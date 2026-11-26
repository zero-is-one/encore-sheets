import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'library_sync.dart';

class WebDavSyncError implements Exception {
  const WebDavSyncError(this.message);
  final String message;
}

class WebDavLibrarySync implements SharedLibrarySyncEndpoint {
  WebDavLibrarySync(
    String address, {
    required String username,
    required String password,
    http.Client? client,
  }) : _folder = _parseFolder(address),
       _authorization = username.isEmpty
           ? null
           : 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
       _client = client ?? http.Client();

  final Uri _folder;
  final String? _authorization;
  final http.Client _client;
  static const _timeout = Duration(seconds: 55);
  static const _manifestLimit = 8 * 1024 * 1024;
  static const _pdfLimit = 50 * 1024 * 1024;
  static const _prefix = 'encoresheets-shared-v1-';
  static final _id = RegExp(r'^[a-zA-Z0-9-]{1,80}$');

  static Uri _parseFolder(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const WebDavSyncError('Enter an HTTPS WebDAV folder URL.');
    }
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  String get folderAddress => _folder.toString();

  @override
  String get stateKey =>
      'sharedLibrarySync-${sha256.convert(utf8.encode(folderAddress))}';

  void close() => _client.close();

  String _filename(String kind, String id, String extension) {
    if (!_id.hasMatch(id)) throw const FormatException('Invalid shared ID');
    return '$_prefix$kind-$id.$extension';
  }

  Future<http.StreamedResponse> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    List<int>? bytes,
    bool allowExisting = false,
  }) async {
    final request = http.Request(method, url)
      ..followRedirects = false
      ..headers.addAll({
        if (_authorization != null) 'Authorization': _authorization,
        ...headers,
      });
    if (bytes != null) request.bodyBytes = bytes;
    final response = await _client.send(request).timeout(_timeout);
    final status = response.statusCode;
    if (status >= 200 && status < 300 || allowExisting && status == 412) {
      return response;
    }
    await response.stream.listen(null).cancel();
    throw WebDavSyncError(switch (status) {
      401 || 403 => 'WebDAV access was denied. Check the credentials and folder permissions.',
      404 => 'The WebDAV folder or shared file was not found.',
      >= 300 && < 400 => 'Use the final WebDAV folder URL without a redirect.',
      _ => 'The WebDAV server returned HTTP $status.',
    });
  }

  Future<Uint8List> _read(http.StreamedResponse response, int limit) async {
    if ((response.contentLength ?? 0) > limit) {
      await response.stream.listen(null).cancel();
      throw const WebDavSyncError('A shared file exceeds the sync size limit.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(_timeout)) {
      if (bytes.length + chunk.length > limit) {
        throw const WebDavSyncError(
          'A shared file exceeds the sync size limit.',
        );
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readDevices() async {
    final listing = await _send(
      'PROPFIND',
      _folder,
      headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      bytes: utf8.encode(
        '<propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>',
      ),
    );
    final xml = XmlDocument.parse(
      utf8.decode(await _read(listing, _manifestLimit)),
    );
    if (xml.rootElement.name.local != 'multistatus' ||
        xml.rootElement.namespaceUri != 'DAV:') {
      throw const WebDavSyncError(
        'The server did not return a WebDAV folder listing.',
      );
    }
    final pattern = RegExp(
      '^${_prefix}device-'
      r'([a-zA-Z0-9-]{1,80})[.]json$',
    );
    final devices = <String, Map<String, dynamic>>{};
    for (final row in xml.rootElement.findElements(
      'response',
      namespaceUri: 'DAV:',
    )) {
      final href = row.getElement('href', namespaceUri: 'DAV:')?.innerText;
      if (href == null) continue;
      final resource = _folder.resolve(href);
      if (resource.scheme != 'https' ||
          resource.origin != _folder.origin ||
          resource.userInfo.isNotEmpty ||
          resource.pathSegments.isEmpty)
        continue;
      final filename = resource.pathSegments.last;
      final id = pattern.firstMatch(filename)?.group(1);
      final path = _folder.resolve(filename);
      if (id == null || resource.path != path.path || devices.containsKey(id))
        continue;
      final manifest = await _send(
        'GET',
        path,
        headers: {'Cache-Control': 'no-cache'},
      );
      devices[id] = jsonDecode(
        utf8.decode(await _read(manifest, _manifestLimit)),
      ) as Map<String, dynamic>;
    }
    return devices;
  }

  @override
  Future<void> writeDevice(String device, Map<String, dynamic> records) async {
    final bytes = utf8.encode(jsonEncode(records));
    if (bytes.length > _manifestLimit) {
      throw const WebDavSyncError(
        'The shared catalog exceeds the sync size limit.',
      );
    }
    final response = await _send(
      'PUT',
      _folder.resolve(_filename('device', device, 'json')),
      headers: {'Content-Type': 'application/json'},
      bytes: bytes,
    );
    await response.stream.drain<void>().timeout(_timeout);
  }

  @override
  Future<void> publishPdf(String id, XFile file) async {
    if (await file.length() > _pdfLimit) {
      throw const WebDavSyncError('Shared PDFs must be 50 MB or smaller.');
    }
    final bytes = await file.readAsBytes();
    final response = await _send(
      'PUT',
      _folder.resolve(_filename('score', id, 'pdf')),
      headers: {'Content-Type': 'application/pdf', 'If-None-Match': '*'},
      bytes: bytes,
      allowExisting: true,
    );
    await response.stream.drain<void>().timeout(_timeout);
    if (response.statusCode == 412) {
      final existing = await fetchPdf(id);
      if (sha256.convert(bytes) !=
          sha256.convert(await existing.readAsBytes())) {
        throw const WebDavSyncError(
          'Two different PDFs share the same score ID.',
        );
      }
    }
  }

  @override
  Future<XFile> fetchPdf(String id) async {
    final name = _filename('score', id, 'pdf');
    final response = await _send('GET', _folder.resolve(name));
    final bytes = await _read(response, _pdfLimit);
    if (!latin1.decode(bytes.take(1024).toList()).contains('%PDF-')) {
      throw const WebDavSyncError('The shared file is not a PDF.');
    }
    return XFile.fromData(bytes, name: name, mimeType: 'application/pdf');
  }
}

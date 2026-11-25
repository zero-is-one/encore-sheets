import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

enum DirectCloudProvider {
  dropbox('Dropbox', ''),
  box('Box', '0');

  const DirectCloudProvider(this.label, this.root);
  final String label;
  final String root;
}

typedef CloudItem = ({String id, String name, bool folder});

class CloudTransferError implements Exception {
  const CloudTransferError(this.message);
  final String message;
}

class CloudProviderSession {
  CloudProviderSession(this.provider, this._token, {http.Client? client})
    : _client = client ?? http.Client();

  final DirectCloudProvider provider;
  final String _token;
  final http.Client _client;
  static const _maxBytes = 50 * 1024 * 1024;
  static const _timeout = Duration(seconds: 55);

  Map<String, String> get _auth => {'Authorization': 'Bearer $_token'};

  void close() => _client.close();

  http.Response _check(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;
    throw CloudTransferError(switch (status) {
      401 => 'The session token is expired or invalid.',
      403 => 'This token lacks permission for the requested file or folder.',
      404 => 'The file or folder is no longer available.',
      409 => 'A file with this name or path already exists.',
      429 => 'The provider is rate limiting requests. Try again shortly.',
      _ => '${provider.label} returned an error ($status).',
    });
  }

  Future<Map<String, dynamic>> _dropboxJson(
    String method,
    Map<String, dynamic> args,
  ) async {
    final response = await _client
        .post(
          Uri.https('api.dropboxapi.com', '/2/files/$method'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode(args),
        )
        .timeout(_timeout);
    return jsonDecode(_check(response).body) as Map<String, dynamic>;
  }

  Future<List<CloudItem>> folder(String id) async {
    final items = <CloudItem>[];
    String? marker;
    final pages = <String>{};
    do {
      final Map<String, dynamic> data;
      if (provider == DirectCloudProvider.dropbox) {
        data = marker == null
            ? await _dropboxJson('list_folder', {'path': id, 'limit': 500})
            : await _dropboxJson('list_folder/continue', {'cursor': marker});
        marker = data['has_more'] == true ? data['cursor'] as String? : null;
      } else {
        final response = await _client
            .get(
              Uri.https('api.box.com', '/2.0/folders/$id/items', {
                'usemarker': 'true',
                'limit': '200',
                'fields': 'id,type,name',
                if (marker != null) 'marker': marker,
              }),
              headers: _auth,
            )
            .timeout(_timeout);
        data = jsonDecode(_check(response).body) as Map<String, dynamic>;
        marker = data['next_marker'] as String?;
        if (marker?.isEmpty == true) marker = null;
      }
      for (final raw in data['entries'] as List? ?? const []) {
        if (raw is! Map) continue;
        final kind =
            raw[provider == DirectCloudProvider.dropbox ? '.tag' : 'type'];
        final name = raw['name'];
        final key =
            raw[provider == DirectCloudProvider.dropbox ? 'path_lower' : 'id'];
        if (name is! String || key is! String) continue;
        if (kind == 'folder' ||
            kind == 'file' && name.toLowerCase().endsWith('.pdf')) {
          items.add((id: key, name: name, folder: kind == 'folder'));
        }
      }
      if (marker != null && !pages.add(marker)) {
        throw const CloudTransferError(
          'The provider returned a repeated folder page.',
        );
      }
    } while (marker != null);
    return items..sort((left, right) {
      if (left.folder != right.folder) return left.folder ? -1 : 1;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
  }

  String _dropboxHeader(Map<String, dynamic> data) =>
      jsonEncode(data).replaceAllMapped(
        RegExp(r'[^\x20-\x7e]'),
        (match) => match[0]!.codeUnits
            .map((unit) => '\\u${unit.toRadixString(16).padLeft(4, '0')}')
            .join(),
      );

  Future<XFile> download(CloudItem item) async {
    final http.Request request;
    if (provider == DirectCloudProvider.dropbox) {
      request =
          http.Request(
              'POST',
              Uri.https('content.dropboxapi.com', '/2/files/download'),
            )
            ..headers.addAll({
              ..._auth,
              'Dropbox-API-Arg': _dropboxHeader({'path': item.id}),
            });
    } else {
      request =
          http.Request(
              'GET',
              Uri.https('api.box.com', '/2.0/files/${item.id}/content'),
            )
            ..headers.addAll(_auth)
            ..followRedirects = false;
    }
    var streamed = await _client.send(request).timeout(_timeout);
    if (provider == DirectCloudProvider.box && streamed.statusCode == 302) {
      final redirect = Uri.tryParse(streamed.headers['location'] ?? '');
      await streamed.stream.drain<void>().timeout(_timeout);
      if (redirect == null ||
          redirect.scheme != 'https' ||
          !(redirect.host.endsWith('.boxcloud.com') ||
              redirect.host.endsWith('.box.com')) ||
          redirect.userInfo.isNotEmpty) {
        throw const CloudTransferError('Box returned an invalid download URL.');
      }
      // The signed download URL authorizes the file itself. The session token
      // stays on the Box API host.
      streamed = await _client
          .send(http.Request('GET', redirect))
          .timeout(_timeout);
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      _check(http.Response('', streamed.statusCode));
    }
    if ((streamed.contentLength ?? 0) > _maxBytes) {
      throw const CloudTransferError(
        'Use the system file picker for PDFs larger than 50 MB.',
      );
    }
    final data = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream.timeout(_timeout)) {
      if (data.length + chunk.length > _maxBytes) {
        throw const CloudTransferError(
          'Use the system file picker for PDFs larger than 50 MB.',
        );
      }
      data.add(chunk);
    }
    final bytes = data.takeBytes();
    if (!latin1.decode(bytes.take(1024).toList()).contains('%PDF-')) {
      throw const CloudTransferError('The download does not contain a PDF.');
    }
    return XFile.fromData(
      bytes,
      path: item.name,
      name: item.name,
      mimeType: 'application/pdf',
    );
  }

  Future<void> upload(String folderId, String name, XFile pdf) async {
    final size = await pdf.length();
    if (size > _maxBytes) {
      throw const CloudTransferError(
        'Use the system file picker for PDFs larger than 50 MB.',
      );
    }
    if (provider == DirectCloudProvider.dropbox) {
      final response = await _client
          .post(
            Uri.https('content.dropboxapi.com', '/2/files/upload'),
            headers: {
              ..._auth,
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': _dropboxHeader({
                'path': '$folderId/$name',
                'mode': 'add',
                'autorename': true,
              }),
            },
            body: await pdf.readAsBytes(),
          )
          .timeout(_timeout);
      _check(response);
      return;
    }
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('upload.box.com', '/api/2.0/files/content'),
          )
          ..headers.addAll(_auth)
          ..fields['attributes'] = jsonEncode({
            'name': name,
            'parent': {'id': folderId},
          })
          ..files.add(
            http.MultipartFile('file', pdf.openRead(), size, filename: name),
          );
    final result = await _client.send(request).timeout(_timeout);
    await result.stream.drain<void>().timeout(_timeout);
    _check(http.Response('', result.statusCode));
  }
}

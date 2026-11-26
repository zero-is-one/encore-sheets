import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

enum DirectCloudProvider {
  dropbox('Dropbox', ''),
  box('Box', '0'),
  googleDrive('Google Drive', 'root'),
  oneDrive('OneDrive', 'root');

  const DirectCloudProvider(this.label, this.root);
  final String label;
  final String root;
  bool get supportsClipboard => this == dropbox || this == box;
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
      409 ||
      412 => 'A file with this name already exists. Choose another name.',
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
    if (provider == DirectCloudProvider.googleDrive ||
        provider == DirectCloudProvider.oneDrive) {
      return _driveFolder(id);
    }
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
    return _sortItems(items);
  }

  List<CloudItem> _sortItems(List<CloudItem> items) =>
      items..sort((left, right) {
        if (left.folder != right.folder) return left.folder ? -1 : 1;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

  Uri _graphItem(String id, String suffix, [Map<String, String>? query]) =>
      Uri.https(
        'graph.microsoft.com',
        '/v1.0/me/drive/${id == 'root' ? 'root' : 'items/$id'}$suffix',
        query,
      );

  String _driveId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_!.~-]+$').hasMatch(id) ||
        id == '.' ||
        id == '..') {
      throw const CloudTransferError(
        'The provider returned an invalid file identifier.',
      );
    }
    return id;
  }

  Future<List<CloudItem>> _driveFolder(String id) async {
    id = _driveId(id);
    final google = provider == DirectCloudProvider.googleDrive;
    final items = <CloudItem>[];
    final pages = <String>{};
    String? marker;
    do {
      final uri = google
          ? Uri.https('www.googleapis.com', '/drive/v3/files', {
              'q': "'$id' in parents and trashed = false",
              'fields': 'nextPageToken,files(id,name,mimeType)',
              'pageSize': '100',
              if (marker != null) 'pageToken': marker,
            })
          : marker == null
          ? _graphItem(id, '/children', {r'$select': 'id,name,folder,file'})
          : Uri.parse(marker);
      if (!google &&
          (uri.scheme != 'https' ||
              uri.authority != 'graph.microsoft.com' ||
              !uri.path.startsWith('/v1.0/'))) {
        throw const CloudTransferError(
          'OneDrive returned an invalid continuation URL.',
        );
      }
      final result = await _driveRequest(http.Request('GET', uri));
      final data = jsonDecode(_check(result).body) as Map<String, dynamic>;
      marker = data[google ? 'nextPageToken' : '@odata.nextLink'] as String?;
      if (marker == '') marker = null;
      if (marker != null && !pages.add(marker)) {
        throw const CloudTransferError(
          'The provider returned a repeated folder page.',
        );
      }
      for (final row in data[google ? 'files' : 'value'] as List? ?? const []) {
        if (row case {'id': final String id, 'name': final String name}) {
          final folder = google
              ? row['mimeType'] == 'application/vnd.google-apps.folder'
              : row['folder'] is Map;
          final pdf = google
              ? row['mimeType'] == 'application/pdf'
              : row['file'] is Map && name.toLowerCase().endsWith('.pdf');
          if (folder || pdf) items.add((id: id, name: name, folder: folder));
        }
      }
    } while (marker != null);
    return _sortItems(items);
  }

  String _dropboxHeader(Map<String, dynamic> data) =>
      jsonEncode(data).replaceAllMapped(
        RegExp(r'[^\x20-\x7e]'),
        (match) => match[0]!.codeUnits
            .map((unit) => '\\u${unit.toRadixString(16).padLeft(4, '0')}')
            .join(),
      );

  Future<http.Response> _driveRequest(http.Request request) async {
    request
      ..followRedirects = false
      ..headers.addAll(_auth);
    return _check(
      await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout),
    );
  }

  http.Request _signedDownload(Object? url) {
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !_downloadHost(uri.host)) {
      throw CloudTransferError(
        '${provider.label} returned an invalid download URL.',
      );
    }
    return http.Request('GET', uri)..followRedirects = false;
  }

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
    } else if (provider == DirectCloudProvider.box) {
      request =
          http.Request(
              'GET',
              Uri.https('api.box.com', '/2.0/files/${item.id}/content'),
            )
            ..headers.addAll(_auth)
            ..followRedirects = false;
    } else if (provider == DirectCloudProvider.oneDrive) {
      final metadata = await _driveRequest(
        http.Request(
          'GET',
          _graphItem(_driveId(item.id), '', {
            r'$select': 'id,@microsoft.graph.downloadUrl',
          }),
        ),
      );
      final data = jsonDecode(metadata.body) as Map<String, dynamic>;
      request = _signedDownload(data['@microsoft.graph.downloadUrl']);
    } else {
      final id = _driveId(item.id);
      request =
          http.Request(
              'GET',
              Uri.https('www.googleapis.com', '/drive/v3/files/$id', {
                'alt': 'media',
              }),
            )
            ..headers.addAll(_auth)
            ..followRedirects = false;
    }
    var streamed = await _client.send(request).timeout(_timeout);
    if (provider == DirectCloudProvider.box && streamed.statusCode == 302) {
      final redirect = streamed.headers['location'];
      await streamed.stream.drain<void>().timeout(_timeout);
      streamed = await _client
          .send(_signedDownload(redirect))
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

  bool _downloadHost(String host) => provider == DirectCloudProvider.box
      ? host.endsWith('.boxcloud.com') || host.endsWith('.box.com')
      : host.endsWith('.1drv.com') ||
            host.endsWith('.sharepoint.com') ||
            host == 'api.onedrive.com' ||
            host == 'onedrive.live.com';

  Future<void> upload(String folderId, String name, XFile pdf) async {
    final size = await pdf.length();
    if (size > _maxBytes) {
      throw const CloudTransferError(
        'Use the system file picker for PDFs larger than 50 MB.',
      );
    }
    if (provider == DirectCloudProvider.googleDrive) {
      final random = Random.secure();
      final boundary =
          'encore-${List.generate(4, (_) => random.nextInt(1 << 30).toRadixString(16)).join('-')}';
      final prefix = utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode({
          'name': name,
          'parents': [_driveId(folderId)],
        })}\r\n'
        '--$boundary\r\nContent-Type: application/pdf\r\n\r\n',
      );
      final suffix = ascii.encode('\r\n--$boundary--\r\n');
      final body = BytesBuilder(copy: false)
        ..add(prefix)
        ..add(await pdf.readAsBytes())
        ..add(suffix);
      final request =
          http.Request(
              'POST',
              Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
                'uploadType': 'multipart',
              }),
            )
            ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
            ..bodyBytes = body.takeBytes();
      await _driveRequest(request);
      return;
    }
    if (provider == DirectCloudProvider.oneDrive) {
      if (name.contains(RegExp(r'[<>:"/\\|?*\x00-\x1f]'))) {
        throw const CloudTransferError('Choose a valid PDF filename.');
      }
      final request =
          http.Request(
              'PUT',
              _graphItem(_driveId(folderId), ':/$name:/content', {
                '@microsoft.graph.conflictBehavior': 'fail',
              }),
            )
            ..headers.addAll({
              'Content-Type': 'application/pdf',
              'If-None-Match': '*',
            })
            ..bodyBytes = await pdf.readAsBytes();
      await _driveRequest(request);
      return;
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

  Future<void> transfer({
    required String sourceId,
    required String filename,
    required String folderId,
    required bool move,
  }) async {
    if (!provider.supportsClipboard) {
      throw const CloudTransferError(
        'Clipboard transfers are unavailable for this provider.',
      );
    }
    if (!filename.toLowerCase().endsWith('.pdf') ||
        filename.contains(RegExp(r'[/\\\x00-\x1f]'))) {
      throw const CloudTransferError('The clipboard file name is invalid.');
    }
    if (provider == DirectCloudProvider.dropbox) {
      if (!sourceId.startsWith('/') ||
          !sourceId.toLowerCase().endsWith('.pdf') ||
          '$folderId/$filename'.toLowerCase() == sourceId.toLowerCase()) {
        throw const CloudTransferError(
          'Open a different folder before pasting this PDF.',
        );
      }
      await _dropboxJson(move ? 'move_v2' : 'copy_v2', {
        'from_path': sourceId,
        'to_path': '$folderId/$filename',
        'autorename': true,
      });
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(sourceId) ||
        !RegExp(r'^\d+$').hasMatch(folderId)) {
      throw const CloudTransferError(
        'The clipboard file or folder is invalid.',
      );
    }
    final request =
        http.Request(
            move ? 'PUT' : 'POST',
            Uri.https(
              'api.box.com',
              '/2.0/files/$sourceId${move ? '' : '/copy'}',
            ),
          )
          ..headers.addAll({..._auth, 'Content-Type': 'application/json'})
          ..body = jsonEncode({
            'parent': {'id': folderId},
          });
    _check(
      await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout),
    );
  }
}

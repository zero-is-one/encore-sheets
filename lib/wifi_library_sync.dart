import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';

import 'app_document_paths.dart';
import 'ensemble_session.dart' show isEnsembleAddress;
import 'library_sync.dart';
import 'score_library.dart';

const _manifestLimit = 8 * 1024 * 1024;
const _pdfLimit = 50 * 1024 * 1024;
const _timeout = Duration(minutes: 2);
const _version = 'encore-wifi-v1';
final _id = RegExp(r'^[a-zA-Z0-9-]{1,80}$');
final _cipher = AesGcm.with256bits();

class WifiSyncException implements Exception {
  const WifiSyncException(this.message);
  final String message;
}

typedef WifiSyncApply = Future<void> Function(
  SharedLibrarySyncEndpoint endpoint,
);

class WifiLibraryHost {
  WifiLibraryHost._(
    this._server,
    this.code,
    this._store,
    this._key,
    this._apply,
  );

  final HttpServer _server;
  final String code;
  final _WifiStore _store;
  final SecretKey _key;
  final WifiSyncApply _apply;
  final _nonces = <String>{};
  final _completed = StreamController<void>.broadcast();
  Stream<void> get completed => _completed.stream;
  late final Timer _expiry = Timer(const Duration(minutes: 15), close);
  bool _closed = false;
  bool _serving = false;

  static Future<WifiLibraryHost> start(
    WifiSyncApply apply, {
    InternetAddress? bindAddress,
    Directory? storeDirectory,
  }) async {
    final local = bindAddress ?? await _localAddress();
    if (local == null) {
      throw const WifiSyncException(
        'Connect this device to a local Wi-Fi network.',
      );
    }
    final store = await _WifiStore.open(
      storeDirectory ??
          Directory('${(await managedDocuments()).path}/wifi-sync'),
    );
    await apply(store);
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final server = await HttpServer.bind(local, 0);
    final code =
        '${local.address}:${server.port}/${base64Url.encode(keyBytes).replaceAll('=', '')}';
    final host = WifiLibraryHost._(
      server,
      code,
      store,
      SecretKey(keyBytes),
      apply,
    );
    host._expiry;
    server.listen(host._handle);
    return host;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expiry.cancel();
    await _server.close(force: true);
    await _completed.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    final segments = request.uri.pathSegments;
    final isPdf = segments.length == 3 && segments[1] == 'pdf';
    final limit = isPdf ? _pdfLimit : _manifestLimit;
    if (_closed ||
        _serving ||
        request.method != 'POST' ||
        segments.isEmpty ||
        segments.first != _version) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    _serving = true;
    try {
      final wire = await _readBytes(request, limit + 28);
      final box = _box(wire);
      final payload = await _cipher.decrypt(
        box,
        secretKey: _key,
        aad: utf8.encode(path),
      );
      final nonce = base64Url.encode(box.nonce);
      if (_nonces.length >= 20000 || !_nonces.add(nonce)) {
        throw const FormatException('Invalid pairing request.');
      }
      final result = await _dispatch(segments.skip(1).toList(), payload);
      final sealed = await _cipher.encrypt(
        result,
        secretKey: _key,
        aad: utf8.encode('$path/$nonce'),
      );
      response.add(sealed.concatenation());
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
    } finally {
      _serving = false;
      await response.close();
    }
  }

  Future<List<int>> _dispatch(List<String> route, List<int> payload) async {
    switch (route) {
      case ['hello']:
        return utf8.encode(_store.stateKey);
      case ['heads']:
        return _encode(await _store.readDevices());
      case ['device', final id]:
        await _store.writeDevice(id, _decode(payload));
        return const [];
      case ['pdf', final id] when payload.isEmpty:
        return (await _store.fetchPdf(id)).readAsBytes();
      case ['pdf', final id]:
        await _store.publishPdf(
          id,
          XFile.fromData(Uint8List.fromList(payload)),
        );
        return const [];
      case ['complete']:
        await _apply(_store);
        if (!_closed) _completed.add(null);
        return const [];
      default:
        throw const FormatException('Unknown sync request.');
    }
  }
}

class WifiLibraryPeer implements SharedLibrarySyncEndpoint {
  WifiLibraryPeer._(this._origin, this._key);
  final Uri _origin;
  final SecretKey _key;
  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..findProxy = (_) => 'DIRECT';
  @override
  late final String stateKey;

  static Future<WifiLibraryPeer> connect(
    String code, {
    bool allowLoopback = false,
  }) async {
    final parts = code.trim().split(RegExp('[:/]'));
    final host = parts.isEmpty ? null : InternetAddress.tryParse(parts.first);
    final port = parts.length == 3 ? int.tryParse(parts[1]) : null;
    if (host == null ||
        !(isEnsembleAddress(host) || allowLoopback && host.isLoopback) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(parts[2])) {
      throw const WifiSyncException(
        'Enter the complete code shown on the other device.',
      );
    }
    final peer = WifiLibraryPeer._(
      Uri(scheme: 'http', host: host.address, port: port),
      SecretKey(base64Url.decode(base64Url.normalize(parts[2]))),
    );
    try {
      final state = utf8.decode(await peer._call('hello'));
      if (!RegExp(r'^wifiLibrarySync-[a-f0-9]{32}$').hasMatch(state)) {
        throw const FormatException('Invalid sync space.');
      }
      peer.stateKey = state;
      return peer;
    } catch (_) {
      peer.close();
      rethrow;
    }
  }

  void close() => _client.close(force: true);

  Future<Uint8List> _call(String route, [List<int> payload = const []]) async {
    final path = '/$_version/$route';
    final limit = route.startsWith('pdf/') ? _pdfLimit : _manifestLimit;
    if (payload.length > limit)
      throw const WifiSyncException('A file is too large to sync.');
    final sealed = await _cipher.encrypt(
      payload,
      secretKey: _key,
      aad: utf8.encode(path),
    );
    final request = await _client
        .postUrl(_origin.replace(path: path))
        .timeout(_timeout);
    request.followRedirects = false;
    final wire = sealed.concatenation();
    request.contentLength = wire.length;
    request.add(wire);
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(_timeout);
      throw const WifiSyncException(
        'The other device rejected the sync request. Check the code and try again.',
      );
    }
    final result = await _readBytes(response, limit + 28);
    final clear = await _cipher.decrypt(
      _box(result),
      secretKey: _key,
      aad: utf8.encode('$path/${base64Url.encode(sealed.nonce)}'),
    );
    return Uint8List.fromList(clear);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readDevices() async =>
      _decode(await _call('heads')).cast<String, Map<String, dynamic>>();

  @override
  Future<void> writeDevice(String device, Map<String, dynamic> records) async {
    await _call('device/${_safeId(device)}', _encode(records));
  }

  @override
  Future<void> publishPdf(String id, XFile file) async {
    if (await file.length() > _pdfLimit) {
      throw const WifiSyncException('Wi-Fi sync supports PDFs up to 50 MB.');
    }
    await _call('pdf/${_safeId(id)}', await file.readAsBytes());
  }

  @override
  Future<XFile> fetchPdf(String id) async =>
      XFile.fromData(await _call('pdf/${_safeId(id)}'), name: '$id.pdf');

  Future<void> complete() async {
    await _call('complete');
  }
}

class _WifiStore implements SharedLibrarySyncEndpoint {
  const _WifiStore(this._folder, this.stateKey);
  final Directory _folder;
  @override
  final String stateKey;

  static Future<_WifiStore> open(Directory folder) async {
    await folder.create(recursive: true);
    final identity = File('${folder.path}/identity');
    if (!await identity.exists()) {
      await identity.writeAsString(ScoreLibrary.newRecordId(), flush: true);
    }
    final value = await identity.readAsString();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
      throw const WifiSyncException(
        'Could not read this device’s Wi-Fi sync identity.',
      );
    }
    return _WifiStore(folder, 'wifiLibrarySync-$value');
  }

  File _file(String prefix, String id) =>
      File('${_folder.path}/$prefix-${_safeId(id)}');

  @override
  Future<Map<String, Map<String, dynamic>>> readDevices() async {
    final heads = <String, Map<String, dynamic>>{};
    await for (final entity in _folder.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('head-')) continue;
      final id = name.substring(5);
      if (!_id.hasMatch(id)) continue;
      if (await entity.length() > _manifestLimit)
        throw const FormatException('Manifest is too large.');
      heads[id] = _decode(await entity.readAsBytes());
    }
    return heads;
  }

  @override
  Future<void> writeDevice(String device, Map<String, dynamic> records) async {
    final data = _encode(records);
    if (data.length > _manifestLimit)
      throw const FormatException('Manifest is too large.');
    await _write(_file('head', device), data);
  }

  @override
  Future<void> publishPdf(String id, XFile file) async {
    if (await file.length() > _pdfLimit) {
      throw const WifiSyncException('Wi-Fi sync supports PDFs up to 50 MB.');
    }
    final destination = _file('pdf', id);
    if (!await destination.exists())
      await _write(destination, await file.readAsBytes());
  }

  @override
  Future<XFile> fetchPdf(String id) async {
    final file = _file('pdf', id);
    if (await file.length() > _pdfLimit)
      throw const FormatException('PDF is too large.');
    return XFile(file.path);
  }

  Future<void> _write(File destination, List<int> bytes) async {
    final staged = File('${destination.path}.tmp');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(destination.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }
}

String _safeId(String value) {
  if (!_id.hasMatch(value))
    throw const FormatException('Invalid sync identifier.');
  return value;
}

Future<InternetAddress?> _localAddress() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final preferred = interfaces.where(
    (item) => item.name == 'en0' || item.name.startsWith('wlan'),
  );
  return [
    ...preferred,
    ...interfaces,
  ].expand((item) => item.addresses).where(isEnsembleAddress).firstOrNull;
}

List<int> _encode(Object value) => utf8.encode(jsonEncode(value));
Map<String, dynamic> _decode(List<int> value) =>
    jsonDecode(utf8.decode(value)) as Map<String, dynamic>;

SecretBox _box(Uint8List wire) {
  if (wire.length < 28)
    throw const FormatException('Invalid encrypted message.');
  return SecretBox.fromConcatenation(wire, nonceLength: 12, macLength: 16);
}

Future<Uint8List> _readBytes(Stream<List<int>> stream, int limit) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream.timeout(_timeout)) {
    if (bytes.length + chunk.length > limit)
      throw const FormatException('Sync message is too large.');
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

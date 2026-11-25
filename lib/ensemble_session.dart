import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef EnsemblePosition = ({
  String? id,
  String title,
  String composer,
  int page,
});

bool isEnsembleAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
    return false;
  }
  final [first, second, ...] = address.rawAddress;
  return first == 10 ||
      first == 172 && second >= 16 && second <= 31 ||
      first == 192 && second == 168;
}

class EnsembleSession {
  static const _endpoint = '/encore-session/v1';
  static const _timeout = Duration(seconds: 3);

  HttpServer? _server;
  HttpClient? _client;
  Timer? _poller;
  String? address;
  String? code;
  bool get leading => _server != null;
  bool get following => _client != null;

  Future<void> lead(EnsemblePosition Function() position) async {
    await close();
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final local = interfaces
        .expand((interface) => interface.addresses)
        .where(isEnsembleAddress)
        .firstOrNull;
    if (local == null) throw StateError('Connect to a local Wi-Fi network.');
    final random = Random.secure();
    final secret = List.generate(
      10,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final server = await HttpServer.bind(local, 0);
    _server = server;
    address = '${local.address}:${server.port}';
    code = secret;
    server.listen((request) async {
      final response = request.response;
      if (request.method != 'GET' ||
          request.uri.path != _endpoint ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $secret') {
        response.statusCode = HttpStatus.notFound;
      } else {
        final current = position();
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'id': current.id,
            'title': current.title,
            'composer': current.composer,
            'page': current.page,
          }),
        );
      }
      await response.close();
    }, onError: (Object _) {});
  }

  Future<void> follow({
    required String address,
    required String code,
    required Future<void> Function(EnsemblePosition) onPosition,
    required void Function() onDisconnect,
  }) async {
    await close();
    final parts = address.trim().split(':');
    final host = InternetAddress.tryParse(parts.first);
    final port = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (host == null ||
        !isEnsembleAddress(host) ||
        port == null ||
        port <= 0 ||
        port > 65535 ||
        !RegExp(r'^[a-fA-F0-9]{10}$').hasMatch(code.trim())) {
      throw const FormatException(
        'Enter the leader’s local address and group code.',
      );
    }
    final uri = Uri(
      scheme: 'http',
      host: host.address,
      port: port,
      path: _endpoint,
    );
    final client = HttpClient()..connectionTimeout = _timeout;
    _client = client;
    this.address = address.trim();
    this.code = code.trim().toLowerCase();
    Future<EnsemblePosition> read() async {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${this.code}',
      );
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(_timeout);
        throw StateError('Check the leader address and group code.');
      }
      final data = BytesBuilder();
      await for (final bytes in response.timeout(_timeout)) {
        if (data.length + bytes.length > 8192) {
          throw const FormatException('Invalid leader response.');
        }
        data.add(bytes);
      }
      final message = jsonDecode(utf8.decode(data.takeBytes()));
      if (message
          case {
            'id': final String? id,
            'title': final String title,
            'composer': final String composer,
            'page': final int page,
          }
          when page > 0) {
        return (id: id, title: title, composer: composer, page: page);
      }
      throw const FormatException('Invalid leader response.');
    }

    try {
      final initial = await read();
      if (_client != client) return;
      await onPosition(initial);
    } catch (_) {
      if (_client == client) await close();
      rethrow;
    }
    if (_client != client) return;
    var failures = 0;
    var pending = false;
    _poller = Timer.periodic(const Duration(milliseconds: 240), (_) async {
      if (pending || _client != client) return;
      pending = true;
      try {
        final position = await read();
        if (_client != client) return;
        await onPosition(position);
        failures = 0;
      } catch (_) {
        if (_client == client && ++failures >= 3) {
          await close();
          onDisconnect();
        }
      } finally {
        pending = false;
      }
    });
  }

  Future<void> close() async {
    _poller?.cancel();
    _poller = null;
    _client?.close(force: true);
    _client = null;
    final server = _server;
    _server = null;
    address = code = null;
    await server?.close(force: true);
  }
}

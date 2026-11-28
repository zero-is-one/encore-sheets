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

typedef NearbyEnsemble = ({String address, String name});
typedef EnsembleFollower = ({String name, bool hasScore});

const _discoveryPort = 43862;
const _discoveryQuery = 'encoresheets:ensemble:discover:1';
final _broadcast = InternetAddress('255.255.255.255');

Future<List<NearbyEnsemble>> discoverEnsembles() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final nearby = <String, NearbyEnsemble>{};
  final listener = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    for (
      var packet = socket.receive();
      packet != null;
      packet = socket.receive()
    ) {
      if (!isEnsembleAddress(packet.address) || packet.data.length > 512)
        continue;
      try {
        final response = jsonDecode(utf8.decode(packet.data));
        if (response
            case {
              'kind': _discoveryQuery,
              'port': final int port,
              'name': final String name,
            }
            when port > 0 && port <= 65535 && name.length <= 80) {
          final address = '${packet.address.address}:$port';
          nearby[address] = (address: address, name: name);
        }
      } on FormatException {
        continue;
      }
    }
  });
  try {
    socket.broadcastEnabled = true;
    for (var attempt = 0; attempt < 3; attempt++) {
      socket.send(utf8.encode(_discoveryQuery), _broadcast, _discoveryPort);
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    return nearby.values.toList();
  } finally {
    await listener.cancel();
    socket.close();
  }
}

class EnsembleSession {
  static const _endpoint = '/encore-session/v1';
  static const _timeout = Duration(seconds: 3);

  HttpServer? _server;
  RawDatagramSocket? _discovery;
  String? _leadingScore;
  String? leaderName;
  final _followers = <String, ({String name, String? score, DateTime seen})>{};

  void _pruneFollowers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 4));
    _followers.removeWhere((_, follower) => follower.seen.isBefore(cutoff));
  }

  List<EnsembleFollower> get followers {
    _pruneFollowers();
    return [
      for (final follower in _followers.values)
        (
          name: follower.name,
          hasScore: _leadingScore != null && follower.score == _leadingScore,
        ),
    ];
  }

  String get _deviceName {
    final name = Platform.localHostname;
    return name.isEmpty
        ? 'EncoreSheets'
        : String.fromCharCodes(name.runes.take(32));
  }

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
    leaderName = _deviceName;
    try {
      final discovery = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
      );
      if (_server != server) {
        discovery.close();
      } else {
        _discovery = discovery;
        final announcement = utf8.encode(
          jsonEncode({
            'kind': _discoveryQuery,
            'port': server.port,
            'name': _deviceName,
          }),
        );
        discovery.listen((event) {
          if (event != RawSocketEvent.read) return;
          for (
            var packet = discovery.receive();
            packet != null;
            packet = discovery.receive()
          ) {
            if (packet.data.length == _discoveryQuery.length &&
                isEnsembleAddress(packet.address) &&
                utf8.decode(packet.data, allowMalformed: true) ==
                    _discoveryQuery) {
              discovery.send(announcement, packet.address, packet.port);
            }
          }
        });
      }
    } on SocketException {
      // The address and group code remain available when discovery is blocked.
    }
    server.listen((request) async {
      final response = request.response;
      if (request.method != 'GET' ||
          request.uri.path != _endpoint ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $secret') {
        response.statusCode = HttpStatus.notFound;
      } else {
        final current = position();
        _leadingScore = current.id;
        _pruneFollowers();
        final follower = request.headers.value('x-encore-follower');
        if (follower != null &&
            follower.length <= 32 &&
            (_followers.containsKey(follower) || _followers.length < 50)) {
          final encodedName = request.headers.value('x-encore-name');
          var name = 'EncoreSheets follower';
          if (encodedName != null && encodedName.length <= 384) {
            try {
              name = Uri.decodeComponent(encodedName);
            } on FormatException {
              // Older or malformed headers use the generic device name.
            }
          }
          _followers[follower] = (
            name: name,
            score: request.headers.value('x-encore-ready'),
            seen: DateTime.now(),
          );
        }
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'id': current.id,
            'title': current.title,
            'composer': current.composer,
            'page': current.page,
            'leader': _deviceName,
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
    required bool Function(EnsemblePosition) hasScore,
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
    final followerId = Random.secure().nextInt(1 << 32).toRadixString(16);
    String? readyScore;
    Future<EnsemblePosition> read() async {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${this.code}',
      );
      request.headers.set('x-encore-follower', followerId);
      request.headers.set('x-encore-name', Uri.encodeComponent(_deviceName));
      if (readyScore != null)
        request.headers.set('x-encore-ready', readyScore!);
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
        final name = message['leader'];
        leaderName = name is String && name.length <= 80
            ? name
            : 'EncoreSheets leader';
        final position = (id: id, title: title, composer: composer, page: page);
        readyScore = hasScore(position) ? id : null;
        return position;
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
    _discovery?.close();
    _discovery = null;
    _followers.clear();
    _leadingScore = null;
    address = code = leaderName = null;
    await server?.close(force: true);
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'score_library.dart';

const assistantPreference = 'assistantConnection';

class AssistantConnection {
  AssistantConnection(this.library);

  final ScoreLibrary library;
  final http.Client _client = http.Client();
  Future<List<AssistantGrant>>? _running;
  bool _closed = false;
  bool _disconnecting = false;

  Future<Uri?> endpoint() async {
    final configuration = await _configuration();
    return configuration == null
        ? null
        : Uri.parse(configuration['origin'] as String).replace(path: '/mcp');
  }

  Future<Map<String, dynamic>?> _configuration() async =>
      (await library.storage.readPreferences())[assistantPreference]
          as Map<String, dynamic>?;

  Future<void> connect(String address, String token) async {
    if (await _configuration() != null) {
      throw StateError('Disconnect the existing server first.');
    }
    final origin = Uri.tryParse(address.trim());
    if (origin == null ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !const ['', '/', '/mcp', '/mcp/'].contains(origin.path) ||
        (origin.scheme != 'https' &&
            !(origin.scheme == 'http' &&
                const [
                  'localhost',
                  '127.0.0.1',
                  '::1',
                ].contains(origin.host)))) {
      throw const FormatException('Enter the HTTPS server address.');
    }
    final trimmed = token.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{43}$').hasMatch(trimmed)) {
      throw const FormatException('Enter the tablet connection token.');
    }
    final configuration = <String, dynamic>{
      'origin': origin.origin,
      'token': trimmed,
    };
    await _post(configuration, 'sync', _snapshot());
    await library.updatePreferences({assistantPreference: configuration});
  }

  Future<String> pairingCode() async {
    final configuration = await _configuration();
    if (configuration == null) throw StateError('Connect a server first.');
    final result = await _post(configuration, 'pair');
    return result['code'] as String;
  }

  Future<void> revoke(String id) async {
    final configuration = await _configuration();
    if (configuration == null) throw StateError('Connect a server first.');
    await _post(configuration, 'revoke', {'id': id});
  }

  Future<void> disconnect() async {
    final configuration = await _configuration();
    if (configuration == null) return;
    _disconnecting = true;
    try {
      try {
        await _running;
      } catch (_) {
        // Disconnect can still succeed after a failed catalog sync.
      }
      await _post(configuration, 'disconnect');
      await library.updatePreferences({assistantPreference: null});
    } finally {
      _disconnecting = false;
    }
  }

  Future<List<AssistantGrant>> sync() {
    if (_closed || _disconnecting) return Future.value(const []);
    final active = _running;
    if (active != null) return active;
    final sync = _sync().whenComplete(() => _running = null);
    _running = sync;
    return sync;
  }

  Future<List<AssistantGrant>> _sync() async {
    final configuration = await _configuration();
    if (configuration == null || _closed) return const [];
    final receipts = Map<String, String>.from(
      configuration['receipts'] as Map? ?? const {},
    );
    final hadReceipts = receipts.isNotEmpty;
    var response = await _post(configuration, 'sync', _snapshot(receipts));
    receipts.clear();
    for (final raw in response['pending'] as List) {
      if (_closed || _disconnecting) break;
      final request = raw as Map<String, dynamic>;
      final id = request['id'] as String;
      if (!RegExp(r'^[a-zA-Z0-9_-]{43}$').hasMatch(id)) {
        throw const FormatException('Invalid setlist request ID.');
      }
      final result = await library.applyAssistantSetlist(
        Setlist(
          'assistant-$id',
          request['name'] as String,
          (request['score_ids'] as List).cast<String>(),
        ),
      );
      receipts[id] = result ? 'saved' : 'rejected';
    }
    if (receipts.isNotEmpty || hadReceipts) {
      final savedConfiguration = {...configuration, 'receipts': receipts};
      await library.updatePreferences({
        assistantPreference: savedConfiguration,
      });
    }
    if (receipts.isNotEmpty && !_closed && !_disconnecting) {
      response = await _post(configuration, 'sync', _snapshot(receipts));
      await library.updatePreferences({
        assistantPreference: {...configuration, 'receipts': <String, String>{}},
      });
    }
    return [
      for (final raw in response['connections'] as List)
        AssistantGrant(
          raw['id'] as String,
          raw['name'] as String,
          (raw['scope'] as String).split(' ').contains('setlists:write'),
        ),
    ];
  }

  Map<String, dynamic> _snapshot([Map<String, String> receipts = const {}]) {
    final scores = library.recent.where((score) => score.validUntil == null);
    final scoreIds = scores.map((score) => score.id).toSet();
    return {
      'scores': [
        for (final score in scores)
          {
            'id': score.id,
            'title': _limit(score.title, 200),
            'composer': _limit(score.metadata['composer'] ?? '', 200),
            'duration': _limit(score.metadata['duration'] ?? '', 40),
          },
      ],
      'setlists': [
        for (final setlist in library.setlists)
          {
            'id': setlist.id,
            'name': _limit(setlist.name, 200),
            'score_ids': setlist.scores.where(scoreIds.contains).toList(),
          },
      ],
      'receipts': receipts,
    };
  }

  String _limit(String value, int length) =>
      value.length <= length ? value : value.substring(0, length);

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> configuration,
    String path, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final url = Uri.parse(configuration['origin'] as String)
        .replace(path: '/device/$path');
    final request = http.Request('POST', url)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer ${configuration['token']}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(payload);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (path == 'disconnect' && response.statusCode == 401) return {};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Assistant server returned HTTP ${response.statusCode}.',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() {
    _closed = true;
    _client.close();
  }
}

class AssistantGrant {
  const AssistantGrant(this.id, this.name, this.canCreate);
  final String id;
  final String name;
  final bool canCreate;
}

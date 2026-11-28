import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr/qr.dart';

import 'wifi_library_sync.dart';

class WifiLibrarySyncScreen extends StatefulWidget {
  const WifiLibrarySyncScreen({super.key, required this.apply});

  final WifiSyncApply apply;

  @override
  State<WifiLibrarySyncScreen> createState() => _WifiLibrarySyncScreenState();
}

class _WifiLibrarySyncScreenState extends State<WifiLibrarySyncScreen> {
  final _code = TextEditingController();
  WifiLibraryHost? _host;
  StreamSubscription<void>? _completions;
  WifiLibraryPeer? _peer;
  bool _busy = false;
  bool _joining = false;
  bool _includeMarkings = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _message = error is WifiSyncException
            ? error.message
            : 'Could not sync. Keep both devices on the same Wi-Fi network, '
                  'allow local network access, and check the pairing code.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run(() async {
    final host = await WifiLibraryHost.start(
      widget.apply,
      includeMarkings: _includeMarkings,
    );
    if (!mounted) {
      await host.close();
      return;
    }
    _host = host;
    _completions = host.completed.listen(
      (_) {
        if (mounted)
          setState(() => _message = 'Both libraries are up to date.');
      },
      onDone: () {
        if (!mounted || _host != host) return;
        setState(() {
          _host = null;
          _message = 'Pairing ended. Show a new code to sync again.';
        });
      },
    );
  });

  Future<void> _stop() => _run(() async {
    final host = _host;
    _host = null;
    await _completions?.cancel();
    await host?.close();
  });

  Future<void> _scan() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _PairingScanner()));
    if (mounted && result != null) setState(() => _code.text = result);
  }

  Future<void> _join() => _run(() async {
    final peer = await WifiLibraryPeer.connect(_code.text);
    _peer = peer;
    try {
      final heads = await peer.readDevices();
      if (!mounted) return;
      final scores = <String, ({int revision, String device, bool deleted})>{};
      for (final head in heads.entries) {
        for (final row in head.value.entries) {
          final parts = row.key.split(':');
          if (parts.length != 3 ||
              parts.first != 's' ||
              parts.last != 'deletedAt')
            continue;
          if (row.value case {
            'revision': final int revision,
            'data': {'value': final value},
          }) {
            final last = scores[parts[1]];
            if (last == null ||
                revision > last.revision ||
                revision == last.revision &&
                    head.key.compareTo(last.device) > 0) {
              scores[parts[1]] = (
                revision: revision,
                device: head.key,
                deleted: value != null,
              );
            }
          }
        }
      }
      final count = scores.values.where((row) => !row.deleted).length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Sync both libraries?'),
          content: Text(
            'The other device has $count available scores. EncoreSheets will '
            'merge scores, metadata, and setlists on both devices. '
            'Previously synced deletions also apply. '
            '${peer.includesMarkings ? 'This personal pairing also transfers ink layers and page notes. If both devices changed the markings, the other version is kept in Recently updated on the device that detects the conflict.' : 'Ink and page notes stay on each device.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Sync now'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await widget.apply(peer);
      await peer.complete();
      if (mounted) _message = 'Both libraries are up to date.';
    } finally {
      peer.close();
      _peer = null;
    }
  });

  @override
  void dispose() {
    unawaited(_completions?.cancel());
    unawaited(_host?.close());
    _peer?.close();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Pair over Wi-Fi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Keep both devices on the same Wi-Fi network with this screen open. '
              'Scores, metadata, and setlists sync. Shared pairing keeps ink, '
              'page notes, and reading positions on each device.',
            ),
            const SizedBox(height: 16),
            if (_host == null && !_joining)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Personal sync'),
                subtitle: const Text(
                  'Include editable ink and page notes when pairing with your own device.',
                ),
                value: _includeMarkings,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _includeMarkings = value),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_message case final message?) Text(message),
            if (_host case final host?) ...[
              const Text(
                'On the other device, tap Join another device and scan this code. '
                'The code expires after 15 minutes.',
              ),
              Center(
                child: Semantics(
                  image: true,
                  label: 'Wi-Fi pairing QR code',
                  child: CustomPaint(
                    size: const Size.square(220),
                    painter: _PairingQr(host.code),
                  ),
                ),
              ),
              SelectableText(host.code),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await Clipboard.setData(ClipboardData(text: host.code));
                        _message = 'Pairing code copied.';
                      }),
                icon: const Icon(Icons.copy),
                label: const Text('Copy pairing code'),
              ),
              TextButton(
                onPressed: _busy ? null : _stop,
                child: const Text('Stop pairing'),
              ),
            ] else if (_joining) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR code'),
              ),
              TextField(
                controller: _code,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Or paste pairing code',
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : _join,
                child: const Text('Review sync'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _joining = false),
                child: const Text('Back to pairing options'),
              ),
            ] else ...[
              FilledButton(
                onPressed: _busy ? null : _start,
                child: const Text('Show pairing code'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => setState(() => _joining = true),
                child: const Text('Join another device'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PairingQr extends CustomPainter {
  _PairingQr(this.code);
  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrImage(
      QrCode.fromData(data: code, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    final unit = size.shortestSide / (qr.moduleCount + 8);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final ink = Paint()..color = Colors.black;
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var column = 0; column < qr.moduleCount; column++) {
        if (qr.isDark(row, column)) {
          canvas.drawRect(
            Rect.fromLTWH((column + 4) * unit, (row + 4) * unit, unit, unit),
            ink,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PairingQr oldDelegate) => code != oldDelegate.code;
}

class _PairingScanner extends StatefulWidget {
  const _PairingScanner();

  @override
  State<_PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<_PairingScanner> {
  var _returned = false;
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan pairing code')),
    body: MobileScanner(
      controller: _scanner,
      onDetect: (capture) {
        if (_returned || !mounted) return;
        final code = capture.barcodes
            .map((barcode) => barcode.rawValue)
            .whereType<String>()
            .where(
              (value) =>
                  RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+/[A-Za-z0-9_-]{43}$')
                      .hasMatch(value),
            )
            .firstOrNull;
        if (code == null) return;
        _returned = true;
        Navigator.pop(context, code);
      },
    ),
  );
}

import 'package:material_ui/material_ui.dart';

import 'library_sync.dart';

class LibrarySyncScreen extends StatefulWidget {
  const LibrarySyncScreen({
    super.key,
    required this.endpoint,
    required this.refresh,
    required this.reset,
    this.lastSuccess,
  });

  final AppleLibrarySync endpoint;
  final Future<DateTime> Function() refresh;
  final Future<void> Function() reset;
  final DateTime? lastSuccess;

  @override
  State<LibrarySyncScreen> createState() => _LibrarySyncScreenState();
}

class _LibrarySyncScreenState extends State<LibrarySyncScreen> {
  bool _configured = false;
  bool _busy = true;
  String? _error;
  late DateTime? _lastSuccess = widget.lastSuccess;

  @override
  void initState() {
    super.initState();
    _run(() async => _configured = await widget.endpoint.configured);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted)
        setState(
          () => _error = 'Could not sync. Check the selected folder in Files.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Device sync')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _configured
                  ? 'Sync folder connected'
                  : 'Choose an iCloud Drive folder',
            ),
            const Text(
              'Choose the same folder on each iPhone or iPad. Scores, annotations and setlists sync while EncoreSheets is open.',
            ),
            if (_lastSuccess case final date?)
              Text(
                'Last sync ${MaterialLocalizations.of(context).formatShortDate(date)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
              ),
            const SizedBox(height: 16),
            if (!_configured)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        if (await widget.endpoint.chooseFolder()) {
                          await widget.reset();
                          _configured = true;
                          _lastSuccess = await widget.refresh();
                        }
                      }),
                child: const Text('Choose sync folder'),
              )
            else ...[
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () async => _lastSuccess = await widget.refresh(),
                      ),
                child: const Text('Refresh now'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.endpoint.disconnect();
                        await widget.reset();
                        _configured = false;
                        _lastSuccess = null;
                      }),
                child: const Text('Disconnect folder'),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) Text(error),
          ],
        ),
      ),
    ),
  );
}

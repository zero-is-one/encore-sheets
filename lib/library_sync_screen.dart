import 'package:material_ui/material_ui.dart';

import 'library_sync.dart';
import 'webdav_library_sync.dart';
import 'wifi_library_sync_screen.dart';
import 'wifi_library_sync.dart';

class LibrarySyncScreen extends StatefulWidget {
  const LibrarySyncScreen({
    super.key,
    required this.endpoint,
    required this.webDav,
    required this.setWebDav,
    required this.refresh,
    required this.reset,
    this.syncOverWifi,
    this.lastSuccess,
  });

  final AppleLibrarySync? endpoint;
  final WebDavLibrarySync? webDav;
  final Future<void> Function(WebDavLibrarySync?) setWebDav;
  final Future<DateTime> Function() refresh;
  final Future<void> Function() reset;
  final WifiSyncApply? syncOverWifi;
  final DateTime? lastSuccess;

  @override
  State<LibrarySyncScreen> createState() => _LibrarySyncScreenState();
}

class _LibrarySyncScreenState extends State<LibrarySyncScreen> {
  bool _configured = false;
  bool _busy = true;
  String? _error;
  late DateTime? _lastSuccess = widget.lastSuccess;
  late WebDavLibrarySync? _webDav = widget.webDav;
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _address.text = _webDav?.folderAddress ?? '';
    _run(() async => _configured = await widget.endpoint?.configured ?? false);
  }

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connectWebDav() => _run(() async {
    final endpoint = WebDavLibrarySync(
      _address.text,
      username: _username.text.trim(),
      password: _password.text,
    );
    await widget.setWebDav(endpoint);
    if (!mounted) return;
    _webDav = endpoint;
    _password.clear();
    _lastSuccess = await widget.refresh();
  });

  Future<void> _disconnectWebDav() => _run(() async {
    await widget.setWebDav(null);
    _webDav = null;
    _lastSuccess = null;
  });

  Future<void> _refresh() => _run(() async {
    _lastSuccess = await widget.refresh();
  });

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
          () => _error = error is WebDavSyncError
              ? error.message
              : 'Could not sync. Check the connection and folder access.',
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
            if (widget.syncOverWifi case final sync?) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wifi),
                title: const Text('Pair over Wi-Fi'),
                subtitle: const Text('Sync two devices on the same network.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WifiLibrarySyncScreen(apply: sync),
                        ),
                      ),
              ),
              const Divider(),
            ],
            const Text('Shared library'),
            const Text(
              'Connect each device to the same WebDAV folder to share scores, metadata, and setlists. Ink, page notes, and reader settings stay on each device.',
            ),
            if (_lastSuccess case final date?)
              Text(
                'Last sync ${MaterialLocalizations.of(context).formatShortDate(date)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
              ),
            const SizedBox(height: 16),
            if (_webDav case final endpoint?) ...[
              Text(endpoint.folderAddress),
              FilledButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh now'),
              ),
              TextButton(
                onPressed: _busy ? null : _disconnectWebDav,
                child: const Text('Disconnect WebDAV'),
              ),
            ] else ...[
              const Text(
                'Enter your WebDAV credentials each time you start the app.',
              ),
              TextField(
                controller: _address,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'HTTPS WebDAV folder URL',
                ),
              ),
              TextField(
                controller: _username,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              FilledButton(
                onPressed: _busy ? null : _connectWebDav,
                child: const Text('Connect WebDAV'),
              ),
              if (widget.endpoint case final apple?) ...[
                const Divider(),
                const Text('iCloud Drive'),
                const Text(
                  'Use the same iCloud Drive folder on Apple devices to sync scores, annotations, and setlists.',
                ),
                if (_configured) ...[
                  TextButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text('Refresh iCloud folder'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await apple.disconnect();
                            await widget.reset();
                            _configured = false;
                            _lastSuccess = null;
                          }),
                    child: const Text('Disconnect iCloud folder'),
                  ),
                ] else
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            if (await apple.chooseFolder()) {
                              await widget.reset();
                              _configured = true;
                              _lastSuccess = await widget.refresh();
                            }
                          }),
                    child: const Text('Choose iCloud folder'),
                  ),
              ],
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) Text(error),
          ],
        ),
      ),
    ),
  );
}

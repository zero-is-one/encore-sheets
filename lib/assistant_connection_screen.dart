import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'assistant_connection.dart';

class AssistantConnectionScreen extends StatefulWidget {
  const AssistantConnectionScreen({super.key, required this.connection});

  final AssistantConnection connection;

  @override
  State<AssistantConnectionScreen> createState() =>
      _AssistantConnectionScreenState();
}

class _AssistantConnectionScreenState extends State<AssistantConnectionScreen> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  Uri? _endpoint;
  List<AssistantGrant> _grants = [];
  String? _code;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _endpoint = await widget.connection.endpoint();
    if (_endpoint != null) _grants = await widget.connection.sync();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _error = switch (error) {
        FormatException(:final message) => message,
        StateError(:final message) => message,
        _ => 'Could not reach the assistant server. Check your connection.',
      };
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect assistant server?'),
        content: const Text(
          'This revokes all assistant connections, removes the online catalog, '
          'and cancels pending requests. Saved setlists stay on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.connection.disconnect();
      _endpoint = null;
      _code = null;
      _grants = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final endpoint = _endpoint;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Connections')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (endpoint == null) ...[
                const Text(
                  'Connect your EncoreSheets assistant server using the tablet '
                  'token issued by its operator. Connecting shares score titles, '
                  'composers, durations, and setlists. PDFs and annotations stay '
                  'on this device.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _address,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                  ),
                ),
                TextField(
                  controller: _token,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Tablet connection token',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.connection.connect(
                            _address.text,
                            _token.text,
                          );
                          if (!mounted) return;
                          _token.clear();
                          await _refresh();
                        }),
                  child: const Text('Connect server'),
                ),
              ] else ...[
                const Text(
                  'Add the MCP address in your assistant’s integration settings. '
                  'When its browser opens the connection page, enter a new code '
                  'from here and choose whether to allow setlist requests.',
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('MCP address'),
                  subtitle: SelectableText(endpoint.toString()),
                  trailing: IconButton(
                    tooltip: 'Copy MCP address',
                    onPressed: () => _copy(endpoint.toString()),
                    icon: const Icon(Icons.copy),
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          _code = await widget.connection.pairingCode();
                        }),
                  child: const Text('Generate connection code'),
                ),
                if (_code case final code?)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('One-time code valid for 10 minutes'),
                    subtitle: SelectableText(code),
                    trailing: IconButton(
                      tooltip: 'Copy connection code',
                      onPressed: () => _copy(code),
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text('Connected assistants'),
                if (_grants.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No assistants connected yet.'),
                  ),
                for (final grant in _grants)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(grant.name),
                    subtitle: Text(
                      grant.canCreate
                          ? 'Read library and request setlists'
                          : 'Read library',
                    ),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await widget.connection.revoke(grant.id);
                              await _refresh();
                            }),
                      child: const Text('Revoke'),
                    ),
                  ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _run(_refresh),
                  child: const Text('Sync now'),
                ),
                TextButton(
                  onPressed: _busy ? null : _disconnect,
                  child: const Text('Disconnect server'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

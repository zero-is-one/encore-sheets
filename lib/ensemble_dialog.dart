import 'package:material_ui/material_ui.dart';

import 'ensemble_session.dart';

enum EnsembleFollowMode {
  pages('Page turns'),
  scores('Score changes'),
  both('Scores and page turns');

  const EnsembleFollowMode(this.label);
  final String label;
}

class EnsembleDialog extends StatefulWidget {
  const EnsembleDialog({
    super.key,
    required this.session,
    required this.lead,
    required this.follow,
  });

  final EnsembleSession session;
  final Future<void> Function() lead;
  final Future<void> Function(String, String, EnsembleFollowMode) follow;

  @override
  State<EnsembleDialog> createState() => _EnsembleDialogState();
}

class _EnsembleDialogState extends State<EnsembleDialog> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  EnsembleFollowMode _mode = EnsembleFollowMode.both;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error =
          'Could not connect. Check the address, code, and local Wi-Fi access.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Ensemble sync'),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?) Text(error),
              if (session.leading || session.following) ...[
                Text(session.leading ? 'Leading' : 'Following'),
                SelectableText(session.address ?? ''),
                if (session.leading)
                  SelectableText('Group code ${session.code}'),
              ] else ...[
                const Text(
                  'Connect both devices to the same Wi-Fi network. Load a copy of the score on each device.',
                ),
                TextButton(
                  onPressed: _busy ? null : () => _run(widget.lead),
                  child: const Text('Lead a session'),
                ),
                TextField(
                  controller: _address,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Leader address',
                    hintText: '192.168.1.23:12345',
                  ),
                ),
                TextField(
                  controller: _code,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Group code'),
                ),
                DropdownButton<EnsembleFollowMode>(
                  value: _mode,
                  items: [
                    for (final mode in EnsembleFollowMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: _busy
                      ? null
                      : (mode) => setState(() => _mode = mode!),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.follow(_address.text, _code.text, _mode),
                        ),
                  child: const Text('Join session'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (session.leading || session.following)
            TextButton(
              onPressed: _busy ? null : () => _run(session.close),
              child: Text(session.leading ? 'End session' : 'Leave session'),
            ),
          FilledButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

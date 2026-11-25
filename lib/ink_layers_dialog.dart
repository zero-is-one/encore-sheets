import 'package:material_ui/material_ui.dart';

import 'page_ink.dart';

typedef InkLayerSettings = ({
  List<InkLayer> layers,
  String? active,
  List<InkLayerChange> changes,
});

class InkLayersDialog extends StatefulWidget {
  const InkLayersDialog({
    super.key,
    required this.layers,
    required this.active,
  });

  final List<InkLayer> layers;
  final String? active;

  @override
  State<InkLayersDialog> createState() => _InkLayersDialogState();
}

class _InkLayersDialogState extends State<InkLayersDialog> {
  late final _layers = [...widget.layers];
  late String? _active = widget.active;
  final _changes = <InkLayerChange>[];
  var _serial = DateTime.now().microsecondsSinceEpoch;

  Future<String?> _askName(String title, {String initial = ''}) {
    var name = initial;
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => name = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, name),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _add({InkLayer? source}) async {
    final title = source == null ? 'New layer' : 'Copy layer';
    final name = await _askName(
      title,
      initial: source == null ? '' : '${source.name} copy',
    );
    if (!mounted || name == null || name.isEmpty) return;
    final id = 'layer-${_serial++}';
    setState(() {
      _layers.add((id: id, name: name, visible: true));
      _active = id;
      if (source != null) _changes.add((target: id, source: source.id));
    });
  }

  Future<void> _action(String action, InkLayer layer) async {
    final index = _layers.indexOf(layer);
    if (action == 'copy') {
      await _add(source: layer);
      return;
    }
    if (action == 'rename') {
      final name = await _askName('Rename layer', initial: layer.name);
      if (mounted && name != null && name.isNotEmpty) {
        setState(
          () => _layers[index] = (
            id: layer.id,
            name: name,
            visible: layer.visible,
          ),
        );
      }
      return;
    }
    if (action == 'replace') {
      final source = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: Text('Replace ${layer.name} with'),
          children: [
            for (final other in _layers)
              if (other.id != layer.id)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, other.id),
                  child: Text(other.name),
                ),
          ],
        ),
      );
      if (mounted && source != null) {
        setState(() => _changes.add((target: layer.id, source: source)));
      }
      return;
    }
    setState(() {
      switch (action) {
        case 'up':
          _layers.insert(index - 1, _layers.removeAt(index));
        case 'down':
          _layers.insert(index + 1, _layers.removeAt(index));
        case 'clear':
          _changes.add((target: layer.id, source: null));
        case 'delete':
          _changes.add((target: layer.id, source: null));
          _layers.removeAt(index);
          if (_active == layer.id)
            _active = _layers.where((item) => item.visible).firstOrNull?.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Annotation layers'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, layer) in _layers.indexed)
              ListTile(
                title: Text(layer.name),
                subtitle:
                    _changes.any(
                      (change) =>
                          change.target == layer.id && change.source == null,
                    )
                    ? const Text('Clear on save')
                    : null,
                selected: _active == layer.id,
                onTap: layer.visible
                    ? () => setState(() => _active = layer.id)
                    : null,
                leading: IconButton(
                  tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                  icon: Icon(
                    layer.visible ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() {
                    _layers[index] = (
                      id: layer.id,
                      name: layer.name,
                      visible: !layer.visible,
                    );
                    if (_active == layer.id) _active = null;
                    _active ??= _layers
                        .where((item) => item.visible)
                        .firstOrNull
                        ?.id;
                  }),
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Layer actions',
                  onSelected: (action) => _action(action, layer),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Duplicate'),
                    ),
                    PopupMenuItem(
                      value: 'replace',
                      enabled: _layers.length > 1,
                      child: const Text('Replace from layer'),
                    ),
                    PopupMenuItem(
                      value: 'up',
                      enabled: index > 0,
                      child: const Text('Move earlier'),
                    ),
                    PopupMenuItem(
                      value: 'down',
                      enabled: index + 1 < _layers.length,
                      child: const Text('Move later'),
                    ),
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear marks'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: _layers.length > 1,
                      child: const Text('Delete layer'),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add layer'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final InkLayerSettings settings = (
            layers: _layers,
            active: _active,
            changes: _changes,
          );
          Navigator.pop(context, settings);
        },
        child: const Text('Save'),
      ),
    ],
  );
}

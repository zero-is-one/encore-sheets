import 'package:material_ui/material_ui.dart';

import 'page_ink.dart';

class TextAnnotationDialog extends StatefulWidget {
  const TextAnnotationDialog({
    super.key,
    required this.initial,
    required this.existing,
  });

  final PageText initial;
  final bool existing;

  @override
  State<TextAnnotationDialog> createState() => _TextAnnotationDialogState();
}

class _TextAnnotationDialogState extends State<TextAnnotationDialog> {
  late final _text = TextEditingController(text: widget.initial.value);
  late var _x = widget.initial.position.dx.clamp(0.0, .98);
  late var _y = widget.initial.position.dy.clamp(0.0, .98);
  late var _size = widget.initial.size;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update,
  ) => Row(
    children: [
      SizedBox(width: 80, child: Text(label)),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          onChanged: (value) => setState(() => update(value)),
          semanticFormatterCallback: (value) =>
              '$label ${(value * 100).round()} percent',
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing ? 'Edit text annotation' : 'Add text annotation',
    ),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              stylusHandwritingEnabled: true,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Text'),
            ),
            _slider('Size', _size, .012, .08, (value) => _size = value),
            _slider('Horizontal', _x, 0, .98, (value) => _x = value),
            _slider('Vertical', _y, 0, .98, (value) => _y = value),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.existing)
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (annotation: null, delete: true)),
          child: const Text('Delete'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _text.text.trim().isEmpty
            ? null
            : () {
                final PageText annotation = (
                  value: _text.text.trim(),
                  position: Offset(_x, _y),
                  size: _size,
                );
                Navigator.pop(context, (annotation: annotation, delete: false));
              },
        child: const Text('Save'),
      ),
    ],
  );
}

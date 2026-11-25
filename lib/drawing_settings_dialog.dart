import 'package:material_ui/material_ui.dart';

import 'drawing_settings.dart';

class DrawingSettingsDialog extends StatefulWidget {
  const DrawingSettingsDialog({super.key, required this.initial});

  final DrawingSettings initial;

  @override
  State<DrawingSettingsDialog> createState() => _DrawingSettingsDialogState();
}

class _DrawingSettingsDialogState extends State<DrawingSettingsDialog> {
  late var _settings = widget.initial;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _color = TextEditingController();
  late double _width;
  late double _opacity;
  bool _newPreset = false;

  @override
  void initState() {
    super.initState();
    _load(_settings.selected);
  }

  void _load(int selected) {
    _settings = _settings.copyWith(selected: selected);
    final preset = _settings.preset;
    _name.text = preset.name;
    _color.text =
        '#${preset.color.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    _width = preset.width;
    _opacity = preset.opacity;
  }

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    super.dispose();
  }

  int? get _rgb {
    final hex = _color.text.trim().replaceFirst(RegExp('^#'), '');
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
        ? int.parse(hex, radix: 16)
        : null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final presets = [..._settings.presets];
    final preset = DrawingPreset(
      _name.text.trim(),
      _width,
      _rgb!,
      opacity: _opacity,
    );
    final index = _newPreset ? presets.length : _settings.selected;
    if (_newPreset) {
      presets.add(preset);
    } else {
      presets[index] = preset;
    }
    Navigator.pop(
      context,
      _settings.copyWith(presets: presets, selected: index),
    );
  }

  Widget _switch(
    String title,
    bool current,
    DrawingSettings Function(bool) update,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: current,
    onChanged: (value) => setState(() => _settings = update(value)),
  );

  @override
  Widget build(BuildContext context) {
    final selectedColor = _rgb ?? 0;
    return AlertDialog(
      title: const Text('Drawing presets and stylus'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButton<int>(
                  value: _settings.selected,
                  isExpanded: true,
                  onChanged: (index) => setState(() => _load(index!)),
                  items: [
                    for (final (index, preset) in _settings.presets.indexed)
                      DropdownMenuItem(value: index, child: Text(preset.name)),
                  ],
                ),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Preset name'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                TextFormField(
                  controller: _color,
                  decoration: const InputDecoration(labelText: 'Color (hex)'),
                  onChanged: (_) => setState(() {}),
                  validator: (_) => _rgb == null
                      ? 'Enter a six-digit color, such as #244A91'
                      : null,
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (label, hex) in const [
                      ('Red', '#9B352E'),
                      ('Blue', '#244A91'),
                      ('Black', '#262626'),
                      ('Green', '#326447'),
                      ('Gold', '#A16C12'),
                    ])
                      TextButton(
                        onPressed: () => setState(() => _color.text = hex),
                        child: Text(label),
                      ),
                  ],
                ),
                Text('Width · ${(_width * 100).toStringAsFixed(1)}% of page'),
                Slider(
                  value: _width,
                  min: .001,
                  max: .04,
                  onChanged: (v) => setState(() => _width = v),
                ),
                Text('Opacity · ${(_opacity * 100).round()}%'),
                Slider(
                  value: _opacity,
                  min: .05,
                  max: 1,
                  onChanged: (v) => setState(() => _opacity = v),
                ),
                Container(
                  height: (_width * 340).clamp(1, 15),
                  decoration: BoxDecoration(
                    color: Color(0xff000000 | selectedColor)
                        .withValues(alpha: _opacity),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                _switch('Save as a new preset', _newPreset, (v) {
                  _newPreset = v;
                  return _settings;
                }),
                const Divider(),
                _switch(
                  'Use stylus pressure',
                  _settings.pressure,
                  (v) => _settings.copyWith(pressure: v),
                ),
                _switch(
                  'Use stylus tilt',
                  _settings.tilt,
                  (v) => _settings.copyWith(tilt: v),
                ),
                _switch(
                  'Stylus shortcut switches tools',
                  _settings.switchTools,
                  (v) => _settings.copyWith(switchTools: v),
                ),
                _switch(
                  'Start markup with a stylus',
                  _settings.autoEnter,
                  (v) => _settings.copyWith(autoEnter: v),
                ),
                _switch(
                  'Return to reading when the stylus lifts',
                  _settings.autoExit,
                  (v) => _settings.copyWith(autoExit: v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

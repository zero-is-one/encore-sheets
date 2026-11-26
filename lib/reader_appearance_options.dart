import 'package:material_ui/material_ui.dart';

enum ReaderPalette {
  classic(
    'Classic',
    Color(0xff202a28),
    Color(0xff2e3a36),
    Color(0xfff0eddf),
    Color(0xffe9bd75),
    false,
  ),
  arctic(
    'Arctic',
    Color(0xff1d2935),
    Color(0xff283c50),
    Color(0xffeff7ff),
    Color(0xff8cc8ff),
    false,
  ),
  daylight(
    'Daylight',
    Color(0xffefeee6),
    Color(0xfffaf7ef),
    Color(0xff261e17),
    Color(0xff765021),
    true,
  ),
  contrast(
    'High contrast',
    Color(0xff000000),
    Color(0xff171717),
    Color(0xffffffff),
    Color(0xffffdc65),
    false,
  );

  const ReaderPalette(
    this.label,
    this.backdrop,
    this.bar,
    this.text,
    this.accent,
    this.light,
  );
  final String label;
  final Color backdrop, bar, text, accent;
  final bool light;
}

class ReaderAppearanceOptions {
  const ReaderAppearanceOptions({
    this.palette = ReaderPalette.classic,
    this.boldIcons = false,
    this.showTabs = true,
    this.showStatusBar = true,
    this.showMetadata = true,
    this.animateTurns = true,
    this.tintedBackdrop = true,
  });

  factory ReaderAppearanceOptions.fromJson(Object? value) {
    final json = value is Map ? value : const {};
    return ReaderAppearanceOptions(
      palette:
          ReaderPalette.values
              .where((item) => item.name == json['palette'])
              .firstOrNull ??
          ReaderPalette.classic,
      boldIcons: json['boldIcons'] == true,
      showTabs: json['showTabs'] != false,
      showStatusBar: json['showStatusBar'] != false,
      showMetadata: json['showMetadata'] != false,
      animateTurns: json['animateTurns'] != false,
      tintedBackdrop: json['tintedBackdrop'] != false,
    );
  }

  final ReaderPalette palette;
  final bool boldIcons,
      showTabs,
      showStatusBar,
      showMetadata,
      animateTurns,
      tintedBackdrop;
  Color get backdrop => tintedBackdrop
      ? palette.backdrop
      : (palette.light ? const Color(0xffeeeeee) : const Color(0xff222222));

  Map<String, Object> toJson() => {
    'palette': palette.name,
    'boldIcons': boldIcons,
    'showTabs': showTabs,
    'showStatusBar': showStatusBar,
    'showMetadata': showMetadata,
    'animateTurns': animateTurns,
    'tintedBackdrop': tintedBackdrop,
  };
}

Future<ReaderAppearanceOptions?> chooseReaderAppearance(
  BuildContext context,
  ReaderAppearanceOptions current,
) {
  final draft = current.toJson();
  return showDialog<ReaderAppearanceOptions>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('Theme and menus'),
        scrollable: true,
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Theme'),
                trailing: DropdownButton<String>(
                  value: draft['palette'] as String,
                  items: [
                    for (final palette in ReaderPalette.values)
                      DropdownMenuItem(
                        value: palette.name,
                        child: Text(palette.label),
                      ),
                  ],
                  onChanged: (value) =>
                      refresh(() => draft['palette'] = value!),
                ),
              ),
              for (final option in const {
                'boldIcons': 'Bold toolbar icons',
                'showTabs': 'Show the score tab bar',
                'showStatusBar': 'Show the system status bar',
                'showMetadata': 'Show details in library rows',
                'animateTurns': 'Animate page turns',
                'tintedBackdrop': 'Use theme backdrop tint',
              }.entries)
                SwitchListTile(
                  title: Text(option.value),
                  value: draft[option.key] == true,
                  onChanged: (value) =>
                      refresh(() => draft[option.key] = value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, ReaderAppearanceOptions.fromJson(draft)),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

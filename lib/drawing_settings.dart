class DrawingPreset {
  const DrawingPreset(this.name, this.width, this.color, {this.opacity = 1});

  final String name;
  final double width;
  final int color;
  final double opacity;

  int get argb => ((opacity * 255).round() << 24) | color;

  static DrawingPreset? fromJson(Object? json) {
    if (json
        case {
          'name': final String name,
          'width': final num width,
          'color': final int color,
          'opacity': final num opacity,
        }
        when name.isNotEmpty &&
            name.length <= 80 &&
            width.isFinite &&
            width >= .001 &&
            width <= .04 &&
            color >= 0 &&
            color <= 0xffffff &&
            opacity.isFinite &&
            opacity >= .05 &&
            opacity <= 1) {
      return DrawingPreset(
        name,
        width.toDouble(),
        color,
        opacity: opacity.toDouble(),
      );
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'width': width,
    'color': color,
    'opacity': opacity,
  };
}

class DrawingSettings {
  const DrawingSettings({
    this.presets = defaults,
    this.selected = 0,
    this.pressure = false,
    this.tilt = false,
    this.switchTools = true,
    this.autoEnter = false,
    this.autoExit = false,
  });

  static const defaults = [
    DrawingPreset('Fine red', .003, 0x9b352e),
    DrawingPreset('Broad red', .006, 0x9b352e),
    DrawingPreset('Fine blue', .003, 0x244a91),
    DrawingPreset('Broad black', .006, 0x262626),
  ];

  final List<DrawingPreset> presets;
  final int selected;
  final bool pressure;
  final bool tilt;
  final bool switchTools;
  final bool autoEnter;
  final bool autoExit;

  DrawingPreset get preset => presets[selected];

  factory DrawingSettings.fromJson(Object? value) {
    if (value is! Map) return const DrawingSettings();
    final raw = value['presets'];
    final parsed = raw is List
        ? raw.map(DrawingPreset.fromJson).whereType<DrawingPreset>().toList()
        : <DrawingPreset>[];
    final presets = parsed.isEmpty ? defaults : parsed;
    final selected = value['selected'];
    return DrawingSettings(
      presets: presets,
      selected: selected is int ? selected.clamp(0, presets.length - 1) : 0,
      pressure: value['pressure'] == true,
      tilt: value['tilt'] == true,
      switchTools: value['switchTools'] != false,
      autoEnter: value['autoEnter'] == true,
      autoExit: value['autoExit'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'presets': [for (final preset in presets) preset.toJson()],
    'selected': selected,
    'pressure': pressure,
    'tilt': tilt,
    'switchTools': switchTools,
    'autoEnter': autoEnter,
    'autoExit': autoExit,
  };

  DrawingSettings copyWith({
    List<DrawingPreset>? presets,
    int? selected,
    bool? pressure,
    bool? tilt,
    bool? switchTools,
    bool? autoEnter,
    bool? autoExit,
  }) => DrawingSettings(
    presets: presets ?? this.presets,
    selected: selected ?? this.selected,
    pressure: pressure ?? this.pressure,
    tilt: tilt ?? this.tilt,
    switchTools: switchTools ?? this.switchTools,
    autoEnter: autoEnter ?? this.autoEnter,
    autoExit: autoExit ?? this.autoExit,
  );
}

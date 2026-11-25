import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/widgets.dart';

enum InkTool { pen, highlighter, eraser }

class _Stroke {
  _Stroke(this.tool, this.points);

  factory _Stroke.fromJson(Map<String, dynamic> data) =>
      _Stroke(InkTool.values.byName(data['tool'] as String), [
        for (final [num x, num y] in data['points'] as List<dynamic>)
          Offset(x.toDouble(), y.toDouble()),
      ]);

  final InkTool tool;
  final List<Offset> points;

  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    'points': [
      for (final point in points) [point.dx, point.dy],
    ],
  };
}

class PageInk extends ChangeNotifier {
  PageInk({List<dynamic> saved = const [], this.onChanged})
    : _strokes = [
        for (final stroke in saved)
          _Stroke.fromJson(stroke as Map<String, dynamic>),
      ];

  final VoidCallback? onChanged;
  List<_Stroke> _strokes;
  final _undo = <List<_Stroke>>[];
  _Stroke? _active;

  List<Map<String, dynamic>> snapshot() => [
    for (final stroke in _strokes) stroke.toJson(),
  ];

  void begin(Offset point, {InkTool tool = InkTool.pen}) {
    _active = _Stroke(tool, [point]);
    notifyListeners();
  }

  void extend(Offset point) {
    _active?.points.add(point);
    notifyListeners();
  }

  void finish({required bool commit}) {
    final stroke = _active;
    if (stroke == null) return;
    _active = null;
    if (commit) {
      final next = stroke.tool == InkTool.eraser
          ? _strokes.where((mark) => !_touches(mark, stroke)).toList()
          : [..._strokes, stroke];
      if (next.length != _strokes.length) {
        _undo.add(_strokes);
        _strokes = next;
        onChanged?.call();
      }
    }
    notifyListeners();
  }

  void undo() {
    if (_undo.isNotEmpty) {
      _strokes = _undo.removeLast();
    } else if (_strokes.isNotEmpty) {
      _strokes = _strokes.sublist(0, _strokes.length - 1);
    } else {
      return;
    }
    onChanged?.call();
    notifyListeners();
  }

  static bool _touches(_Stroke mark, _Stroke eraser) {
    const radius = .018;
    final points = eraser.points;
    for (var i = 0; i < points.length; i++) {
      final start = points[i == 0 ? 0 : i - 1];
      final end = points[i];
      final steps = ((end - start).distance / radius).ceil().clamp(1, 100);
      for (var step = 0; step <= steps; step++) {
        final sample = Offset.lerp(start, end, step / steps)!;
        for (var j = 0; j < mark.points.length; j++) {
          final a = mark.points[j == 0 ? 0 : j - 1];
          final b = mark.points[j];
          final line = b - a;
          final delta = sample - a;
          final t = line == Offset.zero
              ? 0.0
              : ((delta.dx * line.dx + delta.dy * line.dy) /
                        line.distanceSquared)
                    .clamp(0.0, 1.0);
          if ((sample - (a + line * t)).distanceSquared < radius * radius) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

class InkSurface extends StatefulWidget {
  const InkSurface({
    super.key,
    required this.ink,
    required this.enabled,
    required this.allowFinger,
    required this.tool,
  });

  final PageInk ink;
  final bool enabled;
  final bool allowFinger;
  final InkTool tool;

  @override
  State<InkSurface> createState() => _InkSurfaceState();
}

class _InkSurfaceState extends State<InkSurface> {
  int? _pointer;

  Offset _point(PointerEvent event, Size size) => Offset(
    (event.localPosition.dx / size.width).clamp(0.0, 1.0),
    (event.localPosition.dy / size.height).clamp(0.0, 1.0),
  );

  void _end(bool commit) {
    _pointer = null;
    widget.ink.finish(commit: commit);
  }

  @override
  void didUpdateWidget(InkSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pointer != null && (!widget.enabled || oldWidget.ink != widget.ink)) {
      _pointer = null;
      final ink = oldWidget.ink;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ink.finish(commit: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvas = RepaintBoundary(
      child: CustomPaint(painter: _InkPainter(widget.ink)),
    );
    if (!widget.enabled) return IgnorePointer(child: canvas);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointer != null || event.buttons != 1 || size.isEmpty) return;
            final accepted = switch (event.kind) {
              PointerDeviceKind.stylus ||
              PointerDeviceKind.invertedStylus => true,
              PointerDeviceKind.mouse => true,
              PointerDeviceKind.touch => widget.allowFinger,
              _ => false,
            };
            if (!accepted) return;
            _pointer = event.pointer;
            widget.ink.begin(_point(event, size), tool: widget.tool);
          },
          onPointerMove: (event) {
            if (event.pointer == _pointer && !size.isEmpty) {
              widget.ink.extend(_point(event, size));
            }
          },
          onPointerUp: (event) {
            if (event.pointer == _pointer) _end(true);
          },
          onPointerCancel: (event) {
            if (event.pointer == _pointer) _end(false);
          },
          child: canvas,
        );
      },
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.ink) : super(repaint: ink);

  final PageInk ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff9b352e)
      ..strokeWidth = size.width * 0.003
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final active = ink._active;
    final strokes = [
      ...ink._strokes,
      if (active != null && active.tool != InkTool.eraser) active,
    ];
    Offset position(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    for (final mark in strokes) {
      final highlighted = mark.tool == InkTool.highlighter;
      paint
        ..color = highlighted
            ? const Color(0x66ffbe00)
            : const Color(0xff9b352e)
        ..strokeWidth = size.width * (highlighted ? .023 : .003);
      final stroke = mark.points;
      final start = position(stroke.first);
      if (stroke.length == 1) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(start, paint.strokeWidth / 2, paint);
        continue;
      }
      final path = Path()..moveTo(start.dx, start.dy);
      for (final point in stroke.skip(1)) {
        final next = position(point);
        path.lineTo(next.dx, next.dy);
      }
      paint.style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_InkPainter oldDelegate) => oldDelegate.ink != ink;
}

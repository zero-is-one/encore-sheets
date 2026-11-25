import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart'
    show kPrimaryButton, kPrimaryStylusButton, kSecondaryStylusButton;
import 'package:flutter/widgets.dart';

enum InkTool { pen, highlighter, eraser, text, selection }

enum InkShape { line, rectangle, oval, arrow, ruler }

typedef PageText = ({String value, Offset position, double size});
typedef InkLayer = ({String id, String name, bool visible});
typedef InkLayerChange = ({String target, String? source});

const defaultInkLayer = (id: 'base', name: 'Annotations', visible: true);

bool isPenPointer(PointerEvent event) =>
    event.kind == PointerDeviceKind.stylus ||
    event.kind == PointerDeviceKind.invertedStylus;

class _Stroke {
  _Stroke(
    this.tool,
    this.points, {
    this.width,
    this.color,
    this.text,
    this.layer = 'base',
    this.sampleWidths,
  });

  factory _Stroke.fromJson(Map<String, dynamic> data) => _Stroke(
    InkTool.values.byName(data['tool'] as String),
    [
      for (final [num x, num y] in data['points'] as List<dynamic>)
        Offset(x.toDouble(), y.toDouble()),
    ],
    width: (data['width'] as num?)?.toDouble(),
    color: data['color'] as int?,
    text: data['text'] as String?,
    layer: data['layer'] as String? ?? 'base',
    sampleWidths: (data['sampleWidths'] as List?)
        ?.map((value) => (value as num).toDouble())
        .toList(),
  );

  final InkTool tool;
  final List<Offset> points;
  final double? width;
  final int? color;
  final String? text;
  final String layer;
  final List<double>? sampleWidths;

  _Stroke shifted(Offset delta, {String? intoLayer}) => _Stroke(
    tool,
    [for (final point in points) point + delta],
    width: width,
    color: color,
    text: text,
    layer: intoLayer ?? layer,
    sampleWidths: sampleWidths,
  );

  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    if (width != null) 'width': width,
    if (color != null) 'color': color,
    if (text != null) 'text': text,
    if (layer != 'base') 'layer': layer,
    if (sampleWidths != null) 'sampleWidths': sampleWidths,
    'points': [
      for (final point in points) [point.dx, point.dy],
    ],
  };
}

class PageInk extends ChangeNotifier {
  static const eraserRadius = .018;
  PageInk({
    List<dynamic> saved = const [],
    this.onChanged,
    String? activeLayer = 'base',
    List<String> visibleLayers = const ['base'],
  }) : _activeLayer = activeLayer,
       _visibleLayers = visibleLayers,
       _strokes = [
         for (final stroke in saved)
           _Stroke.fromJson(stroke as Map<String, dynamic>),
       ];

  final VoidCallback? onChanged;
  List<_Stroke> _strokes;
  final _undo = <List<_Stroke>>[];
  final _redo = <List<_Stroke>>[];
  _Stroke? _active;
  Offset? _activeStart;
  Set<int> _selection = {};
  List<Offset> _outline = [];
  bool _lasso = false;
  bool _moving = false;
  String? _activeLayer;
  List<String> _visibleLayers;

  void configureLayers({
    required String? active,
    required List<String> visible,
    required List<InkLayerChange> changes,
  }) {
    _activeLayer = active;
    _visibleLayers = visible;
    for (final change in changes) {
      if (change.target == change.source) continue;
      _strokes = [
        for (final stroke in _strokes)
          if (stroke.layer != change.target) stroke,
        for (final stroke in _strokes)
          if (stroke.layer == change.source)
            stroke.shifted(Offset.zero, intoLayer: change.target),
      ];
    }
    _selection = {};
    if (changes.isNotEmpty) {
      _undo.clear();
      _redo.clear();
    }
    notifyListeners();
  }

  Iterable<_Stroke> _orderedStrokes() sync* {
    for (final layer in _visibleLayers) {
      yield* _strokes.where((stroke) => stroke.layer == layer);
    }
  }

  List<Map<String, dynamic>> snapshot() => [
    for (final stroke in _strokes) stroke.toJson(),
  ];

  void paint(Canvas canvas, Size size) =>
      _InkPainter(this, showSelection: false).paint(canvas, size);

  bool get hasSelection => _selection.isNotEmpty;

  List<Map<String, dynamic>> copySelection() => [
    for (final index in _selection) _strokes[index].toJson(),
  ];

  void deleteSelection() {
    if (!hasSelection) return;
    _replaceStrokes([
      for (final (index, stroke) in _strokes.indexed)
        if (!_selection.contains(index)) stroke,
    ]);
  }

  void pasteSelection(List<Map<String, dynamic>> clipboard) {
    final layer = _activeLayer;
    if (clipboard.isEmpty || layer == null) return;
    final strokes = clipboard.map(_Stroke.fromJson).toList();
    final delta = _clampedDelta(const Offset(.024, .024), _bounds(strokes));
    final start = _strokes.length;
    _replaceStrokes(
      [
        ..._strokes,
        for (final stroke in strokes) stroke.shifted(delta, intoLayer: layer),
      ],
      selection: {for (var i = start; i < start + strokes.length; i++) i},
    );
  }

  Rect get _selectionBounds =>
      _bounds(_selection.map((index) => _strokes[index]));

  Rect _bounds(Iterable<_Stroke> strokes) {
    final points = strokes.expand((stroke) => stroke.points);
    final origin = points.first;
    return points.fold(Rect.fromPoints(origin, origin), (bounds, point) {
      return bounds.expandToInclude(Rect.fromPoints(point, point));
    });
  }

  Offset _clampedDelta(Offset offset, Rect bounds) => Offset(
    offset.dx.clamp(-bounds.left, 1 - bounds.right),
    offset.dy.clamp(-bounds.top, 1 - bounds.bottom),
  );

  void beginSelection(Offset point, {required bool freeform}) {
    _lasso = freeform;
    _moving = hasSelection && _selectionBounds.inflate(.018).contains(point);
    if (!_moving) _selection = {};
    _outline = [point];
    notifyListeners();
  }

  void extendSelection(Offset point) {
    if (_outline.isEmpty) return;
    if (_lasso && !_moving) {
      _outline.add(point);
    } else {
      _outline = [_outline.first, point];
    }
    notifyListeners();
  }

  void finishSelection({required bool commit}) {
    if (_outline.isEmpty) return;
    final outline = _outline;
    _outline = [];
    if (commit && outline.length > 1) {
      if (_moving && hasSelection) {
        final delta = _clampedDelta(
          outline.last - outline.first,
          _selectionBounds,
        );
        if (delta != Offset.zero) {
          _replaceStrokes([
            for (final (index, stroke) in _strokes.indexed)
              _selection.contains(index) ? stroke.shifted(delta) : stroke,
          ], selection: _selection);
          return;
        }
      } else {
        final rectangle = Rect.fromPoints(outline.first, outline.last);
        final path = _lasso ? (Path()..addPolygon(outline, true)) : null;
        _selection = {
          for (final (index, stroke) in _strokes.indexed)
            if (_visibleLayers.contains(stroke.layer) &&
                _samples(stroke).any(path?.contains ?? rectangle.contains))
              index,
        };
      }
    }
    notifyListeners();
  }

  Iterable<Offset> _samples(_Stroke stroke) sync* {
    yield stroke.points.first;
    for (var i = 1; i < stroke.points.length; i++) {
      final start = stroke.points[i - 1];
      final end = stroke.points[i];
      final count = ((end - start).distance / .006).ceil();
      for (var step = 1; step <= count; step++) {
        yield Offset.lerp(start, end, step / count)!;
      }
    }
  }

  void _replaceStrokes(List<_Stroke> next, {Set<int> selection = const {}}) {
    _undo.add(_strokes);
    _redo.clear();
    _strokes = next;
    _selection = selection;
    onChanged?.call();
    notifyListeners();
  }

  (int, PageText)? textAt(Offset point, Size size) {
    for (var index = _strokes.length - 1; index >= 0; index--) {
      final mark = _strokes[index];
      if (mark.text == null || !_visibleLayers.contains(mark.layer)) continue;
      final position = mark.points.first;
      final fontSize = mark.width ?? .024;
      final painter = _layoutText(mark.text!, fontSize, size, position);
      final hit = Rect.fromLTWH(
        position.dx * size.width - 4,
        position.dy * size.height - 4,
        painter.width + 8,
        painter.height + 8,
      ).contains(Offset(point.dx * size.width, point.dy * size.height));
      painter.dispose();
      if (hit)
        return (index, (value: mark.text!, position: position, size: fontSize));
    }
    return null;
  }

  void setText(int? index, PageText? annotation) {
    if (index == null && annotation == null) return;
    final layer = index == null ? _activeLayer : _strokes[index].layer;
    if (layer == null) return;
    final next = [..._strokes];
    if (index != null) next.removeAt(index);
    if (annotation != null) {
      next.insert(
        index ?? next.length,
        _Stroke(
          InkTool.text,
          [annotation.position],
          width: annotation.size,
          text: annotation.value,
          layer: layer,
        ),
      );
    }
    _replaceStrokes(next);
  }

  void begin(
    Offset point, {
    InkTool tool = InkTool.pen,
    double? width,
    int? color,
    double? sampleWidth,
  }) {
    final layer = _activeLayer;
    if (layer == null) return;
    _activeStart = point;
    _active = _Stroke(
      tool,
      [point],
      width: width,
      color: color,
      layer: layer,
      sampleWidths: sampleWidth == null ? null : [sampleWidth],
    );
    notifyListeners();
  }

  void extend(Offset point, {double? sampleWidth}) {
    final stroke = _active;
    if (stroke == null) return;
    stroke.points.add(point);
    if (stroke.sampleWidths case final widths?) {
      widths.add(sampleWidth ?? widths.last);
    }
    notifyListeners();
  }

  void extendShape(InkShape shape, Offset end, Size size) {
    final points = _active?.points;
    if (points == null) return;
    final start = _activeStart!;
    final bounds = Rect.fromPoints(start, end);
    final outlined = switch (shape) {
      InkShape.line => [start, end],
      InkShape.ruler => [start, _rulerEnd(start, end, size)],
      InkShape.rectangle => [
        start,
        Offset(end.dx, start.dy),
        end,
        Offset(start.dx, end.dy),
        start,
      ],
      InkShape.oval => [
        for (var i = 0; i <= 48; i++)
          Offset(
            bounds.center.dx + bounds.width / 2 * math.cos(i * math.pi / 24),
            bounds.center.dy + bounds.height / 2 * math.sin(i * math.pi / 24),
          ),
      ],
      InkShape.arrow => _arrow(start, end, size),
    };
    points
      ..clear()
      ..addAll(outlined);
    notifyListeners();
  }

  List<Offset> _arrow(Offset start, Offset end, Size size) {
    final vector = Offset(
      (end.dx - start.dx) * size.width,
      (end.dy - start.dy) * size.height,
    );
    final length = math.min(vector.distance * .32, 24);
    final angle = vector.direction;
    Offset tip(double delta) => Offset(
      (end.dx - math.cos(angle + delta) * length / size.width).clamp(0.0, 1.0),
      (end.dy - math.sin(angle + delta) * length / size.height).clamp(0.0, 1.0),
    );
    return [start, end, tip(.45), end, tip(-.45)];
  }

  Offset _rulerEnd(Offset start, Offset end, Size size) {
    final vector = Offset(
      (end.dx - start.dx) * size.width,
      (end.dy - start.dy) * size.height,
    );
    const increment = math.pi / 12;
    final angle = (vector.direction / increment).round() * increment;
    final direction = Offset(
      math.cos(angle) / size.width,
      math.sin(angle) / size.height,
    );
    final xLimit = direction.dx >= 0 ? 1 - start.dx : -start.dx;
    final yLimit = direction.dy >= 0 ? 1 - start.dy : -start.dy;
    final length = math.min(
      vector.distance,
      math.min(
        direction.dx == 0 ? double.infinity : xLimit / direction.dx,
        direction.dy == 0 ? double.infinity : yLimit / direction.dy,
      ),
    );
    final point = start + direction * length;
    return Offset(point.dx.clamp(0.0, 1.0), point.dy.clamp(0.0, 1.0));
  }

  void finish({required bool commit}) {
    final stroke = _active;
    if (stroke == null) return;
    _active = null;
    _activeStart = null;
    if (commit) {
      final next = stroke.tool == InkTool.eraser
          ? _strokes
                .where(
                  (mark) =>
                      mark.layer != stroke.layer || !_touches(mark, stroke),
                )
                .toList()
          : [..._strokes, stroke];
      if (next.length != _strokes.length) {
        _replaceStrokes(next);
        return;
      }
    }
    notifyListeners();
  }

  void undo() {
    final previous = _strokes;
    if (_undo.isNotEmpty) {
      _strokes = _undo.removeLast();
    } else if (_strokes.isNotEmpty) {
      _strokes = _strokes.sublist(0, _strokes.length - 1);
    } else {
      return;
    }
    _redo.add(previous);
    _selection = {};
    onChanged?.call();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_strokes);
    _strokes = _redo.removeLast();
    _selection = {};
    onChanged?.call();
    notifyListeners();
  }

  static bool _touches(_Stroke mark, _Stroke eraser) {
    final radius =
        eraserRadius +
        (mark.width ?? (mark.tool == InkTool.highlighter ? .023 : .003)) / 2;
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
    this.width,
    this.color,
    this.onTextTap,
    this.shape,
    this.freeformSelection = false,
    this.pressure = false,
    this.tilt = false,
    this.switchTools = true,
    this.autoStylus = false,
    this.onStylusStart,
    this.onStylusEnd,
  });

  final PageInk ink;
  final bool enabled;
  final bool allowFinger;
  final InkTool tool;
  final double? width;
  final int? color;
  final void Function(Offset point, Size pageSize)? onTextTap;
  final InkShape? shape;
  final bool freeformSelection;
  final bool pressure;
  final bool tilt;
  final bool switchTools;
  final bool autoStylus;
  final VoidCallback? onStylusStart;
  final void Function(bool commit)? onStylusEnd;

  @override
  State<InkSurface> createState() => _InkSurfaceState();
}

class _InkSurfaceState extends State<InkSurface> {
  int? _pointer;
  InkTool? _activeTool;
  InkShape? _activeShape;
  bool _stylus = false;

  Offset _point(PointerEvent event, Size size) => Offset(
    (event.localPosition.dx / size.width).clamp(0.0, 1.0),
    (event.localPosition.dy / size.height).clamp(0.0, 1.0),
  );

  void _end(bool commit) {
    _pointer = null;
    if (_activeTool == InkTool.selection) {
      widget.ink.finishSelection(commit: commit);
    } else {
      widget.ink.finish(commit: commit);
    }
    if (_stylus) widget.onStylusEnd?.call(commit);
    _stylus = false;
    _activeTool = null;
    _activeShape = null;
  }

  double? _widthFor(PointerEvent event) {
    if (!_stylus ||
        _activeTool != InkTool.pen ||
        _activeShape != null ||
        !widget.pressure && !widget.tilt)
      return null;
    final pressure =
        event.pressure.isFinite && event.pressureMax > event.pressureMin
        ? ((event.pressure - event.pressureMin) /
                  (event.pressureMax - event.pressureMin))
              .clamp(0.0, 1.0)
        : .6;
    final tilt = event.tilt.isFinite ? event.tilt.clamp(0.0, math.pi / 2) : 0.0;
    final force = widget.pressure ? .38 + pressure * 1.1 : 1.0;
    final angle = widget.tilt ? 1 + math.sin(tilt) * .45 : 1.0;
    return ((widget.width ?? .003) * force * angle).clamp(.0002, .1);
  }

  @override
  void didUpdateWidget(InkSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pointer != null &&
        ((!widget.enabled && !widget.autoStylus) ||
            oldWidget.ink != widget.ink ||
            oldWidget.tool != widget.tool ||
            oldWidget.shape != widget.shape)) {
      _pointer = null;
      final ink = oldWidget.ink;
      final tool = _activeTool;
      final stylus = _stylus;
      _activeTool = null;
      _activeShape = null;
      _stylus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (tool == InkTool.selection) {
          ink.finishSelection(commit: false);
        } else {
          ink.finish(commit: false);
        }
        if (stylus) oldWidget.onStylusEnd?.call(false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvas = RepaintBoundary(
      child: CustomPaint(
        painter: _InkPainter(
          widget.ink,
          showSelection: widget.enabled && widget.tool == InkTool.selection,
        ),
      ),
    );
    if (!widget.enabled && !widget.autoStylus)
      return IgnorePointer(child: canvas);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: widget.enabled
              ? HitTestBehavior.opaque
              : HitTestBehavior.translucent,
          onPointerDown: (event) {
            final stylus = isPenPointer(event);
            if (_pointer != null ||
                size.isEmpty ||
                (!widget.enabled && !stylus) ||
                (stylus ? event.buttons == 0 : event.buttons != kPrimaryButton))
              return;
            final erasing =
                stylus &&
                widget.switchTools &&
                (event.kind == PointerDeviceKind.invertedStylus ||
                    event.buttons &
                            (kPrimaryStylusButton | kSecondaryStylusButton) !=
                        0);
            final tool = erasing
                ? InkTool.eraser
                : widget.enabled
                ? widget.tool
                : InkTool.pen;
            if (tool == InkTool.text) {
              widget.onTextTap?.call(_point(event, size), size);
              return;
            }
            if (tool == InkTool.selection) {
              _pointer = event.pointer;
              _activeTool = tool;
              widget.ink.beginSelection(
                _point(event, size),
                freeform: widget.freeformSelection,
              );
              return;
            }
            final accepted = switch (event.kind) {
              PointerDeviceKind.stylus ||
              PointerDeviceKind.invertedStylus => true,
              PointerDeviceKind.mouse => true,
              PointerDeviceKind.touch => widget.allowFinger,
              _ => false,
            };
            if (!accepted) return;
            _pointer = event.pointer;
            _activeTool = tool;
            _activeShape = widget.enabled && !erasing ? widget.shape : null;
            _stylus = stylus;
            widget.ink.begin(
              _point(event, size),
              tool: tool,
              width: widget.width,
              color: widget.color,
              sampleWidth: _widthFor(event),
            );
            if (stylus) widget.onStylusStart?.call();
          },
          onPointerMove: (event) {
            if (event.pointer == _pointer && !size.isEmpty) {
              final point = _point(event, size);
              if (_activeTool == InkTool.selection) {
                widget.ink.extendSelection(point);
              } else if (_activeShape case final shape?) {
                widget.ink.extendShape(shape, point, size);
              } else {
                widget.ink.extend(point, sampleWidth: _widthFor(event));
              }
            }
          },
          onPointerUp: (event) {
            if (event.pointer == _pointer) {
              if (_activeTool == InkTool.selection && !size.isEmpty) {
                widget.ink.extendSelection(_point(event, size));
              } else if (_activeShape case final shape? when !size.isEmpty) {
                widget.ink.extendShape(shape, _point(event, size), size);
              }
              _end(true);
            }
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

TextPainter _layoutText(
  String text,
  double fontSize,
  Size size,
  Offset position,
) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: const Color(0xff263a4f),
        fontSize: size.width * fontSize,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: (1 - position.dx) * size.width);
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.ink, {required this.showSelection}) : super(repaint: ink);

  final PageInk ink;
  final bool showSelection;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff9b352e)
      ..strokeWidth = size.width * 0.003
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final active = ink._active;
    final strokes = [
      ...ink._orderedStrokes(),
      if (active != null && active.tool != InkTool.eraser) active,
    ];
    Offset position(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    for (final mark in strokes) {
      if (mark.text case final text?) {
        final painter = _layoutText(
          text,
          mark.width ?? .024,
          size,
          mark.points.first,
        );
        canvas.save();
        canvas.clipRect(Offset.zero & size);
        painter.paint(canvas, position(mark.points.first));
        canvas.restore();
        painter.dispose();
        continue;
      }
      final highlighted = mark.tool == InkTool.highlighter;
      paint
        ..color = mark.color != null
            ? Color(mark.color!)
            : highlighted
            ? const Color(0x66ffbe00)
            : const Color(0xff9b352e)
        ..strokeWidth =
            size.width * (mark.width ?? (highlighted ? .023 : .003));
      final stroke = mark.points;
      if (mark.sampleWidths case final widths?) {
        final brush = Path();
        Offset? previous;
        var previousRadius = 0.0;
        for (final (index, point) in stroke.indexed) {
          final center = position(point);
          final radius = widths[index] * size.width / 2;
          brush.addOval(Rect.fromCircle(center: center, radius: radius));
          if (previous != null && previous != center) {
            final segment = center - previous;
            final normal = Offset(segment.dy, -segment.dx) / segment.distance;
            brush.addPolygon([
              previous + normal * previousRadius,
              center + normal * radius,
              center - normal * radius,
              previous - normal * previousRadius,
            ], true);
          }
          previous = center;
          previousRadius = radius;
        }
        paint.style = PaintingStyle.fill;
        canvas.drawPath(brush, paint);
        continue;
      }
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
    if (active?.tool == InkTool.eraser) {
      final cursor = Paint()
        ..color = const Color(0xff565e57)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final center = position(active!.points.last);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: 2 * size.width * PageInk.eraserRadius,
          height: 2 * size.height * PageInk.eraserRadius,
        ),
        cursor,
      );
    }
    if (showSelection) {
      final guide = Paint()
        ..color = const Color(0xff315af4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final outline = ink._outline;
      if (ink.hasSelection) {
        var bounds = ink._selectionBounds;
        if (ink._moving && outline.length > 1) {
          bounds = bounds.shift(
            ink._clampedDelta(outline.last - outline.first, bounds),
          );
        }
        canvas.drawRect(
          Rect.fromPoints(
            position(bounds.topLeft),
            position(bounds.bottomRight),
          ).inflate(5),
          guide,
        );
      } else if (outline.length > 1) {
        if (ink._lasso) {
          canvas.drawPath(
            Path()..addPolygon(outline.map(position).toList(), true),
            guide,
          );
        } else {
          canvas.drawRect(
            Rect.fromPoints(position(outline.first), position(outline.last)),
            guide,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_InkPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.showSelection != showSelection;
}

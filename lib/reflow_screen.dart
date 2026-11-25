import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'reflow_zones.dart';

class ReflowScreen extends StatefulWidget {
  const ReflowScreen({
    super.key,
    required this.document,
    required this.first,
    required this.last,
    required this.initialPage,
    required this.saved,
  });
  final PdfDocument document;
  final int first, last, initialPage;
  final List<ReflowZone> saved;

  @override
  State<ReflowScreen> createState() => _ReflowScreenState();
}

class _ReflowScreenState extends State<ReflowScreen> {
  final _scroll = ScrollController();
  late final _zones = [...widget.saved];
  double _zoom = 1;
  double _extent = 1;
  int _index = 0;
  bool _paged = true, _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    _scan();
  }

  Future<void> _scan() async {
    final result = <ReflowZone>[];
    try {
      for (var page = widget.first; page <= widget.last; page++) {
        if (!mounted) return;
        final saved = _zones.where((zone) => zone.page == page).toList();
        result.addAll(
          saved.isEmpty
              ? await scanReflowPage(widget.document.pages[page - 1])
              : saved,
        );
      }
      if (!mounted) return;
      setState(() {
        _zones
          ..clear()
          ..addAll(result);
        final current = _zones.indexWhere(
          (zone) => zone.page == widget.initialPage,
        );
        _index = current < 0 ? 0 : current;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jump(_index, animate: false);
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not scan the score for reading zones.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrolled() {
    if (_zones.isEmpty) return;
    final index = (_scroll.offset / _extent).round().clamp(
      0,
      _zones.length - 1,
    );
    if (index != _index) setState(() => _index = index);
  }

  void _jump(int index, {bool animate = true}) {
    if (!_scroll.hasClients || _zones.isEmpty) return;
    final position = (index.clamp(0, _zones.length - 1) * _extent).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (animate) {
      _scroll.animateTo(
        position,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(position);
    }
  }

  void _relayout(VoidCallback update) {
    final index = _index;
    setState(update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jump(index, animate: false);
    });
  }

  Future<void> _edit() async {
    final index = _index;
    final zone = _zones[index];
    var values = RangeValues(zone.top, zone.bottom);
    final edit = await showDialog<(String, RangeValues)>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: Text('Edit zone on page ${zone.page}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Top ${(values.start * 100).round()}% · bottom ${(values.end * 100).round()}%',
                ),
                RangeSlider(
                  values: values,
                  divisions: 100,
                  onChanged: (range) {
                    if (range.end - range.start >= .02)
                      refresh(() => values = range);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  _zones
                          .where((zoneItem) => zoneItem.page == zone.page)
                          .length <
                      2
                  ? null
                  : () => Navigator.pop(dialog, ('remove', values)),
              child: const Text('Remove zone'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, ('split', values)),
              child: const Text('Split'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, ('save', values)),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || edit == null) return;
    final (action, range) = edit;
    setState(() {
      final edited = (page: zone.page, top: range.start, bottom: range.end);
      if (action == 'remove') {
        _zones.removeAt(index);
        _index = index.clamp(0, _zones.length - 1);
      } else if (action == 'split') {
        final midpoint = (range.start + range.end) / 2;
        _zones[index] = (page: zone.page, top: range.start, bottom: midpoint);
        _zones.insert(index + 1, (
          page: zone.page,
          top: midpoint,
          bottom: range.end,
        ));
      } else {
        _zones[index] = edited;
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Score reflow'),
      actions: [
        TextButton(
          onPressed: _loading || _zones.isEmpty
              ? null
              : () => Navigator.pop(context, _zones),
          child: const Text('Save zones'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error case final error?) Text(error),
          if (!_loading && _zones.isNotEmpty) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous zone',
                  onPressed: _index > 0 ? () => _jump(_index - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  'Page ${_zones[_index].page} · Zone ${_index + 1} / ${_zones.length}',
                ),
                IconButton(
                  tooltip: 'Next zone',
                  onPressed: _index + 1 < _zones.length
                      ? () => _jump(_index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(onPressed: _edit, child: const Text('Edit zone')),
                TextButton(
                  onPressed: () => _relayout(() => _paged = !_paged),
                  child: Text(
                    _paged ? 'Continuous scroll' : 'Paged navigation',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text('Magnification'),
                ),
                Expanded(
                  child: Slider(
                    value: _zoom,
                    min: 1,
                    max: 2.5,
                    divisions: 6,
                    onChanged: (value) => _relayout(() => _zoom = value),
                  ),
                ),
              ],
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewport) {
                  _extent = viewport.maxWidth * (_paged ? 1 : _zoom);
                  final renderWidth = viewport.maxWidth * _zoom;
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    controller: _scroll,
                    physics: _paged
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemExtent: _extent,
                    itemCount: _zones.length,
                    itemBuilder: (context, index) {
                      final zone = _zones[index];
                      return Center(
                        child: ClipRect(
                          child: SizedBox(
                            width: _extent,
                            child: OverflowBox(
                              minWidth: renderWidth,
                              maxWidth: renderWidth,
                              child: _ZoneImage(
                                page: widget.document.pages[zone.page - 1],
                                zone: zone,
                                width: renderWidth,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ZoneImage extends StatefulWidget {
  const _ZoneImage({
    required this.page,
    required this.zone,
    required this.width,
  });
  final PdfPage page;
  final ReflowZone zone;
  final double width;

  @override
  State<_ZoneImage> createState() => _ZoneImageState();
}

class _ZoneImageState extends State<_ZoneImage> {
  ui.Image? _image;
  int _revision = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(_ZoneImage old) {
    super.didUpdateWidget(old);
    if (old.zone != widget.zone || old.width != widget.width) _render();
  }

  Future<void> _render() async {
    final revision = ++_revision;
    ui.Image? image;
    try {
      image = await renderReflowZone(widget.page, widget.zone, widget.width);
    } catch (_) {
      // An individual render failure should not prevent other sections from opening.
    }
    if (!mounted || revision != _revision) {
      image?.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _failed = image == null;
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image != null
      ? RawImage(image: _image, fit: BoxFit.contain)
      : _failed
      ? const Text('Could not render this zone.')
      : const Center(child: CircularProgressIndicator());
}

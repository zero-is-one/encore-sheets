import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'score_library.dart';

class JumpLinksScreen extends StatefulWidget {
  const JumpLinksScreen({
    super.key,
    required this.document,
    required this.page,
    required this.links,
  });
  final PdfDocument document;
  final int page;
  final List<ScoreJump> links;

  @override
  State<JumpLinksScreen> createState() => _JumpLinksScreenState();
}

class _JumpLinksScreenState extends State<JumpLinksScreen> {
  late final _links = [...widget.links];

  Future<void> _edit([int? index]) async {
    final link = await Navigator.of(context).push<ScoreJump>(
      MaterialPageRoute(
        builder: (_) => _JumpEditor(
          document: widget.document,
          page: widget.page,
          link: index == null ? null : _links[index],
        ),
      ),
    );
    if (!mounted || link == null) return;
    setState(() {
      if (index == null) {
        _links.add(link);
      } else {
        _links[index] = link;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Repeat & coda links'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _links),
          child: const Text('Save'),
        ),
      ],
    ),
    body: _links.isEmpty
        ? const Center(
            child: Text('Add a link between two points in this score.'),
          )
        : ListView.builder(
            itemCount: _links.length,
            itemBuilder: (context, index) {
              final link = _links[index];
              return ListTile(
                leading: const Icon(Icons.link),
                title: Text(link.title),
                subtitle: Text(
                  'Page ${link.source.page} → ${link.target.page}',
                ),
                onTap: () => _edit(index),
                trailing: IconButton(
                  tooltip: 'Remove link',
                  onPressed: () => setState(() => _links.removeAt(index)),
                  icon: const Icon(Icons.clear),
                ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _edit,
      tooltip: 'Add link',
      child: const Icon(Icons.add),
    ),
  );
}

class _JumpEditor extends StatefulWidget {
  const _JumpEditor({
    required this.document,
    required this.page,
    required this.link,
  });
  final PdfDocument document;
  final int page;
  final ScoreJump? link;

  @override
  State<_JumpEditor> createState() => _JumpEditorState();
}

class _JumpEditorState extends State<_JumpEditor> {
  late final _title = TextEditingController(text: widget.link?.title ?? '');
  late final _points = <JumpPoint?>[widget.link?.source, widget.link?.target];
  late final _pages = [
    widget.link?.source.page ?? widget.page,
    widget.link?.target.page ?? widget.page,
  ];
  int _step = 0;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.link == null ? 'New link' : 'Edit link'),
        actions: [
          TextButton(
            onPressed:
                _title.text.trim().isEmpty ||
                    _points.any((point) => point == null)
                ? null
                : () => Navigator.pop(
                    context,
                    ScoreJump(_title.text.trim(), _points[0]!, _points[1]!),
                  ),
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Link title'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (_, bounds) => bounds.maxWidth >= 720
                    ? Row(
                        children: [
                          Expanded(child: _endpoint(0, labelled: true)),
                          const VerticalDivider(width: 16),
                          Expanded(child: _endpoint(1, labelled: true)),
                        ],
                      )
                    : Column(
                        children: [
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(
                                value: 0,
                                label: Text('Start point'),
                              ),
                              ButtonSegment(
                                value: 1,
                                label: Text('Destination'),
                              ),
                            ],
                            selected: {_step},
                            onSelectionChanged: (values) =>
                                setState(() => _step = values.single),
                          ),
                          Expanded(child: _endpoint(_step)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _endpoint(int step, {bool labelled = false}) {
    final count = widget.document.pages.length;
    final current = _pages[step].clamp(1, count);
    final pdfPage = widget.document.pages[current - 1];
    final point = _points[step];
    return Column(
      children: [
        if (labelled)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(step == 0 ? 'Start point' : 'Destination'),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, limits) {
              final ratio = pdfPage.width / pdfPage.height;
              final width = math.min(limits.maxWidth, limits.maxHeight * ratio);
              final height = width / ratio;
              return Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (tap) {
                      if (width <= 0 || height <= 0) return;
                      setState(
                        () => _points[step] = JumpPoint(
                          current,
                          (tap.localPosition.dx / width).clamp(0.0, 1.0),
                          (tap.localPosition.dy / height).clamp(0.0, 1.0),
                        ),
                      );
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: PdfPageView(
                            document: widget.document,
                            pageNumber: current,
                          ),
                        ),
                        if (point != null && point.page == current)
                          Positioned(
                            left: point.x * width - 12,
                            top: point.y * height - 12,
                            child: Icon(
                              Icons.location_on,
                              color: step == 0 ? Colors.blue : Colors.orange,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: current <= 1
                  ? null
                  : () => setState(() => _pages[step] = current - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: Text(
                'Page $current / $count · Tap the score to place',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: current >= count
                  ? null
                  : () => setState(() => _pages[step] = current + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'score_text_search.dart';

class ScoreTextSearchScreen extends StatefulWidget {
  const ScoreTextSearchScreen({
    super.key,
    required this.document,
    required this.firstPage,
    required this.lastPage,
    required this.annotations,
    required this.notes,
  });

  final PdfDocument document;
  final int firstPage;
  final int lastPage;
  final Map<String, dynamic> annotations;
  final Map<int, String> notes;

  @override
  State<ScoreTextSearchScreen> createState() => _ScoreTextSearchScreenState();
}

class _ScoreTextSearchScreenState extends State<ScoreTextSearchScreen> {
  final _input = TextEditingController();
  final _matches = <ScoreTextMatch>[];
  StreamSubscription<ScoreTextMatch>? _search;
  String? _activeQuery;
  bool _searching = false;
  bool _failed = false;

  void _find() {
    final query = _input.text.trim();
    if (query.isEmpty) return;
    unawaited(_search?.cancel());
    setState(() {
      _activeQuery = query;
      _matches.clear();
      _searching = true;
      _failed = false;
    });
    _search =
        searchScoreText(
          document: widget.document,
          firstPage: widget.firstPage,
          lastPage: widget.lastPage,
          query: query,
          annotations: widget.annotations,
          notes: widget.notes,
        ).listen(
          (result) {
            if (mounted) setState(() => _matches.add(result));
          },
          onError: (Object _) {
            if (mounted) setState(() => _failed = true);
          },
          onDone: () {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  @override
  void dispose() {
    unawaited(_search?.cancel());
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find in score')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _input,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _find(),
              decoration: InputDecoration(
                labelText: 'Search PDF text, annotations, and notes',
                suffixIcon: IconButton(
                  tooltip: 'Find',
                  icon: const Icon(Icons.search),
                  onPressed: _find,
                ),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_failed) const Text('Some pages could not be searched.'),
          if (_activeQuery != null &&
              !_searching &&
              !_failed &&
              _matches.isEmpty)
            Text('No matches for “$_activeQuery”.'),
          Expanded(
            child: ListView.builder(
              itemCount: _matches.length,
              itemBuilder: (context, index) {
                final match = _matches[index];
                return ListTile(
                  title: Text(
                    match.excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('Page ${match.page} · ${match.source.label}'),
                  onTap: () => Navigator.pop(context, match.page),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

import 'package:material_ui/material_ui.dart';

import 'pdf_assembly.dart';
import 'score_library.dart';

class PdfAssemblyScreen extends StatefulWidget {
  const PdfAssemblyScreen({
    super.key,
    required this.library,
    this.source,
    this.initialSelection = const [],
  });

  final ScoreLibrary library;
  final ScoreEntry? source;
  final List<ScoreEntry> initialSelection;

  @override
  State<PdfAssemblyScreen> createState() => _PdfAssemblyScreenState();
}

class _PdfAssemblyScreenState extends State<PdfAssemblyScreen> {
  final _form = GlobalKey<FormState>();
  late final _selected = [...widget.initialSelection];
  late final _title = TextEditingController(
    text: widget.source == null
        ? 'Combined score'
        : '${widget.source!.title} excerpt',
  );
  final _first = TextEditingController(text: '1');
  final _last = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final source = widget.source;
      final title = _title.text.trim();
      final name = title.toLowerCase().endsWith('.pdf') ? title : '$title.pdf';
      final pdf = await assemblePdf(name, [
        for (final score in source == null ? _selected : [source])
          (
            file: await widget.library.storage.openScore(score.id),
            first: source == null ? null : int.parse(_first.text.trim()),
            last: source == null ? null : int.parse(_last.text.trim()),
          ),
      ]);
      final (score, _) = await widget.library.import(pdf);
      if (mounted) Navigator.pop(context, score);
    } on RangeError {
      if (mounted)
        setState(() => _error = 'Enter a page range within the source PDF.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the new PDF.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pageField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        validator: (value) => (int.tryParse(value?.trim() ?? '') ?? 0) < 1
            ? 'Enter a page number'
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(source == null ? 'Combine PDFs' : 'Extract pages'),
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'New score name',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name'
                      : null,
                ),
                if (source == null)
                  for (final score in widget.library.recent)
                    CheckboxListTile(
                      value: _selected.contains(score),
                      secondary: _selected.contains(score)
                          ? Text('${_selected.indexOf(score) + 1}')
                          : null,
                      title: Text(score.title),
                      onChanged: _saving
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                _selected.add(score);
                              } else {
                                _selected.remove(score);
                              }
                            }),
                    )
                else ...[
                  ListTile(
                    title: Text(source.title),
                    contentPadding: EdgeInsets.zero,
                  ),
                  _pageField(_first, 'First page'),
                  _pageField(_last, 'Last page'),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving || source == null && _selected.length < 2
                      ? null
                      : _save,
                  child: const Text('Save new score'),
                ),
                if (_saving) const LinearProgressIndicator(),
                if (_error case final error?) Text(error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

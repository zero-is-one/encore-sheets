import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_export.dart';

class PdfExportScreen extends StatefulWidget {
  const PdfExportScreen({
    super.key,
    required this.source,
    required this.title,
    required this.firstPage,
    required this.lastPage,
    required this.pageCount,
    required this.annotations,
  });

  final XFile source;
  final String title;
  final int firstPage;
  final int lastPage;
  final int pageCount;
  final Map<String, dynamic> annotations;

  @override
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: '${widget.firstPage}');
  late final _last = TextEditingController(text: '${widget.lastPage}');
  bool _flatten = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _export({required bool print}) async {
    if (!_form.currentState!.validate()) return;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final stem = widget.title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final name =
        '${stem.isEmpty ? 'Score' : stem}${_flatten ? ' (annotated)' : ''}.pdf';
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final data = await exportScorePdf(
        source: widget.source,
        name: name,
        first: int.parse(_first.text.trim()),
        last: int.parse(_last.text.trim()),
        pageCount: widget.pageCount,
        annotations: _flatten ? widget.annotations : null,
      );
      if (!mounted) return;
      if (print) {
        await Printing.layoutPdf(name: name, onLayout: (_) => data);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(data, name: name, mimeType: 'application/pdf'),
            ],
            fileNameOverrides: [name],
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Could not ${print ? 'print' : 'share'} the PDF.',
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _pageField(
    TextEditingController controller,
    String label, {
    required bool last,
  }) => TextFormField(
    controller: controller,
    enabled: !_working,
    decoration: InputDecoration(labelText: label),
    keyboardType: TextInputType.number,
    validator: (value) {
      final page = int.tryParse(value?.trim() ?? '');
      if (page == null || page < widget.firstPage || page > widget.lastPage) {
        return 'Enter a page from ${widget.firstPage} to ${widget.lastPage}';
      }
      if (last && page < (int.tryParse(_first.text.trim()) ?? 0)) {
        return 'Last page must be at or after the first';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: Scaffold(
      appBar: AppBar(title: const Text('Share or print PDF')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include visible annotations'),
                subtitle: const Text(
                  'The exported copy embeds the marks in the page images.',
                ),
                value: _flatten,
                onChanged: _working
                    ? null
                    : (value) => setState(() => _flatten = value),
              ),
              _pageField(_first, 'First page', last: false),
              _pageField(_last, 'Last page', last: true),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _working ? null : () => _export(print: false),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : () => _export(print: true),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print PDF'),
                  ),
                ],
              ),
              if (_working) const LinearProgressIndicator(),
              if (_error case final error?) Text(error),
            ],
          ),
        ),
      ),
    ),
  );
}

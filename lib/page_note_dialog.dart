import 'package:material_ui/material_ui.dart';

class PageNoteDialog extends StatefulWidget {
  const PageNoteDialog({super.key, required this.page, required this.note});

  final int page;
  final String note;

  @override
  State<PageNoteDialog> createState() => _PageNoteDialogState();
}

class _PageNoteDialogState extends State<PageNoteDialog> {
  late final _text = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Page ${widget.page} note'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _text,
        autofocus: widget.note.isEmpty,
        minLines: 3,
        maxLines: 8,
        maxLength: 4000,
        decoration: const InputDecoration(labelText: 'Note'),
      ),
    ),
    actions: [
      if (widget.note.isNotEmpty)
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Remove note'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

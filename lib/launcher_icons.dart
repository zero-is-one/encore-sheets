import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

Future<void> chooseLauncherIcon(BuildContext context) async {
  const channel = MethodChannel('encoresheets/launcher-icon');
  try {
    final active = await channel.invokeMethod<String>('get');
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Home screen icon'),
        children: [
          for (final (id, label, icon, color) in const [
            ('classic', 'Classic', Icons.library_music, Color(0xff2e3a36)),
            ('midnight', 'Midnight', Icons.music_note, Color(0xff253653)),
            ('paper', 'Paper', Icons.description, Color(0xff593b35)),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, id),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    child: Icon(icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                  if (active == id) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (!context.mounted || choice == null || choice == active) return;
    await channel.invokeMethod<void>('set', {'icon': choice});
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Home screen icon changed. Your launcher may take a moment to refresh.',
          ),
        ),
      );
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change the home screen icon.')),
      );
  }
}

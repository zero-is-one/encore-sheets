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
          for (final (id, label, asset) in const [
            ('classic', 'Classic', 'assets/brand/app-icon-classic.png'),
            ('midnight', 'Midnight', 'assets/brand/app-icon-midnight.png'),
            ('paper', 'Paper', 'assets/brand/app-icon-paper.png'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, id),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      asset,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
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

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

enum RestrictedTool {
  markup('Annotations and on-page edits'),
  transfers('PDF imports and sharing'),
  connections('External connections and automation');

  const RestrictedTool(this.label);
  final String label;
}

class ReaderRestrictions {
  const ReaderRestrictions(this.salt, this.digest, this.tools);
  final String salt;
  final String digest;
  final Set<RestrictedTool> tools;

  static ReaderRestrictions? fromJson(Object? value) {
    if (value
        case {
          'salt': final String salt,
          'digest': final String digest,
          'tools': final List tools,
        }
        when salt.length == 24 && digest.length == 44) {
      final selected = RestrictedTool.values
          .where((tool) => tools.contains(tool.name))
          .toSet();
      if (selected.isNotEmpty)
        return ReaderRestrictions(salt, digest, selected);
    }
    return null;
  }

  static Future<ReaderRestrictions> create(
    String passcode,
    Set<RestrictedTool> tools,
  ) async {
    final random = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
    return ReaderRestrictions(salt, await _hash(passcode, salt), tools);
  }

  Map<String, Object> toJson() => {
    'salt': salt,
    'digest': digest,
    'tools': [for (final tool in tools) tool.name],
  };

  Future<bool> permits(String passcode) async {
    final actual = await _hash(passcode, salt);
    if (actual.length != digest.length) return false;
    var mismatch = 0;
    for (var i = 0; i < actual.length; i++) {
      mismatch |= actual.codeUnitAt(i) ^ digest.codeUnitAt(i);
    }
    return mismatch == 0;
  }

  static Future<String> _hash(String passcode, String salt) =>
      compute(_deriveRestrictionHash, (passcode, salt));
}

String _deriveRestrictionHash((String, String) parameters) {
  final (passcode, salt) = parameters;
  final hmac = Hmac(sha256, utf8.encode(passcode));
  var digest = hmac.convert([...base64Decode(salt), 0, 0, 0, 1]).bytes;
  final derived = List<int>.of(digest);
  for (var round = 1; round < 120000; round++) {
    digest = hmac.convert(digest).bytes;
    for (var i = 0; i < derived.length; i++) {
      derived[i] ^= digest[i];
    }
  }
  return base64Encode(derived);
}

typedef RestrictionDraft = ({Set<RestrictedTool> tools, String passcode});

class RestrictionsDialog extends StatefulWidget {
  const RestrictionsDialog({super.key, this.current});
  final ReaderRestrictions? current;

  @override
  State<RestrictionsDialog> createState() => _RestrictionsDialogState();
}

class _RestrictionsDialogState extends State<RestrictionsDialog> {
  final _passcode = TextEditingController();
  final _confirmation = TextEditingController();
  late final _tools = {...?widget.current?.tools};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passcode.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_busy) return;
    final passcode = _passcode.text;
    final current = widget.current;
    if (current == null &&
        (!RegExp(r'^\d{6,12}$').hasMatch(passcode) ||
            passcode != _confirmation.text ||
            _tools.isEmpty)) {
      setState(
        () => _error = 'Select a tool and confirm a 6- to 12-digit passcode.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (current != null && !await current.permits(passcode)) {
        if (mounted) setState(() => _error = 'Incorrect passcode.');
        return;
      }
      if (mounted) Navigator.pop(context, (tools: _tools, passcode: passcode));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify the passcode.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Shared-device restrictions'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tool in RestrictedTool.values)
          CheckboxListTile(
            title: Text(tool.label),
            value: _tools.contains(tool),
            onChanged: _busy
                ? null
                : (enabled) => setState(() {
                    if (enabled == true) {
                      _tools.add(tool);
                    } else {
                      _tools.remove(tool);
                    }
                  }),
          ),
        TextField(
          controller: _passcode,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: widget.current == null
                ? 'New passcode'
                : 'Current passcode',
          ),
          maxLength: 12,
          enabled: !_busy,
        ),
        if (widget.current == null)
          TextField(
            controller: _confirmation,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Confirm passcode'),
            maxLength: 12,
            enabled: !_busy,
          ),
        if (_error case final error?) Text(error),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _apply,
        child: Text(
          _tools.isEmpty && widget.current != null
              ? 'Remove restrictions'
              : 'Save',
        ),
      ),
    ],
  );
}

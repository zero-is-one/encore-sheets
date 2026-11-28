import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

abstract interface class LibrarySyncEndpoint {
  Future<Map<String, Map<String, dynamic>>> readDevices();
  Future<void> writeDevice(String device, Map<String, dynamic> records);
  Future<void> publishPdf(String id, XFile file);
  Future<XFile> fetchPdf(String id);
}

abstract interface class SharedLibrarySyncEndpoint
    implements LibrarySyncEndpoint {
  String get stateKey;
}

abstract interface class MarkingsSyncEndpoint
    implements SharedLibrarySyncEndpoint {
  bool get includesMarkings;
}

class AppleLibrarySync implements LibrarySyncEndpoint {
  static const _channel = MethodChannel('encoresheets/library-sync');

  Future<bool> get configured async =>
      await _channel.invokeMethod<bool>('configured') ?? false;

  Future<bool> chooseFolder() async =>
      await _channel.invokeMethod<bool>('chooseFolder') ?? false;

  Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');

  @override
  Future<Map<String, Map<String, dynamic>>> readDevices() async {
    final archives =
        await _channel.invokeMapMethod<String, String>('readDevices') ?? {};
    return {
      for (final entry in archives.entries)
        entry.key: jsonDecode(entry.value) as Map<String, dynamic>,
    };
  }

  @override
  Future<void> writeDevice(String device, Map<String, dynamic> records) =>
      _channel.invokeMethod('writeDevice', {
        'id': device,
        'json': jsonEncode(records),
      });

  @override
  Future<void> publishPdf(String id, XFile file) =>
      _channel.invokeMethod('publishPdf', {'id': id, 'path': file.path});

  @override
  Future<XFile> fetchPdf(String id) async {
    final path = await _channel.invokeMethod<String>('fetchPdf', {'id': id});
    if (path == null) throw StateError('The shared score is not ready.');
    return XFile(path);
  }
}

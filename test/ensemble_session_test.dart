import 'dart:io';

import 'package:encoresheets/ensemble_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ensemble endpoints are limited to private IPv4 addresses', () {
    for (final address in ['192.168.0.10', '10.0.0.4', '172.31.1.1']) {
      expect(isEnsembleAddress(InternetAddress(address)), isTrue);
    }
    for (final address in ['172.32.0.1', '8.8.8.8', '127.0.0.1', '::1']) {
      expect(isEnsembleAddress(InternetAddress(address)), isFalse);
    }
  });
}

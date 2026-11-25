import 'package:flutter/services.dart';

Future<ByteData> loadPdfTextFont() =>
    rootBundle.load('assets/NotoSans-Regular.ttf');

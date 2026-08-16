// Regenerates the checked-in reference matrices from the independent `qr` Dart
// package used by the iPhone UI. Run from the repository root with:
//   dart run ios/CelechronWatchTests/generate_qr_fixtures.dart

import 'dart:convert';

import 'package:qr/qr.dart';

void main() {
  const payloads = [
    '12345678901234',
    '12345678901234567890123456',
    '123456789012345678901234567890123456789012',
  ];

  final fixtures = <Map<String, Object>>[];
  for (final payload in payloads) {
    final version = switch (utf8.encode(payload).length) {
      <= 14 => 1,
      <= 26 => 2,
      _ => 3,
    };
    final code = QrCode(version, QrErrorCorrectLevel.M)..addData(payload);
    final image = QrImage.withMaskPattern(code, 0);
    fixtures.add({
      'payload': payload,
      'version': version,
      'rows': [
        for (var y = 0; y < image.moduleCount; y++)
          [
            for (var x = 0; x < image.moduleCount; x++)
              image.isDark(y, x) ? '1' : '0',
          ].join(),
      ],
    });
  }

  const encoder = JsonEncoder.withIndent('  ');
  print(encoder.convert(fixtures));
}

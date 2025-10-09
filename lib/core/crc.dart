import 'dart:typed_data';

import 'package:archive/archive_io.dart';

int calcCrc(Uint8List data) {
  return getCrc32(data);
}

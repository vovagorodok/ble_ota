import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

Uint8List compress(Uint8List data) {
  return Uint8List.fromList(ZLibEncoder().convert(data));
}

Uint8List decompress(Uint8List data) {
  return Uint8List.fromList(ZLibDecoder().convert(data));
}

bool isCompressionSupportedByPlatform() {
  return !kIsWeb;
}

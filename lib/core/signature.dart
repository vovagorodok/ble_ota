import 'dart:typed_data';

const signatureSize = 256;

bool isValidSignedSize(Uint8List data) {
  return data.length > signatureSize;
}

Uint8List getSignature(Uint8List data) {
  return data.sublist(data.length - signatureSize);
}

Uint8List removeSignature(Uint8List data) {
  return data.sublist(0, data.length - signatureSize);
}

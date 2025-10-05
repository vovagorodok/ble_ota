import 'dart:typed_data';

import 'package:ble_backend/utils/converters.dart';

List<bool> byteToBits(int byte, int size) {
  return List.generate(size, (i) => (byte & (1 << i)) != 0);
}

int bitsToByte(List<bool> bits) {
  int value = 0;
  for (int i = 0; i < bits.length; i++) {
    if (bits[i]) value |= (1 << i);
  }
  return value;
}

class MaxValue {
  static const uint8 = 0xFF;
  static const uint16 = 0xFFFF;
  static const uint32 = 0xFFFFFFFF;
}

class BytesSize {
  static const uint8 = 1;
  static const uint16 = 2;
  static const uint32 = 4;
}

const headerSize = BytesSize.uint8;

class HeaderCode {
  static const initReq = 0x01;
  static const initResp = 0x02;
  static const beginReq = 0x03;
  static const beginResp = 0x04;
  static const packageInd = 0x05;
  static const packageReq = 0x06;
  static const packageResp = 0x07;
  static const endReq = 0x08;
  static const endResp = 0x09;
  static const errorInd = 0x10;
  static const uploadEnableInd = 0x11;
  static const uploadDisableInd = 0x12;
  static const signatureReq = 0x20;
  static const signatureResp = 0x21;
  static const setPinReq = 0x30;
  static const setPinResp = 0x31;
  static const removePinReq = 0x32;
  static const removePinResp = 0x33;
}

class ErrorCode {
  static const ok = 0x00;
  static const incorrectMessageSize = 0x01;
  static const incorrectMessageHeader = 0x02;
  static const incorrectFirmwareSize = 0x03;
  static const internalStorageError = 0x04;
  static const uploadDisabled = 0x10;
  static const uploadRunning = 0x11;
  static const uploadStopped = 0x12;
  static const installRunning = 0x13;
  static const bufferDisabled = 0x20;
  static const bufferOverflow = 0x21;
  static const compressionNotSupported = 0x30;
  static const incorrectCompression = 0x31;
  static const incorrectCompressedSize = 0x32;
  static const incorrectCompressionChecksum = 0x33;
  static const incorrectCompressionParam = 0x34;
  static const incorrectCompressionEnd = 0x35;
  static const checksumNotSupported = 0x40;
  static const incorrectChecksum = 0x41;
  static const signatureNotSupported = 0x50;
  static const incorrectSignature = 0x51;
  static const incorrectSignatureSize = 0x52;
  static const pinNotSupported = 0x60;
  static const pinChangeError = 0x61;
}

class Message {
  final int header;

  Message({required this.header});

  factory Message.fromBytes(Uint8List data) {
    return Message(header: bytesToUint8(data, 0));
  }

  static bool isValidSize(Uint8List data) => data.length >= headerSize;
}

class InitReq extends Message {
  InitReq() : super(header: HeaderCode.initReq);

  Uint8List toBytes() => uint8ToBytes(this.header);
}

class InitRespFlags {
  final bool compression;
  final bool checksum;
  final bool upload;
  final bool signature;
  final bool pin;

  InitRespFlags({
    required this.compression,
    required this.checksum,
    required this.upload,
    required this.signature,
    required this.pin,
  });

  factory InitRespFlags.fromByte(int byte) {
    final [
      compression,
      checksum,
      upload,
      pin,
      signature,
    ] = byteToBits(byte, 5);
    return InitRespFlags(
      compression: compression,
      checksum: checksum,
      upload: upload,
      signature: pin,
      pin: signature,
    );
  }
}

class InitResp extends Message {
  final InitRespFlags flags;

  InitResp({required this.flags}) : super(header: HeaderCode.initResp);

  factory InitResp.fromBytes(Uint8List data) {
    return InitResp(flags: InitRespFlags.fromByte(data[_flagsOffset]));
  }

  static bool isValidSize(Uint8List data) => data.length == _size;

  static const int _flagsOffset = headerSize;
  static const int _size = _flagsOffset + BytesSize.uint8;
}

class BeginReqFlags {
  final bool compression;
  final bool checksum;

  BeginReqFlags({
    required this.compression,
    required this.checksum,
  });

  int toByte() {
    return bitsToByte([
      this.compression,
      this.checksum,
    ]);
  }
}

class BeginReq extends Message {
  final int firmwareSize;
  final int packageSize;
  final int bufferSize;
  final int compressedSize;
  final BeginReqFlags flags;

  BeginReq({
    required this.firmwareSize,
    required this.packageSize,
    required this.bufferSize,
    required this.compressedSize,
    required this.flags,
  }) : super(header: HeaderCode.beginReq);

  Uint8List toBytes() {
    return Uint8List.fromList(uint8ToBytes(this.header) +
        uint32ToBytes(this.firmwareSize) +
        uint32ToBytes(this.packageSize) +
        uint32ToBytes(this.bufferSize) +
        uint32ToBytes(this.compressedSize) +
        uint8ToBytes(this.flags.toByte()));
  }
}

class BeginResp extends Message {
  final int packageSize;
  final int bufferSize;

  BeginResp({
    required this.packageSize,
    required this.bufferSize,
  }) : super(header: HeaderCode.beginResp);

  factory BeginResp.fromBytes(Uint8List data) {
    return BeginResp(
      packageSize: bytesToUint32(data, _packageSizeOffset),
      bufferSize: bytesToUint32(data, _bufferSizeOffset),
    );
  }

  static bool isValidSize(Uint8List data) => data.length == _size;

  static const int _packageSizeOffset = headerSize;
  static const int _bufferSizeOffset = _packageSizeOffset + BytesSize.uint32;
  static const int _size = _bufferSizeOffset + BytesSize.uint32;
}

abstract class Package extends Message {
  final Uint8List data;

  Package({
    required int header,
    required this.data,
  }) : super(header: header);

  Uint8List toBytes() {
    return Uint8List.fromList(uint8ToBytes(this.header) + this.data);
  }
}

class PackageInd extends Package {
  PackageInd({
    required Uint8List data,
  }) : super(header: HeaderCode.packageInd, data: data);
}

class PackageReq extends Package {
  PackageReq({
    required Uint8List data,
  }) : super(header: HeaderCode.packageReq, data: data);
}

class PackageResp extends Message {
  PackageResp() : super(header: HeaderCode.packageResp);

  static bool isValidSize(Uint8List data) => data.length == headerSize;
}

class EndReq extends Message {
  final int firmwareCrc;

  EndReq({
    required this.firmwareCrc,
  }) : super(header: HeaderCode.endReq);

  Uint8List toBytes() {
    return Uint8List.fromList(
        uint8ToBytes(this.header) + uint32ToBytes(this.firmwareCrc));
  }
}

class EndResp extends Message {
  EndResp() : super(header: HeaderCode.endResp);

  static bool isValidSize(Uint8List data) => data.length == headerSize;
}

class ErrorInd extends Message {
  final int code;

  ErrorInd({
    required this.code,
  }) : super(header: HeaderCode.errorInd);

  factory ErrorInd.fromBytes(Uint8List data) {
    return ErrorInd(
      code: data[_codeOffset],
    );
  }

  static bool isValidSize(Uint8List data) => data.length == _size;

  static const int _codeOffset = headerSize;
  static const int _size = _codeOffset + BytesSize.uint8;
}

class UploadEnableInd extends Message {
  UploadEnableInd() : super(header: HeaderCode.uploadEnableInd);

  static bool isValidSize(Uint8List data) => data.length == headerSize;
}

class UploadDisableInd extends Message {
  UploadDisableInd() : super(header: HeaderCode.uploadDisableInd);

  static bool isValidSize(Uint8List data) => data.length == headerSize;
}

class SignatureReq extends Package {
  SignatureReq({
    required Uint8List data,
  }) : super(header: HeaderCode.signatureReq, data: data);
}

class SignatureResp extends Message {
  SignatureResp() : super(header: HeaderCode.signatureResp);

  static bool isValidSize(Uint8List data) => data.length == headerSize;
}

class SetPinReq extends Message {
  final int pin;

  SetPinReq({
    required this.pin,
  }) : super(header: HeaderCode.setPinReq);

  Uint8List toBytes() {
    return Uint8List.fromList(
        uint8ToBytes(this.header) + uint32ToBytes(this.pin));
  }
}

class SetPinResp extends Message {
  SetPinResp() : super(header: HeaderCode.setPinResp);

  static bool isValidSize(Uint8List data) => data.length == headerSize;
}

class RemovePinReq extends Message {
  RemovePinReq() : super(header: HeaderCode.removePinReq);

  Uint8List toBytes() => uint8ToBytes(this.header);
}

class RemovePinResp extends Message {
  RemovePinResp() : super(header: HeaderCode.removePinResp);

  static bool isValidSize(Uint8List data) => data.length == headerSize;
}

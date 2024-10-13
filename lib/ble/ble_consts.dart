import 'package:ble_ota/core/errors.dart';

// BLE packet types:
// https://microchipdeveloper.com/wireless:ble-link-layer-packet-types
// MTU overhead:
// https://docs.silabs.com/bluetooth/4.0/general/system-and-performance/throughput-with-bluetooth-low-energy-technology#attribute-protocol-att-operation
const mtuWriteOverheadBytesNum = 3;

const uint8BytesNum = 1;
const uint32BytesNum = 4;
const headCodeBytesNum = uint8BytesNum;
const attrSizeBytesNum = uint32BytesNum;
const bufferSizeBytesNum = uint32BytesNum;
const beginRespBytesNum =
    headCodeBytesNum + attrSizeBytesNum + bufferSizeBytesNum;
const headCodePos = 0;
const attrSizePos = headCodePos + headCodeBytesNum;
const bufferSizePos = attrSizePos + attrSizeBytesNum;

class HeadCode {
  static const ok = 0x00;
  static const nok = 0x01;
  static const incorrectFormat = 0x02;
  static const incorrectFirmwareSize = 0x03;
  static const checksumError = 0x04;
  static const internalSrorageError = 0x05;
  static const uploadDisabled = 0x06;

  static const begin = 0x10;
  static const package = 0x11;
  static const end = 0x12;

  static const setPin = 0x20;
  static const removePin = 0x21;
}

UploadError determineErrorHeadCode(int code) {
  switch (code) {
    case HeadCode.nok:
      return UploadError.generalDeviceError;
    case HeadCode.incorrectFormat:
      return UploadError.incorrectPackageFormat;
    case HeadCode.incorrectFirmwareSize:
      return UploadError.incorrectFirmwareSize;
    case HeadCode.checksumError:
      return UploadError.incorrectChecksum;
    case HeadCode.internalSrorageError:
      return UploadError.internalSrorageError;
    case HeadCode.uploadDisabled:
      return UploadError.uploadDisabled;
    default:
      return UploadError.unexpectedDeviceResponse;
  }
}

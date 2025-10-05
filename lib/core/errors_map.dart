import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/messages.dart';

const Map<int, Error> errorCodeMap = {
  ErrorCode.incorrectMessageSize: Error.incorrectMessageSize,
  ErrorCode.incorrectMessageHeader: Error.incorrectMessageHeader,
  ErrorCode.incorrectFirmwareSize: Error.incorrectFirmwareSize,
  ErrorCode.internalStorageError: Error.internalStorageError,
  ErrorCode.uploadDisabled: Error.uploadDisabled,
  ErrorCode.uploadRunning: Error.uploadRunning,
  ErrorCode.uploadStopped: Error.uploadStopped,
  ErrorCode.installRunning: Error.installRunning,
  ErrorCode.bufferDisabled: Error.bufferDisabled,
  ErrorCode.bufferOverflow: Error.bufferOverflow,
  ErrorCode.compressionNotSupported: Error.compressionNotSupported,
  ErrorCode.incorrectCompression: Error.incorrectCompression,
  ErrorCode.incorrectCompressedSize: Error.incorrectCompressedSize,
  ErrorCode.incorrectCompressionChecksum: Error.incorrectCompressionChecksum,
  ErrorCode.incorrectCompressionParam: Error.incorrectCompressionParam,
  ErrorCode.incorrectCompressionEnd: Error.incorrectCompressionEnd,
  ErrorCode.checksumNotSupported: Error.checksumNotSupported,
  ErrorCode.incorrectChecksum: Error.incorrectChecksum,
  ErrorCode.signatureNotSupported: Error.signatureNotSupported,
  ErrorCode.incorrectSignature: Error.incorrectSignature,
  ErrorCode.incorrectSignatureSize: Error.incorrectSignatureSize,
  ErrorCode.pinNotSupported: Error.pinNotSupported,
  ErrorCode.pinChangeError: Error.pinChangeError,
};

Error determineErrorCode(int code) {
  return errorCodeMap[code] ?? Error.incorrectDeviceResponse;
}

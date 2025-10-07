import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ble_backend/ble_connector.dart';
import 'package:ble_backend/ble_mtu.dart';
import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/utils/serialization.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/ble/consts.dart';
import 'package:ble_ota/core/errors_map.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/messages.dart';

class Uploader extends StatefulNotifier<UploadState> {
  Uploader({
    required BleConnector bleConnector,
    required BleSerial bleSerial,
    int? maxMtuSize = null,
    int? maxBufferSize = null,
    bool sequentialUpload = false,
  })  : _bleMtu = bleConnector.createMtu(),
        _bleSerial = bleSerial,
        _sequentialUpload = sequentialUpload,
        _maxBufferSize = maxBufferSize,
        _maxMtuSize = maxMtuSize;

  final BleMtu _bleMtu;
  final BleSerial _bleSerial;
  final int? _maxMtuSize;
  final int? _maxBufferSize;
  final bool _sequentialUpload;
  StreamSubscription? _subscription;
  UploadState _state = UploadState();
  Uint8List _firmwareData = Uint8List(0);
  Uint8List? _signatureData = null;
  int? _firmwareCrc = null;
  int _packageSize = 0;
  int _bufferSize = 0;
  int _currentDataPos = 0;
  int _currentBufferSize = 0;

  @override
  UploadState get state => _state;

  Future<void> upload({
    required Uint8List firmwareData,
    Uint8List? signatureData,
    int? firmwareCrc,
    int? decompressedSize,
  }) async {
    try {
      _subscription = _bleSerial.dataStream.listen(_handleMessage);
      _state = UploadState(status: UploadStatus.begin);
      notifyState(state);

      _packageSize = await _calcMaxPackageSize();
      _bufferSize = _calcMaxBufferSize();
      _firmwareData = firmwareData;
      _signatureData = signatureData;
      _firmwareCrc = firmwareCrc;

      _sendBeginReq(decompressedSize: decompressedSize);
    } catch (_) {
      _raiseError(Error.deviceError);
    }
  }

  void _handleMessage(Uint8List data) {
    if (!Message.isValidSize(data)) {
      _raiseError(Error.incorrectMessageSize);
      return;
    }

    final message = Message.fromBytes(data);
    final header = message.header;

    switch (header) {
      case HeaderCode.beginResp:
        BeginResp.isValidSize(data)
            ? _handleBeginResp(BeginResp.fromBytes(data))
            : _raiseError(Error.incorrectMessageSize);
        break;
      case HeaderCode.packageResp:
        PackageResp.isValidSize(data)
            ? _handlePackageResp(PackageResp())
            : _raiseError(Error.incorrectMessageSize);
        break;
      case HeaderCode.signatureResp:
        SignatureResp.isValidSize(data)
            ? _handleSignatureResp(SignatureResp())
            : _raiseError(Error.incorrectMessageSize);
        break;
      case HeaderCode.endResp:
        EndResp.isValidSize(data)
            ? _handleEndResp(EndResp())
            : _raiseError(Error.incorrectMessageSize);
        break;
      case HeaderCode.uploadEnableInd:
        if (!UploadEnableInd.isValidSize(data))
          _raiseError(Error.incorrectMessageSize);
        break;
      case HeaderCode.uploadDisableInd:
        if (!UploadDisableInd.isValidSize(data))
          _raiseError(Error.incorrectMessageSize);
        break;
      case HeaderCode.errorInd:
        ErrorInd.isValidSize(data)
            ? _raiseError(determineErrorCode(ErrorInd.fromBytes(data).code))
            : _raiseError(Error.incorrectMessageSize);
        break;
      default:
        _raiseError(
          Error.unexpectedDeviceResponse,
          errorCode: header,
        );
    }
  }

  void _sendBeginReq({int? decompressedSize}) {
    final isCompressed = decompressedSize != null;

    final beginReq = BeginReq(
      firmwareSize: isCompressed ? decompressedSize : _firmwareData.length,
      packageSize: _packageSize,
      bufferSize: _bufferSize,
      compressedSize: isCompressed ? _firmwareData.length : 0,
      flags: BeginReqFlags(
        compression: isCompressed,
        checksum: _firmwareCrc != null,
      ),
    );

    _sendMessage(beginReq.toBytes());
    _waitMessage();
  }

  void _handleBeginResp(BeginResp resp) {
    if (state.status != UploadStatus.begin) {
      _raiseError(
        Error.unexpectedDeviceResponse,
        errorCode: resp.header,
      );
      return;
    }

    state.status = UploadStatus.upload;
    notifyState(state);

    _packageSize = resp.packageSize;
    _bufferSize = resp.bufferSize;
    _currentDataPos = 0;
    _currentBufferSize = 0;

    _sendPackages();
  }

  void _sendPackages() async {
    while (_currentDataPos < _firmwareData.length) {
      final packageData = _getPackege(_firmwareData);
      final packageSize = packageData.length;
      _currentDataPos += packageSize;
      _currentBufferSize += packageSize;
      final isBufferFull = _currentBufferSize > _bufferSize;

      final package = isBufferFull
          ? PackageReq(data: packageData)
          : PackageInd(data: packageData);

      _sequentialUpload
          ? await _sendMessage(package.toBytes())
          : _sendMessage(package.toBytes());

      state.progress =
          _currentDataPos.toDouble() / _firmwareData.length.toDouble();
      notifyState(state);

      if (isBufferFull) {
        _currentBufferSize = packageSize;
        _waitMessage();
        return;
      }
    }

    if (_signatureData == null) {
      _sendEndReq();
    } else {
      _currentDataPos = 0;
      _sendSignature();
    }
  }

  void _handlePackageResp(PackageResp resp) {
    if (state.status != UploadStatus.upload) {
      _raiseError(
        Error.unexpectedDeviceResponse,
        errorCode: resp.header,
      );
      return;
    }

    _sendPackages();
  }

  void _sendSignature() async {
    if (_signatureData == null) {
      _raiseError(Error.signatureNotSupported);
      return;
    }
    final signatureData = _signatureData!;
    if (_currentDataPos > signatureData.length) {
      _raiseError(Error.incorrectSignatureSize);
      return;
    }
    if (_currentDataPos == signatureData.length) {
      _sendEndReq();
      return;
    }

    final packageData = _getPackege(signatureData);
    _currentDataPos += packageData.length;

    _sendMessage(SignatureReq(data: packageData).toBytes());
    _waitMessage();
  }

  void _handleSignatureResp(SignatureResp resp) {
    if (state.status != UploadStatus.upload) {
      _raiseError(
        Error.unexpectedDeviceResponse,
        errorCode: resp.header,
      );
      return;
    }

    _sendSignature();
  }

  void _sendEndReq() {
    _sendMessage(EndReq(firmwareCrc: _firmwareCrc ?? 0).toBytes());
    state.status = UploadStatus.end;
    _waitMessage();
  }

  void _handleEndResp(EndResp resp) {
    if (state.status != UploadStatus.end) {
      _raiseError(
        Error.unexpectedDeviceResponse,
        errorCode: resp.header,
      );
      return;
    }

    _unsubscribe();
    _firmwareData = Uint8List(0);
    state.status = UploadStatus.success;
    notifyState(state);
  }

  Future<int> _calcMaxPackageSize() async {
    if (_maxMtuSize == null) return MaxValue.uint32;

    final mtu = _bleMtu.isRequestSupported
        ? await _bleMtu.request(mtu: _maxMtuSize!)
        : _maxMtuSize!;

    return mtu - mtuWriteOverheadSize - headerSize;
  }

  int _calcMaxBufferSize() {
    return _maxBufferSize ?? MaxValue.uint32;
  }

  Uint8List _getPackege(Uint8List data) {
    final packageSize = min(data.length - _currentDataPos, _packageSize);
    final packageEndPos = _currentDataPos + packageSize;
    final packageData = data.sublist(_currentDataPos, packageEndPos);
    return packageData;
  }

  Future<void> _sendMessage(Uint8List data) async {
    await _bleSerial.send(data: data);
  }

  void _waitMessage() {
    _bleSerial.waitData(
        timeoutCallback: () => _raiseError(Error.noDeviceResponse));
  }

  void _raiseError(Error error, {int errorCode = 0}) {
    _unsubscribe();
    state.status = UploadStatus.error;
    state.error = error;
    state.errorCode = errorCode;
    notifyState(state);
  }

  void _unsubscribe() {
    _subscription?.cancel();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}

class UploadState extends WorkState<UploadStatus, Error> {
  UploadState({
    super.status = UploadStatus.idle,
    super.error = Error.unknown,
    this.progress = 0.0,
  });

  double progress;
}

enum UploadStatus {
  idle,
  begin,
  upload,
  end,
  success,
  error,
}

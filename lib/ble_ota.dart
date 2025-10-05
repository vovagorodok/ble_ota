import 'dart:io';
import 'dart:typed_data';

import 'package:ble_backend/ble_connector.dart';
import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/ble/ble_flags_observer.dart';
import 'package:ble_ota/ble/ble_flags_reader.dart';
import 'package:ble_ota/ble/ble_info_reader.dart';
import 'package:ble_ota/ble/ble_pin_changer.dart';
import 'package:ble_ota/ble/ble_uploader.dart';
import 'package:ble_ota/ble/ble_uuids.dart';
import 'package:ble_ota/core/compression.dart';
import 'package:ble_ota/core/crc.dart';
import 'package:ble_ota/core/device_flags.dart';
import 'package:ble_ota/core/device_info.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/remote_info.dart';
import 'package:ble_ota/core/signature.dart';
import 'package:ble_ota/http/http_info_reader.dart';
import 'package:http/http.dart' as http;

class BleOta extends StatefulNotifier<BleOtaState> {
  BleOta({
    required BleConnector bleConnector,
    String? manufacturesDictUrl = null,
    int? maxMtu = null,
    bool skipInfoReading = false,
    bool sequentialUpload = false,
  })  : _bleSerial = bleConnector.createSerial(
            serviceId: serviceUuid,
            rxCharacteristicId: characteristicUuidRx,
            txCharacteristicId: characteristicUuidTx),
        _manufacturesDictUrl = manufacturesDictUrl,
        _skipInfoReading = skipInfoReading {
    _bleFlagsReader = BleFlagsReader(bleSerial: _bleSerial);
    _bleInfoReader = BleInfoReader(bleConnector: bleConnector);
    _httpInfoReader = HttpInfoReader();
    _bleUploader = BleUploader(
        bleConnector: bleConnector,
        bleSerial: _bleSerial,
        maxMtu: maxMtu,
        sequentialUpload: sequentialUpload);
    _blePinChanger = BlePinChanger(bleSerial: _bleSerial);
    _bleFlagsObserver = BleFlagsObserver(bleSerial: _bleSerial);

    _bleFlagsReader.stateStream.listen(_onDeviceFlagsStateChanged);
    _bleInfoReader.stateStream.listen(_onDeviceInfoStateChanged);
    _httpInfoReader.stateStream.listen(_onRemoteInfoStateChanged);
    _bleUploader.stateStream.listen(_onBleUploadStateChanged);
    _blePinChanger.stateStream.listen(_onBlePinChangeStateChanged);
    _bleFlagsObserver.stateStream.listen(_onDeviceObserverStateChanged);
  }

  final BleSerial _bleSerial;
  late final BleFlagsReader _bleFlagsReader;
  late final BleInfoReader _bleInfoReader;
  late final HttpInfoReader _httpInfoReader;
  late final BleUploader _bleUploader;
  late final BlePinChanger _blePinChanger;
  late final BleFlagsObserver _bleFlagsObserver;
  final bool _skipInfoReading;
  String? _manufacturesDictUrl;
  BleOtaState _state = BleOtaState(
    deviceFlags: DeviceFlags(),
    remoteInfo: RemoteInfo(),
  );

  @override
  BleOtaState get state => _state;

  void init() {
    _state = BleOtaState(
      status: BleOtaStatus.init,
      deviceFlags: DeviceFlags(),
      remoteInfo: RemoteInfo(),
    );
    notifyState(state);

    _bleSerial.startNotifications();
    _bleFlagsObserver.stop();
    _bleFlagsReader.read();
  }

  Future<void> uploadBytes({required Uint8List bytes}) async {
    await _upload(data: bytes);
  }

  Future<void> uploadLocalFile({required String localPath}) async {
    File file = File(localPath);
    await _upload(data: await file.readAsBytes());
  }

  Future<void> uploadHttpFile({required String url, int? size}) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        _raiseError(
          Error.unexpectedNetworkResponse,
          errorCode: response.statusCode,
        );
        return;
      }

      await _upload(data: await response.bodyBytes, size: size);
    } catch (_) {
      _raiseError(Error.networkError);
    }
  }

  void setPin({required int pin}) {
    _bleFlagsObserver.stop();
    _state.status = BleOtaStatus.pinChange;
    notifyState(state);
    _blePinChanger.set(pin: pin);
  }

  void removePin() {
    _bleFlagsObserver.stop();
    _state.status = BleOtaStatus.pinChange;
    notifyState(state);
    _blePinChanger.remove();
  }

  Future<void> _upload({required Uint8List data, int? size}) async {
    _bleFlagsObserver.stop();
    _state.status = BleOtaStatus.upload;

    final isSignatureRequired = state.deviceFlags.signatureRequired;
    if (isSignatureRequired && !isValidSignedSize(data)) {
      _raiseError(Error.incorrectSignatureSize);
      return;
    }
    final signatureData = isSignatureRequired ? getSignature(data) : null;
    final unsignedData = isSignatureRequired ? removeSignature(data) : data;

    final isCompressionSupported = state.deviceFlags.compressionSupported;
    final isDataCompressed = size != null && size != unsignedData.length;
    if (isDataCompressed && unsignedData.length > size) {
      _raiseError(Error.incorrectCompressedSize);
      return;
    }
    final firmwareData = isCompressionSupported
        ? isDataCompressed
            ? unsignedData
            : compress(unsignedData)
        : isDataCompressed
            ? decompress(unsignedData)
            : unsignedData;
    final decompressedSize = isCompressionSupported
        ? isDataCompressed
            ? size
            : unsignedData.length
        : null;

    final isChecksumSupported = state.deviceFlags.checksumSupported;
    final firmwareCrc = isChecksumSupported ? calcCrc(firmwareData) : null;

    await _bleUploader.upload(
      firmwareData: firmwareData,
      signatureData: signatureData,
      firmwareCrc: firmwareCrc,
      decompressedSize: decompressedSize,
    );
  }

  void _onDeviceFlagsStateChanged(DeviceFlagsState deviceFlagsState) {
    if (deviceFlagsState.status == WorkStatus.success) {
      state.deviceFlags = deviceFlagsState.flags;
      _bleFlagsObserver.start(uploadEnabled: state.deviceFlags.uploadEnabled);
      if (!_skipInfoReading) {
        _bleInfoReader.read();
      } else {
        state.status = BleOtaStatus.initialized;
        notifyState(state);
      }
    } else if (deviceFlagsState.status == WorkStatus.error) {
      _raiseError(
        deviceFlagsState.error,
        errorCode: deviceFlagsState.errorCode,
      );
    }
  }

  void _onDeviceInfoStateChanged(DeviceInfoState deviceInfoState) {
    if (deviceInfoState.status == WorkStatus.success) {
      state.deviceInfo = deviceInfoState.info;
      if (_manufacturesDictUrl != null) {
        _httpInfoReader.read(state.deviceInfo, _manufacturesDictUrl!);
      } else {
        state.status = BleOtaStatus.initialized;
        notifyState(state);
      }
    } else if (deviceInfoState.status == WorkStatus.error) {
      _raiseError(deviceInfoState.error, errorCode: deviceInfoState.errorCode);
    }
  }

  void _onRemoteInfoStateChanged(RemoteInfoState remoteInfoState) {
    if (remoteInfoState.status == WorkStatus.success) {
      state.remoteInfo = remoteInfoState.info;
      state.status = BleOtaStatus.initialized;
      notifyState(state);
    } else if (remoteInfoState.status == WorkStatus.error) {
      _raiseError(remoteInfoState.error, errorCode: remoteInfoState.errorCode);
    }
  }

  void _onBleUploadStateChanged(BleUploadState bleUploadState) {
    state.uploadProgress = bleUploadState.progress;
    if (bleUploadState.status == BleUploadStatus.success) {
      state.status = BleOtaStatus.uploaded;
      notifyState(state);
    } else if (bleUploadState.status == BleUploadStatus.error) {
      _raiseError(bleUploadState.error, errorCode: bleUploadState.errorCode);
    } else {
      notifyState(state);
    }
  }

  void _onBlePinChangeStateChanged(BlePinChangeState blePinChangeState) {
    if (blePinChangeState.status == WorkStatus.success) {
      state.status = BleOtaStatus.pinChanged;
      _bleFlagsObserver.start(uploadEnabled: state.deviceFlags.uploadEnabled);
      notifyState(state);
    } else if (blePinChangeState.status == WorkStatus.error) {
      _raiseError(
        blePinChangeState.error,
        errorCode: blePinChangeState.errorCode,
      );
    }
  }

  void _onDeviceObserverStateChanged(DeviceObserverState deviceObserverState) {
    if (deviceObserverState.status != WorkStatus.error) {
      state.deviceFlags.uploadEnabled = deviceObserverState.uploadEnabled;
      notifyState(state);
    } else {
      _raiseError(
        deviceObserverState.error,
        errorCode: deviceObserverState.errorCode,
      );
    }
  }

  void _raiseError(Error error, {int errorCode = 0}) {
    state.status = BleOtaStatus.error;
    state.error = error;
    state.errorCode = errorCode;
    state.deviceFlags.uploadEnabled = false;
    notifyState(state);
  }

  @override
  void dispose() {
    _bleSerial.stopNotifications();
    _bleSerial.dispose();
    super.dispose();
  }
}

class BleOtaState extends WorkState<BleOtaStatus, Error> {
  BleOtaState({
    super.status = BleOtaStatus.idle,
    super.error = Error.unknown,
    required this.deviceFlags,
    this.deviceInfo = const DeviceInfo(),
    required this.remoteInfo,
    this.uploadProgress = 0.0,
  });

  DeviceFlags deviceFlags;
  DeviceInfo deviceInfo;
  RemoteInfo remoteInfo;
  double uploadProgress;
}

enum BleOtaStatus {
  idle,
  init,
  initialized,
  upload,
  uploaded,
  pinChange,
  pinChanged,
  error,
}

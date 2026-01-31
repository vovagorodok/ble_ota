import 'dart:io';
import 'dart:typed_data';

import 'package:ble_backend/ble_connector.dart';
import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/ble/device_capabilities_reader.dart';
import 'package:ble_ota/ble/device_info_reader.dart';
import 'package:ble_ota/ble/pin_changer.dart';
import 'package:ble_ota/ble/upload_capability_observer.dart';
import 'package:ble_ota/ble/uploader.dart';
import 'package:ble_ota/ble/uuids.dart';
import 'package:ble_ota/core/compression.dart';
import 'package:ble_ota/core/crc.dart';
import 'package:ble_ota/core/device_capabilities.dart';
import 'package:ble_ota/core/device_info.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/remote_info.dart';
import 'package:ble_ota/core/signature.dart';
import 'package:ble_ota/http/remote_info_reader.dart';
import 'package:http/http.dart' as http;

class BleOta extends StatefulNotifier<BleOtaState> {
  BleOta({
    required BleConnector bleConnector,
    String? manufacturesDictUrl = null,
    int? maxMtuSize = null,
    int? maxBufferSize = null,
    bool skipInfoReading = false,
    bool sequentialUpload = false,
  })  : _bleSerial = bleConnector.createSerial(
            serviceId: serviceUuid,
            rxCharacteristicId: characteristicUuidRx,
            txCharacteristicId: characteristicUuidTx),
        _manufacturesDictUrl = manufacturesDictUrl,
        _skipInfoReading = skipInfoReading {
    _deviceCapabilitiesReader = DeviceCapabilitiesReader(bleSerial: _bleSerial);
    _deviceInfoReader = DeviceInfoReader(bleConnector: bleConnector);
    _remoteInfoReader = RemoteInfoReader();
    _uploader = Uploader(
        bleConnector: bleConnector,
        bleSerial: _bleSerial,
        maxMtuSize: maxMtuSize,
        maxBufferSize: maxBufferSize,
        sequentialUpload: sequentialUpload);
    _pinChanger = PinChanger(bleSerial: _bleSerial);
    _uploadCapabilityObserver = UploadCapabilityObserver(bleSerial: _bleSerial);

    _deviceCapabilitiesReader.stateStream
        .listen(_onDeviceCapabilitiesStateChanged);
    _deviceInfoReader.stateStream.listen(_onDeviceInfoStateChanged);
    _remoteInfoReader.stateStream.listen(_onRemoteInfoStateChanged);
    _uploader.stateStream.listen(_onUploadStateChanged);
    _pinChanger.stateStream.listen(_onPinChangeStateChanged);
    _uploadCapabilityObserver.stateStream
        .listen(_onUploadCapabilityStateChanged);
  }

  final BleSerial _bleSerial;
  late final DeviceCapabilitiesReader _deviceCapabilitiesReader;
  late final DeviceInfoReader _deviceInfoReader;
  late final RemoteInfoReader _remoteInfoReader;
  late final Uploader _uploader;
  late final PinChanger _pinChanger;
  late final UploadCapabilityObserver _uploadCapabilityObserver;
  final bool _skipInfoReading;
  String? _manufacturesDictUrl;
  BleOtaState _state = BleOtaState(
    deviceCapabilities: DeviceCapabilities(),
    remoteInfo: RemoteInfo(),
  );

  @override
  BleOtaState get state => _state;

  Future<void> init() async {
    _state = BleOtaState(
      status: BleOtaStatus.init,
      deviceCapabilities: DeviceCapabilities(),
      remoteInfo: RemoteInfo(),
    );
    notifyState(state);

    await _bleSerial.startNotifications();
    _uploadCapabilityObserver.stop();
    _deviceCapabilitiesReader.read();
  }

  Future<void> uploadBytes({required Uint8List bytes}) async {
    _state.status = BleOtaStatus.upload;
    notifyState(state);

    await _upload(data: bytes);
  }

  Future<void> uploadLocalFile({required String localPath}) async {
    _state.status = BleOtaStatus.upload;
    notifyState(state);

    File file = File(localPath);
    await _upload(data: await file.readAsBytes());
  }

  Future<void> uploadHttpFile({required String url, int? size}) async {
    _state.status = BleOtaStatus.upload;
    notifyState(state);

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
    _uploadCapabilityObserver.stop();
    _state.status = BleOtaStatus.pinChange;
    notifyState(state);
    _pinChanger.set(pin: pin);
  }

  void removePin() {
    _uploadCapabilityObserver.stop();
    _state.status = BleOtaStatus.pinChange;
    notifyState(state);
    _pinChanger.remove();
  }

  Future<void> _upload({required Uint8List data, int? size}) async {
    _uploadCapabilityObserver.stop();

    final isSignatureRequired = state.deviceCapabilities.signatureRequired;
    if (isSignatureRequired && !isValidSignedSize(data)) {
      _raiseError(Error.incorrectSignatureSize);
      return;
    }
    final signatureData = isSignatureRequired ? getSignature(data) : null;
    final unsignedData = isSignatureRequired ? removeSignature(data) : data;

    final isCompressionSupported =
        state.deviceCapabilities.compressionSupported;
    final isDataCompressed = size != null && size != unsignedData.length;
    if (isDataCompressed && unsignedData.length > size) {
      _raiseError(Error.incorrectCompressedSize);
      return;
    }
    final canCompress = isCompressionSupportedByPlatform();
    if (!canCompress && !isCompressionSupported && isDataCompressed) {
      _raiseError(Error.compressionNotSupported);
      return;
    }
    final isCompressionRequired =
        canCompress && isCompressionSupported && !isDataCompressed;
    final isDecompressionRequired =
        canCompress && !isCompressionSupported && isDataCompressed;
    final firmwareData = isCompressionRequired
        ? compress(unsignedData)
        : isDecompressionRequired
            ? decompress(unsignedData)
            : unsignedData;
    final decompressedSize = isCompressionRequired
        ? unsignedData.length
        : !isDecompressionRequired && isDataCompressed
            ? size
            : null;

    final isChecksumSupported = state.deviceCapabilities.checksumSupported;
    final firmwareCrc = isChecksumSupported ? calcCrc(firmwareData) : null;

    await _uploader.upload(
      firmwareData: firmwareData,
      signatureData: signatureData,
      firmwareCrc: firmwareCrc,
      decompressedSize: decompressedSize,
    );
  }

  void _onDeviceCapabilitiesStateChanged(
      DeviceCapabilitiesState deviceCapabilitiesState) {
    if (deviceCapabilitiesState.status == WorkStatus.success) {
      state.deviceCapabilities = deviceCapabilitiesState.capabilities;
      _uploadCapabilityObserver.start(
          uploadEnabled: state.deviceCapabilities.uploadEnabled);
      if (!_skipInfoReading) {
        _deviceInfoReader.read();
      } else {
        state.status = BleOtaStatus.initialized;
        notifyState(state);
      }
    } else if (deviceCapabilitiesState.status == WorkStatus.error) {
      _raiseError(
        deviceCapabilitiesState.error,
        errorCode: deviceCapabilitiesState.errorCode,
      );
    }
  }

  void _onDeviceInfoStateChanged(DeviceInfoState deviceInfoState) {
    if (deviceInfoState.status == WorkStatus.success) {
      state.deviceInfo = deviceInfoState.info;
      if (_manufacturesDictUrl != null) {
        _remoteInfoReader.read(state.deviceInfo, _manufacturesDictUrl!);
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

  void _onUploadStateChanged(UploadState uploadState) {
    state.uploadProgress = uploadState.progress;
    if (uploadState.status == UploadStatus.success) {
      state.status = BleOtaStatus.uploaded;
      notifyState(state);
    } else if (uploadState.status == UploadStatus.error) {
      _raiseError(uploadState.error, errorCode: uploadState.errorCode);
    } else {
      notifyState(state);
    }
  }

  void _onPinChangeStateChanged(PinChangeState pinChangeState) {
    if (pinChangeState.status == WorkStatus.success) {
      state.status = BleOtaStatus.pinChanged;
      _uploadCapabilityObserver.start(
          uploadEnabled: state.deviceCapabilities.uploadEnabled);
      notifyState(state);
    } else if (pinChangeState.status == WorkStatus.error) {
      _raiseError(
        pinChangeState.error,
        errorCode: pinChangeState.errorCode,
      );
    }
  }

  void _onUploadCapabilityStateChanged(
      UploadCapabilityState uploadCapabilityState) {
    if (uploadCapabilityState.status != WorkStatus.error) {
      state.deviceCapabilities.uploadEnabled =
          uploadCapabilityState.uploadEnabled;
      notifyState(state);
    } else {
      _raiseError(
        uploadCapabilityState.error,
        errorCode: uploadCapabilityState.errorCode,
      );
    }
  }

  void _raiseError(Error error, {int errorCode = 0}) {
    state.status = BleOtaStatus.error;
    state.error = error;
    state.errorCode = errorCode;
    state.deviceCapabilities.uploadEnabled = false;
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
    required this.deviceCapabilities,
    this.deviceInfo = const DeviceInfo(),
    required this.remoteInfo,
    this.uploadProgress = 0.0,
  });

  DeviceCapabilities deviceCapabilities;
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

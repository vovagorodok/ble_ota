import 'dart:async';
import 'dart:typed_data';

import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/device_capabilities.dart';
import 'package:ble_ota/core/errors_map.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/messages.dart';
import 'package:ble_ota/core/state.dart';

class DeviceCapabilitiesReader
    extends StatefulNotifier<DeviceCapabilitiesState> {
  DeviceCapabilitiesReader({required BleSerial bleSerial})
      : _bleSerial = bleSerial;

  final BleSerial _bleSerial;
  StreamSubscription? _subscription;
  DeviceCapabilitiesState _state =
      DeviceCapabilitiesState(capabilities: DeviceCapabilities());

  @override
  DeviceCapabilitiesState get state => _state;

  void read() {
    _subscription = _bleSerial.dataStream.listen(_handleMessage);

    _state = DeviceCapabilitiesState(
      status: WorkStatus.working,
      capabilities: DeviceCapabilities(),
    );
    notifyState(state);

    _sendInitReq();
  }

  void _handleMessage(Uint8List data) {
    if (!Message.isValidSize(data)) {
      _raiseError(Error.incorrectMessageSize);
      return;
    }

    final message = Message.fromBytes(data);
    final header = message.header;

    switch (header) {
      case HeaderCode.initResp:
        InitResp.isValidSize(data)
            ? _handleInitResp(InitResp.fromBytes(data))
            : _raiseError(Error.incorrectMessageSize);
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

  void _sendInitReq() {
    _sendMessage(InitReq().toBytes());
    _waitMessage();
  }

  void _handleInitResp(InitResp resp) {
    _unsubscribe();

    final flags = resp.flags;
    state.capabilities = DeviceCapabilities(
      compressionSupported: flags.compression,
      checksumSupported: flags.checksum,
      uploadEnabled: flags.upload,
      signatureRequired: flags.signature,
      pinChangeSupported: flags.pin,
    );

    state.status = WorkStatus.success;
    notifyState(state);
  }

  void _sendMessage(Uint8List data) {
    _bleSerial.send(data: data);
  }

  void _waitMessage() {
    _bleSerial.waitData(
        timeoutCallback: () => _raiseError(Error.noDeviceResponse));
  }

  void _raiseError(Error error, {int errorCode = 0}) {
    _unsubscribe();
    state.status = WorkStatus.error;
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

class DeviceCapabilitiesState extends State {
  DeviceCapabilitiesState({
    super.status = WorkStatus.idle,
    super.error = Error.unknown,
    required this.capabilities,
  });

  DeviceCapabilities capabilities;
}

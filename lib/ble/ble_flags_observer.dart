import 'dart:async';
import 'dart:typed_data';

import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/errors_map.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/messages.dart';
import 'package:ble_ota/core/state.dart';

class BleFlagsObserver extends StatefulNotifier<DeviceObserverState> {
  BleFlagsObserver({required BleSerial bleSerial}) : _bleSerial = bleSerial;

  final BleSerial _bleSerial;
  StreamSubscription? _subscription;
  DeviceObserverState _state = DeviceObserverState(uploadEnabled: false);

  @override
  DeviceObserverState get state => _state;

  void start({required bool uploadEnabled}) {
    _subscription = _bleSerial.dataStream.listen(_handleMessage);
    state.uploadEnabled = uploadEnabled;
    state.status = WorkStatus.working;
    notifyState(state);
  }

  void stop() {
    _unsubscribe();
    state.status = WorkStatus.idle;
    notifyState(state);
  }

  void _handleMessage(Uint8List data) {
    if (!Message.isValidSize(data)) {
      _raiseError(Error.incorrectMessageSize);
      return;
    }

    final message = Message.fromBytes(data);
    final header = message.header;

    switch (header) {
      case HeaderCode.uploadEnableInd:
        UploadEnableInd.isValidSize(data)
            ? _handleUploadEnableInd()
            : _raiseError(Error.incorrectMessageSize);
        break;
      case HeaderCode.uploadDisableInd:
        UploadDisableInd.isValidSize(data)
            ? _handleUploadDisableInd()
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

  void _handleUploadEnableInd() {
    state.uploadEnabled = true;
    notifyState(state);
  }

  void _handleUploadDisableInd() {
    state.uploadEnabled = false;
    notifyState(state);
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

class DeviceObserverState extends State {
  DeviceObserverState({
    super.status = WorkStatus.idle,
    super.error = Error.unknown,
    required this.uploadEnabled,
  });

  bool uploadEnabled;
}

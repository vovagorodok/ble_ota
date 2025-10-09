import 'dart:async';
import 'dart:typed_data';

import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/errors_map.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/messages.dart';
import 'package:ble_ota/core/state.dart';

class UploadCapabilityObserver extends StatefulNotifier<UploadCapabilityState> {
  UploadCapabilityObserver({required BleSerial bleSerial})
      : _bleSerial = bleSerial;

  final BleSerial _bleSerial;
  StreamSubscription? _subscription;
  UploadCapabilityState _state = UploadCapabilityState(uploadEnabled: false);

  @override
  UploadCapabilityState get state => _state;

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
    try {
      final header = Message.fromBytes(data).header;

      switch (header) {
        case HeaderCode.uploadEnableInd:
          _handleUploadEnableInd(UploadEnableInd.fromBytes(data));
          break;
        case HeaderCode.uploadDisableInd:
          _handleUploadDisableInd(UploadDisableInd.fromBytes(data));
          break;
        case HeaderCode.errorInd:
          _raiseError(determineErrorCode(ErrorInd.fromBytes(data).code));
          break;
        default:
          _raiseError(
            Error.unexpectedDeviceResponse,
            errorCode: header,
          );
      }
    } on IncorrectMessageSizeException {
      _raiseError(Error.incorrectMessageSize);
    }
  }

  void _handleUploadEnableInd(UploadEnableInd ind) {
    state.uploadEnabled = true;
    notifyState(state);
  }

  void _handleUploadDisableInd(UploadDisableInd ind) {
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

class UploadCapabilityState extends State {
  UploadCapabilityState({
    super.status = WorkStatus.idle,
    super.error = Error.unknown,
    required this.uploadEnabled,
  });

  bool uploadEnabled;
}

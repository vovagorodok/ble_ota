import 'dart:async';
import 'dart:typed_data';

import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/errors_map.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/messages.dart';
import 'package:ble_ota/core/state.dart';

class PinChanger extends StatefulNotifier<PinChangeState> {
  PinChanger({required BleSerial bleSerial}) : _bleSerial = bleSerial;

  final BleSerial _bleSerial;
  StreamSubscription? _subscription;
  PinChangeState _state = PinChangeState();

  @override
  PinChangeState get state => _state;

  void set({required int pin}) {
    _begin();
    _sendMessage(SetPinReq(pin: pin).toBytes());
    _waitMessage();
  }

  void remove() {
    _begin();
    _sendMessage(RemovePinReq().toBytes());
    _waitMessage();
  }

  void _handleMessage(Uint8List data) {
    try {
      final header = Message.fromBytes(data).header;

      switch (header) {
        case HeaderCode.setPinResp:
          _handleResp(SetPinResp.fromBytes(data));
          break;
        case HeaderCode.removePinResp:
          _handleResp(RemovePinResp.fromBytes(data));
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

  void _begin() {
    _subscription = _bleSerial.dataStream.listen(_handleMessage);

    _state = PinChangeState(status: WorkStatus.working);
    notifyState(state);
  }

  void _handleResp(Message resp) {
    if (state.status != WorkStatus.working) {
      _raiseError(
        Error.unexpectedDeviceResponse,
        errorCode: resp.header,
      );
      return;
    }

    _unsubscribe();
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

class PinChangeState extends State {
  PinChangeState({
    super.status = WorkStatus.idle,
    super.error = Error.unknown,
  });
}

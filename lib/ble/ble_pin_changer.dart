import 'dart:async';
import 'dart:typed_data';

import 'package:ble_backend/ble_serial.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/messages.dart';
import 'package:ble_ota/core/state.dart';

class BlePinChanger extends StatefulNotifier<BlePinChangeState> {
  BlePinChanger({required BleSerial bleSerial}) : _bleSerial = bleSerial;

  final BleSerial _bleSerial;
  StreamSubscription? _subscription;
  BlePinChangeState _state = BlePinChangeState();

  @override
  BlePinChangeState get state => _state;

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
    if (!Message.isValidSize(data)) {
      _raiseError(Error.incorrectMessageSize);
      return;
    }

    final message = Message.fromBytes(data);
    final header = message.header;

    if (state.status != WorkStatus.working) {
      _raiseError(
        Error.unexpectedDeviceResponse,
        errorCode: header,
      );
      return;
    }

    if (header == HeaderCode.setPinResp || header == HeaderCode.removePinResp) {
      _unsubscribe();
      state.status = WorkStatus.success;
      notifyState(state);
    } else {
      _raiseError(
        Error.unexpectedDeviceResponse,
        errorCode: header,
      );
    }
  }

  void _begin() {
    _subscription = _bleSerial.dataStream.listen(_handleMessage);

    _state = BlePinChangeState(status: WorkStatus.working);
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

class BlePinChangeState extends State {
  BlePinChangeState({
    super.status = WorkStatus.idle,
    super.error = Error.unknown,
  });
}

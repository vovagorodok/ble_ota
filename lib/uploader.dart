import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:ble_backend/ble_connector.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/ble/ble_uploader.dart';

class Uploader extends StatefulNotifier<UploadState> {
  Uploader({required BleConnector bleConnector, bool sequentialUpload = false})
      : _bleUploader = BleUploader(
            bleConnector: bleConnector, sequentialUpload: sequentialUpload) {
    _bleUploader.stateStream.listen(_onBleUploadStateChanged);
  }

  final BleUploader _bleUploader;
  UploadState _state = UploadState();

  @override
  UploadState get state => _state;

  Future<void> uploadBytes(
      {required Uint8List bytes, required int maxMtu}) async {
    _state = UploadState(status: WorkStatus.working);
    notifyState(state);

    await _bleUploader.upload(data: bytes, maxMtu: maxMtu);
  }

  Future<void> uploadLocalFile(
      {required String localPath, required int maxMtu}) async {
    _state = UploadState(status: WorkStatus.working);
    notifyState(state);

    File file = File(localPath);
    final data = await file.readAsBytes();
    await _bleUploader.upload(data: data, maxMtu: maxMtu);
  }

  Future<void> uploadHttpFile(
      {required String url, required int maxMtu}) async {
    try {
      _state = UploadState(status: WorkStatus.working);
      notifyState(state);

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        _raiseError(
          UploadError.unexpectedNetworkResponse,
          errorCode: response.statusCode,
        );
        return;
      }

      await _bleUploader.upload(data: response.bodyBytes, maxMtu: maxMtu);
    } catch (_) {
      _raiseError(UploadError.generalNetworkError);
    }
  }

  void _raiseError(UploadError error, {int errorCode = 0}) {
    state.status = WorkStatus.error;
    state.error = error;
    state.errorCode = errorCode;
    notifyState(state);
  }

  void _onBleUploadStateChanged(BleUploadState bleUploadState) {
    state.progress = bleUploadState.progress;

    if (bleUploadState.status == BleUploadStatus.success) {
      state.status = WorkStatus.success;
      notifyState(state);
    } else if (bleUploadState.status == BleUploadStatus.error) {
      _raiseError(
        bleUploadState.error,
        errorCode: bleUploadState.errorCode,
      );
    } else {
      notifyState(state);
    }
  }
}

class UploadState extends WorkState<WorkStatus, UploadError> {
  UploadState({
    super.status = WorkStatus.idle,
    super.error = UploadError.unknown,
    this.progress = 0.0,
  });

  double progress;
}

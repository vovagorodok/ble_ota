import 'package:ble_backend/ble_characteristic.dart';
import 'package:ble_backend/ble_connector.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/ble/uuids.dart';
import 'package:ble_ota/core/device_info.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/state.dart';
import 'package:ble_ota/core/version.dart';

class DeviceInfoReader extends StatefulNotifier<DeviceInfoState> {
  DeviceInfoReader({required BleConnector bleConnector})
      : _characteristicManufactureName = bleConnector.createCharacteristic(
            serviceId: serviceUuid,
            characteristicId: characteristicUuidManufactureName),
        _characteristicHardwareName = bleConnector.createCharacteristic(
            serviceId: serviceUuid,
            characteristicId: characteristicUuidHardwareName),
        _characteristicHardwareVersion = bleConnector.createCharacteristic(
            serviceId: serviceUuid,
            characteristicId: characteristicUuidHardwareVersion),
        _characteristicSoftwareName = bleConnector.createCharacteristic(
            serviceId: serviceUuid,
            characteristicId: characteristicUuidSoftwareName),
        _characteristicSoftwareVersion = bleConnector.createCharacteristic(
            serviceId: serviceUuid,
            characteristicId: characteristicUuidSoftwareVersion);

  final BleCharacteristic _characteristicManufactureName;
  final BleCharacteristic _characteristicHardwareName;
  final BleCharacteristic _characteristicHardwareVersion;
  final BleCharacteristic _characteristicSoftwareName;
  final BleCharacteristic _characteristicSoftwareVersion;
  final DeviceInfoState _state = DeviceInfoState();

  @override
  DeviceInfoState get state => _state;

  void read() {
    state.status = WorkStatus.working;
    notifyState(state);

    () async {
      try {
        state.info = DeviceInfo(
          manufactureName:
              String.fromCharCodes(await _characteristicManufactureName.read()),
          hardwareName:
              String.fromCharCodes(await _characteristicHardwareName.read()),
          hardwareVersion:
              Version.fromList(await _characteristicHardwareVersion.read()),
          softwareName:
              String.fromCharCodes(await _characteristicSoftwareName.read()),
          softwareVersion:
              Version.fromList(await _characteristicSoftwareVersion.read()),
          isAvailable: true,
        );
        state.status = WorkStatus.success;
        notifyState(state);
      } catch (_) {
        _raiseError(Error.deviceError);
      }
    }.call();
  }

  void _raiseError(Error error, {int errorCode = 0}) {
    state.status = WorkStatus.error;
    state.error = error;
    state.errorCode = errorCode;
    notifyState(state);
  }
}

class DeviceInfoState extends State {
  DeviceInfoState({
    super.status = WorkStatus.idle,
    super.error = Error.unknown,
    this.info = const DeviceInfo(),
  });

  DeviceInfo info;
}

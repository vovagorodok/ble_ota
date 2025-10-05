import 'package:ble_ota/core/version.dart';
import 'package:meta/meta.dart';

@immutable
class DeviceInfo {
  const DeviceInfo({
    this.manufactureName = "",
    this.hardwareName = "",
    this.hardwareVersion = const Version(),
    this.softwareName = "",
    this.softwareVersion = const Version(),
    this.isAvailable = false,
  });

  final String manufactureName;
  final String hardwareName;
  final Version hardwareVersion;
  final String softwareName;
  final Version softwareVersion;
  final bool isAvailable;
}

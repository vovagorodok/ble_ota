import 'package:ble_ota/core/version.dart';
import 'package:meta/meta.dart';

@immutable
class Software {
  const Software({
    this.name = "",
    this.version = const Version(),
    this.path = "",
    this.icon,
    this.text,
    this.page,
    this.size,
    this.hardwareVersion,
    this.minHardwareVersion,
    this.maxHardwareVersion,
  });

  factory Software.fromDict(dict) => Software(
        name: dict["software_name"],
        version: Version.fromList(dict["software_version"]),
        path: dict["software_path"],
        icon: dict["software_icon"],
        text: dict["software_text"],
        page: dict["software_page"],
        size: dict["software_size"],
        hardwareVersion: _getOptionalVersion(dict, "hardware_version"),
        minHardwareVersion: _getOptionalVersion(dict, "min_hardware_version"),
        maxHardwareVersion: _getOptionalVersion(dict, "max_hardware_version"),
      );

  @override
  String toString() {
    return "$name v$version";
  }

  static _getOptionalVersion(dict, key) =>
      dict.containsKey(key) ? Version.fromList(dict[key]) : null;

  final String name;
  final Version version;
  final String path;
  final String? icon;
  final String? text;
  final String? page;
  final int? size;
  final Version? hardwareVersion;
  final Version? minHardwareVersion;
  final Version? maxHardwareVersion;
}

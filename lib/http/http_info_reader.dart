import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import 'package:ble_backend/state_notifier.dart';
import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/errors.dart';
import 'package:ble_ota/core/device_info.dart';
import 'package:ble_ota/core/remote_info.dart';
import 'package:ble_ota/core/software.dart';

class HttpInfoReader extends StatefulNotifier<RemoteInfoState> {
  RemoteInfoState _state = RemoteInfoState(info: RemoteInfo());

  @override
  RemoteInfoState get state => _state;

  void read(DeviceInfo deviceInfo, String manufacturesDictUrl) {
    _state = RemoteInfoState(
      status: WorkStatus.working,
      info: RemoteInfo(),
    );
    notifyState(state);

    () async {
      try {
        final manufacturesResponse =
            await http.get(Uri.parse(manufacturesDictUrl));
        if (manufacturesResponse.statusCode != 200) {
          _raiseError(
            InfoError.unexpectedNetworkResponse,
            errorCode: manufacturesResponse.statusCode,
          );
          return;
        }
        final manufacturesBody =
            _loadDict(manufacturesDictUrl, manufacturesResponse.body);

        final hardwaresUrl = manufacturesBody[deviceInfo.manufactureName];
        if (hardwaresUrl == null) {
          state.info.isHardwareUnregistered = true;
          state.status = WorkStatus.success;
          notifyState(state);
          return;
        }

        final hardwaresResponse = await http.get(Uri.parse(hardwaresUrl));
        if (hardwaresResponse.statusCode != 200) {
          _raiseError(
            InfoError.unexpectedNetworkResponse,
            errorCode: hardwaresResponse.statusCode,
          );
          return;
        }
        final hardwaresBody = _loadDict(hardwaresUrl, hardwaresResponse.body);

        final hardwareUrl = hardwaresBody[deviceInfo.hardwareName];
        if (hardwareUrl == null) {
          state.info.isHardwareUnregistered = true;
          state.status = WorkStatus.success;
          notifyState(state);
          return;
        }

        await _readSoftwares(deviceInfo, hardwareUrl);
      } catch (_) {
        _raiseError(InfoError.generalNetworkError);
      }
    }.call();
  }

  void _readNewestSoftware(DeviceInfo deviceInfo) {
    final filteredBySoftwareList =
        state.info.softwareList.where((Software software) {
      return software.name == deviceInfo.softwareName;
    }).toList();
    if (filteredBySoftwareList.isEmpty) {
      return;
    }
    final max = filteredBySoftwareList.reduce((Software a, Software b) {
      return a.version >= b.version ? a : b;
    });
    if (max.version <= deviceInfo.softwareVersion) {
      return;
    }
    state.info.newestSoftware = max;
  }

  Future<void> _readSoftwares(DeviceInfo deviceInfo, String hardwareUrl) async {
    try {
      final response = await http.get(Uri.parse(hardwareUrl));
      if (response.statusCode != 200) {
        _raiseError(
          InfoError.unexpectedNetworkResponse,
          errorCode: response.statusCode,
        );
        return;
      }

      final body = _loadDict(hardwareUrl, response.body);
      if (!body.containsKey("hardware_name") ||
          !body.containsKey("softwares")) {
        _raiseError(InfoError.incorrectFileFormat);
        return;
      }
      _state.info.hardwareName = body["hardware_name"];
      if (_state.info.hardwareName != deviceInfo.hardwareName) {
        _raiseError(InfoError.incorrectFileFormat);
        return;
      }
      _state.info.hardwareIcon = body["hardware_icon"];
      _state.info.hardwareText = body["hardware_text"];
      _state.info.hardwarePage = body["hardware_page"];

      final softwares = body["softwares"];
      final fullList = softwares.map<Software>(Software.fromDict).toList();
      final filteredByHardwareList = fullList.where((Software software) {
        return (software.hardwareVersion != null
                ? software.hardwareVersion == deviceInfo.hardwareVersion
                : true) &&
            (software.minHardwareVersion != null
                ? software.minHardwareVersion! <= deviceInfo.hardwareVersion
                : true) &&
            (software.maxHardwareVersion != null
                ? software.maxHardwareVersion! >= deviceInfo.hardwareVersion
                : true);
      }).toList();
      state.info.softwareList = filteredByHardwareList;

      _readNewestSoftware(deviceInfo);
      state.status = WorkStatus.success;
      notifyState(state);
    } catch (_) {
      _raiseError(InfoError.generalNetworkError);
    }
  }

  dynamic _loadDict(String name, String body) =>
      name.endsWith('.yaml') || name.endsWith('.yml')
          ? loadYaml(body)
          : jsonDecode(body);

  void _raiseError(InfoError error, {int errorCode = 0}) {
    state.status = WorkStatus.error;
    state.error = error;
    state.errorCode = errorCode;
    notifyState(state);
  }
}

class RemoteInfoState extends WorkState<WorkStatus, InfoError> {
  RemoteInfoState({
    super.status = WorkStatus.idle,
    super.error = InfoError.unknown,
    required this.info,
  });

  RemoteInfo info;
}

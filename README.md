# BLE OTA

Upload firmware over bluetooth

## Usage
Full example at: https://github.com/vovagorodok/ble_ota_app

Scan configuration:
```dart
import 'package:ble_ota/ble/ble_uuids.dart';

final bleScanner = bleCentral.createScanner(serviceIds: [serviceUuid]);
```

Init:
```dart
bleOta = BleOta(bleConnector: bleConnector);
bleOta.stateStream.listen((state) => print("State changed: ${state.status}"));
bleOta.init();
```

Upload local binary:
```dart
bleOta.uploadLocalFile(localPath: localPath);
```

Upload remote binary:
```dart
print("Hardware name: ${bleOta.state.deviceInfo.hardwareName}");
if (bleOta.state.remoteInfo.newestSoftware != null)
  bleOta.uploadHttpFile(url: bleOta.state.remoteInfo.newestSoftware.path!);
```
# BLE OTA

Upload firmware over bluetooth

## Usage
Full example at: https://github.com/vovagorodok/ble_ota_app

Read info:
```dart
infoReader = InfoReader(bleConnector: bleConnector);
infoReader.stateStream.listen((state) => print("Read state changed: ${state.status}"));
infoReader.read(manufacturesDictUrl: manufacturesDictUrl);
```

Upload local binary:
```dart
uploader = Uploader(bleConnector: bleConnector);
uploader.stateStream.listen((state) => print("Upload state changed: ${state.status}"));
uploader.uploadLocalFile(localPath: localPath, maxMtu: maxMtu);
```

Upload remote binary:
```dart
print("Hardware name: ${infoReader.state.deviceInfo.hardwareName}");
if (infoReader.state.remoteInfo.newestSoftware != null)
  uploader.uploadHttpFile(url: infoReader.state.remoteInfo.newestSoftware.path!, maxMtu: maxMtu);
```
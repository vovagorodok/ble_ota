class DeviceFlags {
  DeviceFlags({
    this.compressionSupported = false,
    this.checksumSupported = false,
    this.uploadEnabled = false,
    this.signatureRequired = false,
    this.pinChangeSupported = false,
  });

  bool compressionSupported;
  bool checksumSupported;
  bool uploadEnabled;
  bool signatureRequired;
  bool pinChangeSupported;
}

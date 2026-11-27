import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.bergercookie.tefteri/device');

/// The IANA name of the time zone of this device, or null.
Future<String?> readDeviceTimezone() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _channel.invokeMethod<String>('timezone');
    }
    return _fromSystem();
  } on Object {
    // Not running on a device (a test), or the system does not say: leave the zone as it is.
    return null;
  }
}

/// Linux and macOS: the TZ variable, `/etc/timezone`, or the target of `/etc/localtime`.
String? _fromSystem() {
  final env = Platform.environment['TZ'];
  if (env != null && env.contains('/')) {
    return env.replaceFirst(RegExp('^:'), '');
  }
  final file = File('/etc/timezone');
  if (file.existsSync()) {
    final name = file.readAsStringSync().trim();
    if (name.isNotEmpty) return name;
  }
  final link = Link('/etc/localtime');
  if (link.existsSync()) {
    final target = link.targetSync();
    final at = target.indexOf('zoneinfo/');
    if (at >= 0) return target.substring(at + 'zoneinfo/'.length);
  }
  return null;
}

/// The time zone of the device, so that the server can use the same one.
///
/// A day starts and a review reminder comes in the time zone that is saved for the user. The
/// app sends the zone of the device, so that the user never has to set it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_timezone_stub.dart'
    if (dart.library.js_interop) 'device_timezone_web.dart';

/// Reads the IANA name of the device's time zone (`Europe/Athens`), or null when the system
/// does not tell it. A test replaces this.
final deviceTimezoneProvider =
    Provider<Future<String?> Function()>((ref) => readDeviceTimezone);

import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
external _DateTimeFormat _dateTimeFormat();

extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external _Options resolvedOptions();
}

extension type _Options._(JSObject _) implements JSObject {
  external String? get timeZone;
}

/// The IANA name of the time zone of the browser, or null.
Future<String?> readDeviceTimezone() async {
  try {
    return _dateTimeFormat().resolvedOptions().timeZone;
  } on Object {
    return null;
  }
}

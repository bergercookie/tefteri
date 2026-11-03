/// Opens web pages outside the app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL in a new browser tab (or the system browser); tests override
/// it. Returns false when nothing could open the URL.
final openUrlProvider = Provider<Future<bool> Function(Uri)>(
    (_) => (uri) => launchUrl(uri, webOnlyWindowName: '_blank'));

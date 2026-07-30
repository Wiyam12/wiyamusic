import 'dart:io';

/// Lightweight reachability check without an extra package.
///
/// Uses DNS lookup with a short timeout. A positive result means the device
/// likely has internet; a failure means we should stick to offline playback.
Future<bool> hasInternetAccess({
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    final result = await InternetAddress.lookup(
      'dns.google',
    ).timeout(timeout);
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  } on Exception {
    return false;
  }
}

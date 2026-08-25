import 'package:geolocator/geolocator.dart';

/// Coarse location, used only to sort hospitals by distance. Always optional:
/// every caller must work when this returns null (permission denied, no GPS,
/// emulator with no fix). Nothing here blocks registration.
Future<({double lat, double lng})?> currentLatLng() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low, // a city block is precise enough
        timeLimit: Duration(seconds: 12),
      ),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  } catch (_) {
    return null;
  }
}

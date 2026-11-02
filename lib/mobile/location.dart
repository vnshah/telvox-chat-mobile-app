import 'package:geolocator/geolocator.dart';

import 'api.dart';

/// The phone's current position, for sending "my location" as a map pin.
/// A seam so tests need no GPS.
abstract class LocationSource {
  Future<({double latitude, double longitude})> current();
}

class DeviceLocationSource implements LocationSource {
  @override
  Future<({double latitude, double longitude})> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiFailure('Turn on location on this phone to share it.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const ApiFailure('Allow location access to share your location.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ApiFailure(
        'Location access is off for Telvox Chat. Turn it on in the phone’s Settings.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return (latitude: position.latitude, longitude: position.longitude);
  }
}

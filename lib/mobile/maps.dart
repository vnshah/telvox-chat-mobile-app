import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'location.dart';
import 'message_content.dart' show readableText;

/// Google Maps draws only when the build carries a Maps key
/// (`--dart-define=GOOGLE_MAPS=true`, set when android/maps.properties
/// exists). Without one, locations show as a card with "Open in Google
/// Maps", and the picker works from search and this phone's position.
const mapsEnabled = bool.fromEnvironment('GOOGLE_MAPS');

/// Google's own link for a point: opens the Maps app, or maps.google.com.
Uri mapsLink(Object? latitude, Object? longitude) => Uri.https(
  'www.google.com',
  '/maps/search/',
  {'api': '1', 'query': '$latitude,$longitude'},
);

Future<void> openInMaps(Object? latitude, Object? longitude) => launchUrl(
  mapsLink(latitude, longitude),
  mode: LaunchMode.externalApplication,
);

/// "23.02250, 72.57140": five places is about a metre.
String coordinates(num latitude, num longitude) =>
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

/// A place found by search or under the pin.
typedef Place = ({
  double latitude,
  double longitude,
  String? name,
  String? address,
});

/// Names a point and finds places by name. A seam so tests need no geocoder.
abstract class PlaceLookup {
  Future<Place?> at(double latitude, double longitude);
  Future<List<Place>> search(String query);
}

/// The phone's own geocoder (Google's on Android, Apple's on iOS): no key.
class DevicePlaceLookup implements PlaceLookup {
  final _geocoder = geo.Geocoding();

  static String? _address(geo.Placemark p) {
    final parts = <String>[];
    for (final part in [
      p.street,
      p.subLocality,
      p.locality,
      p.administrativeArea,
      p.postalCode,
      p.country,
    ]) {
      final text = part?.trim() ?? '';
      if (text.isNotEmpty && !parts.contains(text)) parts.add(text);
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  Future<Place?> at(double latitude, double longitude) async {
    try {
      final marks = await _geocoder.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (marks.isEmpty) return null;
      return (
        latitude: latitude,
        longitude: longitude,
        name: null,
        address: _address(marks.first),
      );
    } catch (_) {
      // No network or no geocoder: the pin still sends without an address.
      return null;
    }
  }

  @override
  Future<List<Place>> search(String query) async {
    final found = await _geocoder.locationFromAddress(query);
    return [
      for (final l in found.take(5))
        (
          latitude: l.latitude,
          longitude: l.longitude,
          name: query.trim(),
          address: (await at(l.latitude, l.longitude))?.address,
        ),
    ];
  }
}

PlaceLookup placeLookup = DevicePlaceLookup();

/// Where location bubbles get their map picture: the server's Google Static
/// Maps proxy (GET inbox/static-map), drawn with a key that never ships in
/// the app. Set by the chat; null in tests and before sign-in.
class StaticMapSource {
  StaticMapSource(this.api);
  final MobileApi api;

  /// The server answered that it has no maps: stop asking this run.
  static bool unavailable = false;

  Uri url(double latitude, double longitude, int width, int height) =>
      Uri.parse(api.dio.options.baseUrl)
          .resolve('inbox/static-map')
          .replace(
            queryParameters: {
              'lat': latitude.toStringAsFixed(5),
              'lng': longitude.toStringAsFixed(5),
              'w': '$width',
              'h': '$height',
            },
          );

  Map<String, String> get headers => {
    if (api.token != null) 'Authorization': 'Bearer ${api.token}',
    if (api.wabaId != null) 'X-Waba-User-Id': '${api.wabaId}',
  };
}

StaticMapSource? staticMaps;

/// A location's map picture with its pin, as WhatsApp shows one: Google's
/// still map from the server, or a live lite-mode map when the app has its
/// own Maps key; a drawn stand-in while it loads or when neither is set up.
class LocationPreview extends StatelessWidget {
  const LocationPreview(
    this.latitude,
    this.longitude, {
    super.key,
    this.height = 140,
    this.width = 254,
  });
  final double latitude, longitude;
  final double height, width;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    // Lite mode is a still image, light enough for a chat list; iOS has no
    // lite mode.
    final live = mapsEnabled && !kIsWeb && Platform.isAndroid;
    final source = staticMaps;
    final Widget map;
    if (live) {
      map = IgnorePointer(
        child: GoogleMap(
          liteModeEnabled: true,
          initialCameraPosition: CameraPosition(target: point, zoom: 15),
          markers: {Marker(markerId: const MarkerId('pin'), position: point)},
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
        ),
      );
    } else if (source != null &&
        !StaticMapSource.unavailable &&
        height.isFinite) {
      map = Image.network(
        source
            .url(latitude, longitude, width.round(), height.round())
            .toString(),
        headers: source.headers,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        semanticLabel: 'Map',
        frameBuilder: (context, child, frame, sync) =>
            frame == null && !sync ? const _DrawnMap() : child,
        errorBuilder: (_, error, _) {
          // A server without maps answers 404 once; the rest draw at once.
          if ('$error'.contains('404')) StaticMapSource.unavailable = true;
          return const _DrawnMap();
        },
      );
    } else {
      map = const _DrawnMap();
    }
    return SizedBox(height: height, width: double.infinity, child: map);
  }
}

/// Streets and blocks in the brand's warm greys, with the pin in the middle.
class _DrawnMap extends StatelessWidget {
  const _DrawnMap();
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _StreetsPainter(),
    child: const Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 18),
        child: Icon(Icons.location_on, size: 40, color: T.danger),
      ),
    ),
  );
}

class _StreetsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEDE9E1),
    );
    final block = Paint()..color = const Color(0xFFE3DED3);
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 7;
    final lane = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    for (var x = 18.0; x < size.width; x += 64) {
      for (var y = 14.0; y < size.height; y += 52) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 44, 32),
            const Radius.circular(3),
          ),
          block,
        );
      }
    }
    canvas.drawLine(
      Offset(0, size.height * .62),
      Offset(size.width, size.height * .38),
      road,
    );
    canvas.drawLine(
      Offset(size.width * .3, 0),
      Offset(size.width * .42, size.height),
      lane,
    );
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .25),
      14,
      Paint()..color = const Color(0xFFD5E8D6),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Picks a point to send: the map centred on this phone (drag it under the
/// pin), or a place found by search. Returns the `location` the inbox's
/// send endpoint takes, or null when closed.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({
    super.key,
    required this.source,
    required this.lookup,
  });
  final LocationSource source;
  final PlaceLookup lookup;
  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final query = TextEditingController();
  final name = TextEditingController();
  final address = TextEditingController();
  GoogleMapController? map;
  ({double latitude, double longitude})? point;
  List<Place>? results;
  bool locating = true, searching = false, naming = false;
  String? error;

  /// Typed by hand: a moved pin no longer replaces it.
  bool typedAddress = false;
  int lookups = 0;
  Timer? settle;

  @override
  void initState() {
    super.initState();
    here();
  }

  @override
  void dispose() {
    settle?.cancel();
    query.dispose();
    name.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> here() async {
    setState(() {
      locating = true;
      error = null;
    });
    try {
      final p = await widget.source.current();
      if (!mounted) return;
      name.clear();
      typedAddress = false;
      move(p.latitude, p.longitude);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  /// Puts the pin on a point and names it, unless the address was typed.
  void move(double latitude, double longitude, {bool camera = true}) {
    setState(() => point = (latitude: latitude, longitude: longitude));
    if (camera) {
      map?.animateCamera(CameraUpdate.newLatLng(LatLng(latitude, longitude)));
    }
    if (typedAddress) return;
    final ticket = ++lookups;
    setState(() => naming = true);
    widget.lookup.at(latitude, longitude).then((place) {
      if (!mounted || ticket != lookups) return;
      setState(() {
        naming = false;
        address.text = place?.address ?? '';
      });
    });
  }

  Future<void> search() async {
    final text = query.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      searching = true;
      results = null;
    });
    try {
      final found = await widget.lookup.search(text);
      if (mounted) setState(() => results = found);
    } catch (_) {
      if (mounted) setState(() => results = const []);
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void choose(Place place) {
    lookups++;
    setState(() {
      results = null;
      naming = false;
      name.text = place.name ?? '';
      address.text = place.address ?? '';
      typedAddress = place.address != null;
    });
    move(place.latitude, place.longitude);
  }

  void send() {
    final p = point;
    if (p == null) return;
    Navigator.pop(context, <String, dynamic>{
      'latitude': '${p.latitude}',
      'longitude': '${p.longitude}',
      if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
      if (address.text.trim().isNotEmpty) 'address': address.text.trim(),
    });
  }

  Widget mapArea() {
    final p = point;
    if (p == null) {
      return ColoredBox(
        color: const Color(0xFFEDE9E1),
        child: Center(
          child: locating
              ? const CircularProgressIndicator.adaptive()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error ?? 'Search for a place to share.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: T.muted),
                  ),
                ),
        ),
      );
    }
    if (!mapsEnabled) {
      return LocationPreview(p.latitude, p.longitude, height: double.infinity);
    }
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(p.latitude, p.longitude),
            zoom: 16,
          ),
          onMapCreated: (c) => map = c,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onCameraMove: (c) {
            // The point under the pin, named once the map stops.
            settle?.cancel();
            settle = Timer(const Duration(milliseconds: 450), () {
              if (mounted) {
                move(c.target.latitude, c.target.longitude, camera: false);
              }
            });
          },
        ),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_on, size: 44, color: T.danger),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = point;
    return Scaffold(
      appBar: platformAppBar(context, title: const Text('Send location')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: AppTextFormField(
              controller: query,
              bordered: true,
              decoration: InputDecoration(
                hintText: 'Search for a place or address',
                prefixIcon: const Icon(Icons.search, color: T.muted),
                suffixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : null,
              ),
              onSubmitted: (_) => search(),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: mapArea()),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'My location',
                    backgroundColor: T.surface,
                    foregroundColor: T.ink,
                    shape: const CircleBorder(),
                    onPressed: locating ? null : here,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                if (results != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 0,
                    child: Material(
                      color: T.surface,
                      elevation: 3,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: results!.isEmpty
                          ? const ListTile(
                              leading: Icon(Icons.search_off, color: T.muted),
                              title: Text('No places found'),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final (i, r) in results!.indexed)
                                  ListTile(
                                    key: ValueKey('place-$i'),
                                    leading: const Icon(
                                      Icons.location_on_outlined,
                                      color: T.brass,
                                    ),
                                    title: Text(r.name ?? 'Place'),
                                    subtitle: Text(
                                      r.address ??
                                          coordinates(r.latitude, r.longitude),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => choose(r),
                                  ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: T.surface,
              border: Border(top: BorderSide(color: T.hairline)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextFormField(
                      controller: name,
                      bordered: true,
                      decoration: const InputDecoration(
                        hintText: 'Name (optional), e.g. Head office',
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppTextFormField(
                      controller: address,
                      bordered: true,
                      minLines: 1,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: naming
                            ? 'Finding the address…'
                            : 'Address (optional)',
                      ),
                      onChanged: (_) => typedAddress = true,
                    ),
                    if (p != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 2),
                        child: Text(
                          coordinates(p.latitude, p.longitude),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: T.muted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    AppButton.filledIcon(
                      key: const ValueKey('send-location'),
                      onPressed: p == null ? null : send,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Send this location'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The location a message carries, read from its stored payload.
({double latitude, double longitude, String name, String address})? locationOf(
  Json location,
) {
  final lat = double.tryParse('${location['latitude']}');
  final lng = double.tryParse('${location['longitude']}');
  if (lat == null || lng == null) return null;
  return (
    latitude: lat,
    longitude: lng,
    name: readableText(location['name']),
    address: readableText(location['address']),
  );
}

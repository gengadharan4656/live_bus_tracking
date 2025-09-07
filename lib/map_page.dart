import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'location_helper.dart';

class MapPage extends StatefulWidget {
  final String? selectedBusNumber;
  const MapPage({super.key, this.selectedBusNumber});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  Map<String, LatLng> _nearbyBuses = {};
  String? _trackedBusNumber;
  StreamSubscription<Map<String, LatLng>>? _busSub;
  final Distance _distance = Distance();

  static const double defaultZoom = 15.0;

  @override
  void initState() {
    super.initState();
    _initLocations();
  }

  @override
  void dispose() {
    _busSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocations() async {
    await _getUserLocation();

    if (_userLocation != null) {
      _busSub = LocationHelper.getNearbyBusesStream(
        userLat: _userLocation!.latitude,
        userLon: _userLocation!.longitude,
        interval: 5,
      ).listen((buses) {
        setState(() {
          _nearbyBuses = buses;

          // Track selected bus if exists
          if (widget.selectedBusNumber != null &&
              _nearbyBuses.containsKey(widget.selectedBusNumber)) {
            _trackedBusNumber = widget.selectedBusNumber;
          } else if (_nearbyBuses.isNotEmpty &&
              (_trackedBusNumber == null ||
                  !_nearbyBuses.containsKey(_trackedBusNumber))) {
            _trackedBusNumber = _nearbyBuses.keys.first;
          }

          // Sort buses by distance
          _nearbyBuses = Map.fromEntries(
            _nearbyBuses.entries.toList()
              ..sort((a, b) {
                double d1 = _distance.as(
                    LengthUnit.Kilometer, _userLocation!, a.value);
                double d2 = _distance.as(
                    LengthUnit.Kilometer, _userLocation!, b.value);
                return d1.compareTo(d2);
              }),
          );

          // Center map on tracked bus or user
          LatLng center = _trackedBusNumber != null
              ? _nearbyBuses[_trackedBusNumber!]!
              : _userLocation!;
          _mapController.move(center, defaultZoom);
        });
      });
    }
  }

  Future<void> _getUserLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    Position pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    setState(() {
      _userLocation = LatLng(pos.latitude, pos.longitude);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_userLocation != null) {
        _mapController.move(_userLocation!, defaultZoom);
      }
    });
  }

  double? getDistanceToTrackedBus() {
    if (_userLocation != null && _trackedBusNumber != null) {
      LatLng? busLoc = _nearbyBuses[_trackedBusNumber!];
      if (busLoc != null) {
        return _distance.as(LengthUnit.Kilometer, _userLocation!, busLoc);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    double? distanceKm = getDistanceToTrackedBus();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Nearby Buses"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_trackedBusNumber != null && distanceKm != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "🚌 Bus $_trackedBusNumber is ${distanceKm.toStringAsFixed(2)} km away",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _userLocation ?? LatLng(11.0168, 76.9558),
                initialZoom: defaultZoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
                MarkerLayer(
                  markers: [
                    // User marker
                    if (_userLocation != null)
                      Marker(
                        point: _userLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 35,
                        ),
                      ),
                    // Bus markers
                    ..._nearbyBuses.entries.map(
                          (entry) => Marker(
                        point: entry.value,
                        width: 55,
                        height: 55,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _trackedBusNumber = entry.key;
                              _mapController.move(entry.value, defaultZoom);
                            });
                          },
                          child: Column(
                            children: [
                              Image.asset(
                                "assets/icons/bus_icon.png", // updated asset
                                width: entry.key == _trackedBusNumber ? 45 : 35,
                                height: entry.key == _trackedBusNumber ? 45 : 35,
                              ),
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getUserLocation,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }
}

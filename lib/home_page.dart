import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'location_helper.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  Map<String, LatLng> _buses = {};
  StreamSubscription<Map<String, LatLng>>? _busSub;
  final TextEditingController _searchController = TextEditingController();
  final Distance _distance = Distance();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initLocationAndStream();
  }

  @override
  void dispose() {
    _busSub?.cancel();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _initLocationAndStream() async {
    await _getCurrentLocation();
    if (_currentLocation != null) {
      _busSub = LocationHelper.getNearbyBusesStream(
        userLat: _currentLocation!.latitude,
        userLon: _currentLocation!.longitude,
        interval: 5,
      ).listen((buses) {
        setState(() => _buses = buses);
      });
    }
  }

  Future<void> _getCurrentLocation({bool recenter = false}) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });

    if (recenter && _currentLocation != null) {
      _mapController.move(_currentLocation!, 15);
    }
  }

  /// Filter buses and sort by nearest distance
  List<MapEntry<String, LatLng>> _getSortedBuses(String query) {
    List<MapEntry<String, LatLng>> list = _buses.entries.toList();

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((entry) => entry.key.toLowerCase().contains(q)).toList();
    }

    if (_currentLocation != null) {
      list.sort((a, b) {
        double d1 = _distance.as(LengthUnit.Kilometer, _currentLocation!, a.value);
        double d2 = _distance.as(LengthUnit.Kilometer, _currentLocation!, b.value);
        return d1.compareTo(d2);
      });
    }
    return list;
  }

  void _selectBus(String busNo, LatLng location) {
    _mapController.move(location, 15);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Centered on bus $busNo"),
        backgroundColor: Colors.lightBlue.shade600,
      ),
    );
  }

  void _showSearchBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void _onSearchChanged(String _) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                setModalState(() {});
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (_, scrollController) {
                String query = _searchController.text;
                List<MapEntry<String, LatLng>> filtered = _getSortedBuses(query);

                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF8E7),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: "Search bus by number",
                            prefixIcon: const Icon(Icons.search, color: Colors.black),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                          child: Text("No buses found",
                              style: TextStyle(color: Colors.black)),
                        )
                            : ListView.builder(
                          controller: scrollController,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            var entry = filtered[index];
                            double distanceKm = _currentLocation != null
                                ? _distance.as(LengthUnit.Kilometer, _currentLocation!, entry.value)
                                : 0.0;
                            return ListTile(
                              leading: Image.asset(
                                "assets/icons/bus_icon.png",
                                width: 28,
                                height: 28,
                              ),
                              title: Text("Bus ${entry.key}",
                                  style: const TextStyle(color: Colors.black)),
                              subtitle: Text(
                                "${distanceKm.toStringAsFixed(2)} km away",
                                style: const TextStyle(color: Colors.black87),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _selectBus(entry.key, entry.value);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E7),
      appBar: AppBar(
        backgroundColor: Colors.lightBlue.shade600,
        title: const Text("Live Bus Tracker", style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: _showSearchBottomSheet,
          ),
        ],
      ),
      body: _currentLocation == null
          ? const Center(child: CircularProgressIndicator(color: Colors.lightBlue))
          : Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation!,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              ),
              MarkerLayer(
                markers: [
                  // User location
                  Marker(
                    point: _currentLocation!,
                    width: 50,
                    height: 50,
                    child: Image.asset(
                      "assets/icons/user_pin.png",
                      width: 40,
                      height: 40,
                    ),
                  ),
                  // Bus markers
                  ..._buses.entries.map(
                        (entry) => Marker(
                      point: entry.value,
                      width: 40,
                      height: 40,
                      child: Image.asset(
                        "assets/icons/bus_icon.png",
                        width: 30,
                        height: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Bottom draggable nearby buses
          DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.25,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              var sortedBuses = _buses.entries.toList();

              // Sort buses by distance
              if (_currentLocation != null) {
                sortedBuses.sort((a, b) {
                  double d1 = _distance.as(
                      LengthUnit.Kilometer, _currentLocation!, a.value);
                  double d2 = _distance.as(
                      LengthUnit.Kilometer, _currentLocation!, b.value);
                  return d1.compareTo(d2);
                });
              }

              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Column(
                  children: [
                    // ===== Draggable blue handle =====
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 60,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.lightBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    // ===== Title =====
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        "Nearby Buses",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                      ),
                    ),

                    // ===== Bus list =====
                    Expanded(
                      child: sortedBuses.isEmpty
                          ? const Center(
                        child: Text("No buses available",
                            style: TextStyle(color: Colors.black54)),
                      )
                          : ListView.builder(
                        controller: scrollController,
                        itemCount: sortedBuses.length,
                        itemBuilder: (context, index) {
                          var entry = sortedBuses[index];
                          double distanceKm = _currentLocation != null
                              ? _distance.as(LengthUnit.Kilometer,
                              _currentLocation!, entry.value)
                              : 0.0;
                          return ListTile(
                            leading: Image.asset(
                              "assets/icons/bus_icon.png",
                              width: 28,
                              height: 28,
                            ),
                            title: Text("Bus ${entry.key}",
                                style: const TextStyle(color: Colors.black)),
                            subtitle: Text(
                              "${distanceKm.toStringAsFixed(2)} km away",
                              style: const TextStyle(color: Colors.black87),
                            ),
                            onTap: () => _selectBus(entry.key, entry.value),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          )


        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.lightBlue,
        onPressed: () => _getCurrentLocation(recenter: true),
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class LocationHelper {
  static final Distance _distance = Distance();

  /// 🔗 Your backend URL (update if needed)
  static const String baseUrl = "https://location-bus-tracking.onrender.com";

  /// 📡 Fetch nearby buses from backend
  static Future<Map<String, LatLng>> fetchNearbyBuses({
    required double userLat,
    required double userLon,
    int limit = 10,
    double radiusMeters = 2000, // default 2km radius
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/get_nearby_buses"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "latitude": userLat,
          "longitude": userLon,
          "radius_m": radiusMeters,
          "limit": limit,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is List) {
          Map<String, LatLng> buses = {};
          for (var b in data) {
            final busNo = b["bus_no"]?.toString() ??
                b["busNumber"]?.toString() ??
                b["bus_id"]?.toString() ??
                "unknown";

            if (b["latitude"] != null && b["longitude"] != null) {
              buses[busNo] = LatLng(
                (b["latitude"] as num).toDouble(),
                (b["longitude"] as num).toDouble(),
              );
            }
          }
          return buses;
        } else {
          print("⚠️ Unexpected response format: $data");
          return {};
        }
      } else {
        print("❌ Backend error: ${response.statusCode} → ${response.body}");
        return {};
      }
    } catch (e) {
      print("❌ Error fetching buses: $e");
      return {};
    }
  }

  /// 🔄 Live stream for nearby buses
  static Stream<Map<String, LatLng>> getNearbyBusesStream({
    required double userLat,
    required double userLon,
    int interval = 5, // refresh every 5 sec
    int limit = 10,
    double radiusMeters = 2000,
  }) async* {
    while (true) {
      final buses = await fetchNearbyBuses(
        userLat: userLat,
        userLon: userLon,
        limit: limit,
        radiusMeters: radiusMeters,
      );
      yield buses;
      await Future.delayed(Duration(seconds: interval));
    }
  }

  /// 🔄 Live stream for a single bus
  static Stream<LatLng?> getBusLocationStream({
    required String busNumber,
    required double userLat,
    required double userLon,
    int interval = 5,
    double radiusMeters = 5000,
  }) async* {
    while (true) {
      final buses = await fetchNearbyBuses(
        userLat: userLat,
        userLon: userLon,
        limit: 50,
        radiusMeters: radiusMeters,
      );
      yield buses[busNumber]; // ✅ null if not found
      await Future.delayed(Duration(seconds: interval));
    }
  }

  /// 📏 Distance in KM
  static double distanceKm(LatLng a, LatLng b) {
    return _distance.as(LengthUnit.Kilometer, a, b);
  }
}

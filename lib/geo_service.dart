import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class GeoService {
  static Future<bool> requestLocationPermission(BuildContext context) async {
    PermissionStatus status = await Permission.locationWhenInUse.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (context.mounted) _showSettingsDialog(context);
      return false;
    }

    PermissionStatus result = await Permission.locationWhenInUse.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied && context.mounted) _showSettingsDialog(context);

    return false;
  }

  static Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
    } catch (e) {
      debugPrint("Erreur GPS: $e");
      return null;
    }
  }

  static double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2));

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return double.parse((earthRadiusKm * c).toStringAsFixed(1));
  }

  static double _toRadians(double degree) => degree * (math.pi / 180.0);

  static void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Localisation bloquée", style: TextStyle(color: Colors.white)),
        content: const Text(
          "L'accès à la localisation est désactivé dans les paramètres de ton téléphone.\n\n"
          "Pour activer le Tarot Social, autorise la localisation dans les réglages.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text("Paramètres", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

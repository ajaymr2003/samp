//lib/models/navigation_request_model.dart ---

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class NavigationRequest {
  final LatLng start;
  final LatLng end;
  final bool isNavigating;
  final String? destinationStationId;
  final bool stationIsFull; 
  final String? cancellationReason; 
  final String? cancelledStationName; 
  final bool isCharging; // --- NEW ---
  final bool chargingComplete; // --- NEW ---

  NavigationRequest({
    required this.start,
    required this.end,
    required this.isNavigating,
    this.destinationStationId,
    this.stationIsFull = false, 
    this.cancellationReason, 
    this.cancelledStationName, 
    this.isCharging = false, // --- NEW ---
    this.chargingComplete = false, // --- NEW ---
  });

  factory NavigationRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return NavigationRequest(
      start: LatLng(
        (data['start_lat'] ?? 0.0).toDouble(),
        (data['start_lng'] ?? 0.0).toDouble(),
      ),
      end: LatLng(
        (data['end_lat'] ?? 0.0).toDouble(),
        (data['end_lng'] ?? 0.0).toDouble(),
      ),
      isNavigating: data['isNavigating'] ?? false,
      destinationStationId: data['destinationStationId'],
      stationIsFull: data['stationIsFull'] ?? false, 
      cancellationReason: data['cancellationReason'], 
      cancelledStationName: data['cancelledStationName'], 
      isCharging: data['isCharging'] ?? false, // --- NEW ---
      chargingComplete: data['chargingComplete'] ?? false, // --- NEW ---
    );
  }
}
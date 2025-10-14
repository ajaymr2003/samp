//lib/models/navigation_request_model.dart ---

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class NavigationRequest {
  final LatLng start;
  final LatLng end;
  final bool isNavigating;
  final String? destinationStationId;
  final bool stationIsFull; // --- MODIFIED: New field ---
  final String? cancellationReason; // --- MODIFIED: New field ---
  final String? cancelledStationName; // --- MODIFIED: New field ---

  NavigationRequest({
    required this.start,
    required this.end,
    required this.isNavigating,
    this.destinationStationId,
    this.stationIsFull = false, // --- MODIFIED: Added to constructor ---
    this.cancellationReason, // --- MODIFIED: Added to constructor ---
    this.cancelledStationName, // --- MODIFIED: Added to constructor ---
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
      stationIsFull: data['stationIsFull'] ?? false, // --- MODIFIED: Parse from Firestore ---
      cancellationReason: data['cancellationReason'], // --- MODIFIED: Parse from Firestore ---
      cancelledStationName: data['cancelledStationName'], // --- MODIFIED: Parse from Firestore ---
    );
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class NavigationRequest {
  final LatLng start;
  final LatLng end;
  final bool isNavigating;

  NavigationRequest({
    required this.start,
    required this.end,
    required this.isNavigating,
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
    );
  }
}
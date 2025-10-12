import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/station_model.dart';
import '../models/vehicle_model.dart';

class FirebaseService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _encodeEmail(String email) {
    return email.replaceAll('.', ',');
  }
  
  Future<List<String>> getUsers() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      if (snapshot.docs.isEmpty) return ['default_simulator_user'];
      return snapshot.docs.map((doc) => doc.data()['email'] as String).toList();
    } catch (e) {
      print("Error fetching users: $e");
      return ['default_simulator_user'];
    }
  }
  
  // --- CORRECTED VEHICLE METHODS ---

  Stream<Vehicle> getVehicleStream({required String email}) {
    final encodedEmail = _encodeEmail(email);
    final vehicleRef = _database.ref('vehicles/$encodedEmail');
    
    return vehicleRef.onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        return Vehicle.fromJson(data);
      } else {
        // If no data exists, return the default initial state.
        return Vehicle.initial();
      }
    });
  }
  
  Future<void> updateVehicleState({required String email, required Vehicle vehicle}) async {
    final encodedEmail = _encodeEmail(email);
    final vehicleRef = _database.ref('vehicles/$encodedEmail');
    try {
      await vehicleRef.set(vehicle.toJson());
    } catch (e) {
      print("Error writing vehicle state to Firebase: $e");
    }
  }

  // --- STATION DATA METHODS ---

  Future<List<Station>> getStations() async {
    try {
      final snapshot = await _firestore.collection('stations').orderBy('name').get();
      if (snapshot.docs.isEmpty) return [];
      return snapshot.docs.map((doc) => Station.fromJson(doc.data()..['id'] = doc.id)).toList();
    } catch (e) {
      print("Error fetching stations: $e");
      throw Exception('Failed to load stations.');
    }
  }
  
  Future<void> updateSlotStatus({
    required String stationId,
    required int slotIndex,
    required bool isAvailable,
  }) async {
    final stationRef = _firestore.collection('stations').doc(stationId);
    final doc = await stationRef.get();
    if (doc.exists) {
      List<dynamic> slots = doc.data()?['slots'] ?? [];
      if (slotIndex < slots.length) {
        slots[slotIndex]['isAvailable'] = isAvailable;
        await stationRef.update({'slots': slots});
      }
    }
  }

  Future<void> applyPreset(List<Station> updatedStations) async {
    final batch = _firestore.batch();
    for (var station in updatedStations) {
      final stationRef = _firestore.collection('stations').doc(station.id);
      final updatedSlotsJson = station.slots.map((s) => s.toJson()).toList();
      batch.update(stationRef, {'slots': updatedSlotsJson});
    }
    await batch.commit();
  }
}
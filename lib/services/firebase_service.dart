//lib/services/firebase_service.dart ---

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import '../models/navigation_request_model.dart';
import '../models/station_model.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';

class FirebaseService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String _rtdbStationStatusPath = 'station_status';
  final String _serviceAccountJsonPath = 'credentials/serviceAccountKey.json';
  final String _projectId = 'miniproject-c03ff';

  Future<String?> _getAccessToken() async {
    try {
      final jsonString = await rootBundle.loadString(_serviceAccountJsonPath);
      final credentials = ServiceAccountCredentials.fromJson(jsonString);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      final client = await clientViaServiceAccount(credentials, scopes);
      return client.credentials.accessToken.data;
    } catch (e) {
      print("Error getting FCM access token: $e");
      print("IMPORTANT: Make sure '$_serviceAccountJsonPath' exists and is added to pubspec.yaml assets.");
      return null;
    }
  }

  String _encodeEmail(String email) {
    return email.replaceAll('.', ',');
  }
  
  // --- MODIFIED: This method is now safe against missing email fields ---
  Future<List<String>> getUsers() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      if (snapshot.docs.isEmpty) return ['default_simulator_user'];

      // Filter out documents that don't have a valid, non-null 'email' field.
      final validDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        return data.containsKey('email') && data['email'] != null;
      });

      // Now, map only the valid documents to a list of strings.
      return validDocs.map((doc) => doc.data()['email'] as String).toList();
      
    } catch (e) {
      print("Error fetching users: $e");
      return ['default_simulator_user'];
    }
  }
  
  Stream<Vehicle> getVehicleStream({required String email}) {
    final encodedEmail = _encodeEmail(email);
    final vehicleRef = _database.ref('vehicles/$encodedEmail');
    
    return vehicleRef.onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        return Vehicle.fromJson(data);
      } else {
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

  Future<String> getStationName(String stationId) async {
    try {
      final doc = await _firestore.collection('stations').doc(stationId).get();
      if (doc.exists) {
        return doc.data()?['name'] ?? 'Unknown Station';
      }
    } catch (e) {
      print("Error fetching station name: $e");
    }
    return 'Unknown Station';
  }

  Future<void> initializeStationStatusInRTDB(List<Station> stations) async {
    if (stations.isEmpty) return;
    try {
      final Map<String, dynamic> updates = {};
      for (final station in stations) {
        final slotStatusList = station.slots.map((s) => s.isAvailable).toList();
        updates['$_rtdbStationStatusPath/${station.id}'] = slotStatusList;
      }
      await _database.ref().update(updates);
      print("Successfully initialized/updated station statuses in Realtime Database.");
    } catch (e) {
      print("Error initializing station status in RTDB: $e");
    }
  }

  Stream<List<bool>?> getStationStatusStreamRTDB(String stationId) {
    return _database.ref('$_rtdbStationStatusPath/$stationId').onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = List<dynamic>.from(event.snapshot.value as List);
        return data.map((e) => e as bool).toList();
      }
      return null;
    });
  }
  
  Future<void> updateSlotStatus({
    required String stationId,
    required int slotIndex,
    required bool isAvailable,
  }) async {
    final stationRef = _firestore.collection('stations').doc(stationId);
    try {
      final doc = await stationRef.get();
      if (doc.exists) {
        List<dynamic> slots = doc.data()?['slots'] ?? [];
        if (slotIndex < slots.length) {
          slots[slotIndex]['isAvailable'] = isAvailable;
          await stationRef.update({'slots': slots});
          await _database.ref('$_rtdbStationStatusPath/$stationId/$slotIndex').set(isAvailable);
        }
      }
    } catch (e) {
      print("Error updating slot status: $e");
    }
  }

  Future<int?> findAndOccupySlot(String stationId) async {
    final stationRef = _firestore.collection('stations').doc(stationId);
    int? foundSlotIndex;

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(stationRef);
        if (!snapshot.exists) {
          throw Exception("Station document does not exist!");
        }
        
        final station = Station.fromJson(snapshot.data()!..['id'] = snapshot.id);
        final availableSlotIndex = station.slots.indexWhere((slot) => slot.isAvailable);

        if (availableSlotIndex != -1) {
          foundSlotIndex = availableSlotIndex;
          List<Map<String, dynamic>> updatedSlots = station.slots.map((s) => s.toJson()).toList();
          updatedSlots[availableSlotIndex]['isAvailable'] = false;
          
          transaction.update(stationRef, {'slots': updatedSlots});
        }
      });

      if (foundSlotIndex != null) {
        await _database.ref('$_rtdbStationStatusPath/$stationId/$foundSlotIndex').set(false);
        print("Successfully occupied slot $foundSlotIndex at station $stationId");
      }
      return foundSlotIndex;
    } catch (e) {
      print("Error during findAndOccupySlot transaction: $e");
      return null;
    }
  }

  Future<void> applyPreset(List<Station> updatedStations) async {
    final firestoreBatch = _firestore.batch();
    final Map<String, dynamic> rtdbUpdates = {};

    for (var station in updatedStations) {
      final stationRef = _firestore.collection('stations').doc(station.id);
      final updatedSlotsJson = station.slots.map((s) => s.toJson()).toList();
      firestoreBatch.update(stationRef, {'slots': updatedSlotsJson});
      
      final slotStatusList = station.slots.map((s) => s.isAvailable).toList();
      rtdbUpdates['$_rtdbStationStatusPath/${station.id}'] = slotStatusList;
    }

    await Future.wait([
      firestoreBatch.commit(),
      _database.ref().update(rtdbUpdates)
    ]);
  }

  Stream<NavigationRequest?> getNavigationStream({required String email}) {
    return _firestore.collection('navigation').doc(email).snapshots().map((doc) {
      if (doc.exists) {
        return NavigationRequest.fromFirestore(doc);
      }
      return null;
    });
  }

  Future<void> endNavigation({required String email}) async {
    try {
      final navRef = _firestore.collection('navigation').doc(email);
      await navRef.update({
        'isNavigating': false,
        'vehicleReachedStation': false,
        'cancellationReason': null,
        'cancelledStationName': null,
        'stationIsFull': false,
      });
    } catch (e) {
      print("Could not end navigation (might not exist): $e");
    }
  }

  Future<void> setVehicleReachedStation({required String email}) async {
    try {
      final navRef = _firestore.collection('navigation').doc(email);
      await navRef.update({
        'isNavigating': false,
        'vehicleReachedStation': true,
        'cancellationReason': null,
        'cancelledStationName': null,
        'stationIsFull': false,
      });
      print("Updated navigation doc for $email: Vehicle has reached the station.");
    } catch (e) {
      print("Could not update navigation for vehicle arrival: $e");
    }
  }

  Future<void> setVehicleIsCharging({required String email}) async {
    try {
      final navRef = _firestore.collection('navigation').doc(email);
      await navRef.update({
        'isCharging': true,
        'chargingComplete': false,
      });
      print("Updated navigation doc for $email: Vehicle is now charging.");
    } catch (e) {
      print("Could not update navigation for vehicle charging start: $e");
    }
  }

  Future<void> setNavigationChargingComplete({required String email}) async {
    try {
      final navRef = _firestore.collection('navigation').doc(email);
      await navRef.update({
        'isCharging': false,
        'chargingComplete': true,
      });
      print("Updated navigation doc for $email: Vehicle charging is complete.");
    } catch (e) {
      print("Could not update navigation for vehicle charging complete: $e");
    }
  }
  
  Future<void> setNavigationChargingCancelled({required String email}) async {
    try {
      final navRef = _firestore.collection('navigation').doc(email);
      await navRef.update({
        'isCharging': false,
        'chargingComplete': false,
      });
      print("Updated navigation doc for $email: Vehicle charging was cancelled.");
    } catch (e) {
      print("Could not update navigation for vehicle charging cancellation: $e");
    }
  }

  Future<void> cancelNavigationForFullStation({
    required String email,
    required String stationName,
  }) async {
    try {
      final navRef = _firestore.collection('navigation').doc(email);
      await navRef.update({
        'isNavigating': false,
        'vehicleReachedStation': false,
        'cancellationReason': 'STATION_FULL',
        'cancelledStationName': stationName,
        'stationIsFull': true,
      });
      print("Navigation document for $email updated: cancelled because station '$stationName' is full.");
    } catch (e) {
      print("Could not update navigation document for full station: $e");
    }
  }

  Future<UserModel?> getUserSettings(String email) async {
    try {
      final doc = await _firestore.collection('users').doc(email).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromFirestore(doc.data()!);
      }
    } catch (e) {
      print("Error fetching user settings: $e");
    }
    return null;
  }

  Future<void> sendStationFullNotification({ required String fcmToken, required String stationName }) async {
    if (fcmToken.isEmpty) return;
    final accessToken = await _getAccessToken();
    if (accessToken == null) return;
    final String url = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';
    final Map<String, dynamic> message = { 'message': { 'token': fcmToken, 'notification': { 'title': 'Destination Full!', 'body': 'Your destination station "$stationName" has no available slots. Your trip has been cancelled.', }, 'data': { 'type': 'STATION_FULL', 'stationName': stationName } } };
    try {
      await http.post(Uri.parse(url), headers: <String, String>{ 'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken' }, body: jsonEncode(message));
    } catch (e) { print("Error sending V1 FCM notification: $e"); }
  }

  Future<void> sendLowBatteryNotification({ required String fcmToken, required double batteryLevel }) async {
    if (fcmToken.isEmpty) return;
    final accessToken = await _getAccessToken();
    if (accessToken == null) return;
    final String url = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';
    final Map<String, dynamic> message = { 'message': { 'token': fcmToken, 'notification': { 'title': 'Low Battery Alert!', 'body': 'Your EV battery is at ${batteryLevel.toStringAsFixed(0)}%. Find a charging station soon.', } } };
    try {
      await http.post(Uri.parse(url), headers: <String, String>{'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'}, body: jsonEncode(message));
    } catch (e) { print("Error sending V1 FCM notification: $e"); }
  }
}
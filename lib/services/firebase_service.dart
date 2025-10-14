// lib/services/firebase_service.dart ---

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

  // --- NEW: Path for RTDB station status data ---
  final String _rtdbStationStatusPath = 'station_status';

  // --- V1 API CONFIGURATION ---
  final String _serviceAccountJsonPath = 'credentials/serviceAccountKey.json';
  final String _projectId = 'miniproject-c03ff';

  // --- Method to get an OAuth 2.0 Access Token ---
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

  // --- GENERAL METHODS ---

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
  
  // --- VEHICLE METHODS ---
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

  // --- STATION DATA METHODS ---

  // Fetches static station data from Firestore (Source of Truth)
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

  // NEW: Gets a single station's name from Firestore (for notifications)
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

  // NEW: Initializes/Syncs the RTDB structure from Firestore data
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

  // NEW: RTDB Stream for Vehicle Provider to get real-time slot status
  Stream<List<bool>?> getStationStatusStreamRTDB(String stationId) {
    return _database.ref('$_rtdbStationStatusPath/$stationId').onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = List<dynamic>.from(event.snapshot.value as List);
        return data.map((e) => e as bool).toList();
      }
      return null; // Station might not exist in RTDB yet
    });
  }
  
  // MODIFIED: Now updates both Firestore and RTDB for consistency
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
        // Update Firestore (source of truth)
        await stationRef.update({'slots': slots});
        // Update RTDB (for fast real-time listeners)
        await _database.ref('$_rtdbStationStatusPath/$stationId/$slotIndex').set(isAvailable);
      }
    }
  }

  // MODIFIED: Now updates both Firestore and RTDB for consistency
  Future<void> applyPreset(List<Station> updatedStations) async {
    final firestoreBatch = _firestore.batch();
    final Map<String, dynamic> rtdbUpdates = {};

    for (var station in updatedStations) {
      // Prepare Firestore update
      final stationRef = _firestore.collection('stations').doc(station.id);
      final updatedSlotsJson = station.slots.map((s) => s.toJson()).toList();
      firestoreBatch.update(stationRef, {'slots': updatedSlotsJson});
      
      // Prepare RTDB update
      final slotStatusList = station.slots.map((s) => s.isAvailable).toList();
      rtdbUpdates['$_rtdbStationStatusPath/${station.id}'] = slotStatusList;
    }

    // Commit both updates atomically
    await Future.wait([
      firestoreBatch.commit(),
      _database.ref().update(rtdbUpdates)
    ]);
  }

  // --- NAVIGATION METHODS ---
  Stream<NavigationRequest?> getNavigationStream({required String email}) {
    return _firestore.collection('navigation').doc(email).snapshots().map((doc) {
      if (doc.exists) {
        return NavigationRequest.fromFirestore(doc);
      }
      return null;
    });
  }

  // --- MODIFIED: This method now correctly resets all cancellation-related fields ---
  Future<void> endNavigation({required String email}) async {
    try {
      final navRef = _firestore.collection('navigation').doc(email);
      await navRef.update({
        'isNavigating': false,
        'vehicleReachedStation': false,
        'cancellationReason': FieldValue.delete(), // Clears the field
        'cancelledStationName': FieldValue.delete(), // Clears the field
        'stationIsFull': FieldValue.delete(), // Clears the field
      });
    } catch (e) {
      print("Could not end navigation (might not exist): $e");
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
        'stationIsFull': true, // Sets the field
      });
      print("Navigation document for $email updated: cancelled because station '$stationName' is full.");
    } catch (e) {
      print("Could not update navigation document for full station: $e");
    }
  }

  // --- USER SETTINGS & NOTIFICATION METHODS ---
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

  Future<void> sendStationFullNotification({
    required String fcmToken,
    required String stationName,
  }) async {
    if (fcmToken.isEmpty) {
      print("FCM token is empty. Cannot send notification.");
      return;
    }
    final accessToken = await _getAccessToken();
    if (accessToken == null) return;

    final String url = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';
    final Map<String, dynamic> message = {
      'message': {
        'token': fcmToken,
        'notification': {
          'title': 'Destination Full!',
          'body': 'Your destination station "$stationName" has no available slots. Your trip has been cancelled.',
        },
        'data': { 'type': 'STATION_FULL', 'stationName': stationName }
      }
    };
    try {
      final response = await http.post(Uri.parse(url), headers: <String, String>{ 'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken' }, body: jsonEncode(message));
      if (response.statusCode == 200) { print("Successfully sent station full notification via V1 API."); } 
      else { print("Failed to send V1 notification: ${response.statusCode} - ${response.body}"); }
    } catch (e) { print("Error sending V1 FCM notification: $e"); }
  }

  Future<void> sendLowBatteryNotification({
    required String fcmToken,
    required double batteryLevel,
  }) async {
    if (fcmToken.isEmpty) {
      print("FCM token is empty. Cannot send notification.");
      return;
    }
    final accessToken = await _getAccessToken();
    if (accessToken == null) return;
    
    final String url = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';
    final Map<String, dynamic> message = {
      'message': {
        'token': fcmToken,
        'notification': {
          'title': 'Low Battery Alert!',
          'body': 'Your EV battery is at ${batteryLevel.toStringAsFixed(0)}%. Find a charging station soon.',
        },
      }
    };
    try {
      final response = await http.post(Uri.parse(url), headers: <String, String>{'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'}, body: jsonEncode(message));
      if (response.statusCode == 200) { print("Successfully sent low battery notification via V1 API."); } 
      else { print("Failed to send V1 notification: ${response.statusCode} - ${response.body}"); }
    } catch (e) { print("Error sending V1 FCM notification: $e"); }
  }
}
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/station_model.dart';
import '../services/firebase_service.dart';

enum Preset { ideal, normal, busy }

class StationProvider with ChangeNotifier {
  final FirebaseService _firebaseService;
  StationProvider({required FirebaseService firebaseService}) : _firebaseService = firebaseService;

  List<Station> _stations = [];
  List<Station> get stations => _stations;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> fetchStations() async {
    _isLoading = true;
    notifyListeners();
    try {
      _stations = await _firebaseService.getStations();
      // --- NEW: Initialize the Realtime Database with the fetched station statuses ---
      await _firebaseService.initializeStationStatusInRTDB(_stations);
    } catch (e) {
      print("Error fetching stations in provider: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSlot(Station station, int slotIndex, bool isAvailable) async {
    // Optimistic UI update
    station.slots[slotIndex] = station.slots[slotIndex].copyWith(isAvailable: isAvailable);
    notifyListeners();

    // Actual DB call (now updates both Firestore and RTDB)
    await _firebaseService.updateSlotStatus(
      stationId: station.id,
      slotIndex: slotIndex,
      isAvailable: isAvailable,
    );
  }

  Future<void> applyPreset(Preset preset) async {
    if (_stations.isEmpty) return;

    List<Station> updatedStations = [];

    for (var station in _stations) {
      List<Slot> newSlots = [];
      for (var slot in station.slots) {
        bool isAvailable;
        switch (preset) {
          case Preset.ideal:
            isAvailable = true;
            break;
          case Preset.normal:
            isAvailable = Random().nextBool();
            break;
          case Preset.busy:
            isAvailable = false;
            break;
        }
        newSlots.add(slot.copyWith(isAvailable: isAvailable));
      }
      updatedStations.add(station.copyWith(slots: newSlots));
    }
    
    // Optimistic UI update
    _stations = updatedStations;
    notifyListeners();
    
    // Actual DB call (now updates both Firestore and RTDB)
    await _firebaseService.applyPreset(updatedStations);
  }
}
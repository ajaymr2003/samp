//lib/providers/vehicle_provider.dart ---

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as latlong;
import '../models/user_model.dart';
import '../models/vehicle_model.dart';
import '../services/firebase_service.dart';

class VehicleProvider with ChangeNotifier {
  final FirebaseService _firebaseService;
  
  Vehicle _vehicle = Vehicle.initial();
  Vehicle get vehicle => _vehicle;

  bool get isSimulating => _vehicle.isRunning;
  bool get isPaused => _vehicle.isPaused;
  bool get isCharging => _vehicle.isCharging; 
  String? get arrivedAtStationId => _arrivedAtStationId; 

  // --- Simulation State ---
  Timer? _simulationTimer;
  Timer? _chargingTimer; 
  List<latlong.LatLng> _route = [];
  DateTime? _startTime;
  DateTime? _pauseTime;
  DateTime? _lastTickTime;
  double _lastKnownBattery = 100.0;
  String? _destinationStationId; 
  String? _arrivedAtStationId; 
  int? _chargingSlotIndex; 
  
  // --- State for notification logic ---
  UserModel? _userSettings;
  bool _notificationSent = false;
  StreamSubscription? _stationStatusSubscription;
  bool _stationFullNotificationSent = false;

  // --- Dynamic Simulation Parameters ---
  double _vehicleSpeedKmh = 60.0;
  double _drainRatePerMinute = 1.0;
  
  StreamSubscription<Vehicle>? _vehicleSubscription;
  String? _currentUserEmail;

  VehicleProvider({required FirebaseService firebaseService}) : _firebaseService = firebaseService;

  void initialize(String userEmail) {
    if (_currentUserEmail == userEmail && _vehicleSubscription != null) return;
    
    _currentUserEmail = userEmail;
    _vehicleSubscription?.cancel();
    _loadUserSettings(userEmail);
    
    _vehicleSubscription = _firebaseService.getVehicleStream(email: userEmail).listen((vehicleData) {
      final wasCharging = _vehicle.isCharging;
      _vehicle = vehicleData;
      _lastKnownBattery = vehicleData.batteryLevel;
      
      if (wasCharging && !_vehicle.isCharging) {
        _stopChargingTimer();
      }
      notifyListeners();
    });
  }

  Future<void> _loadUserSettings(String email) async {
    _userSettings = await _firebaseService.getUserSettings(email);
    _notificationSent = false;
  }

  void updateVehicleSpeed(double speedKmh) { _vehicleSpeedKmh = speedKmh; }
  void updateDrainRate(double ratePerMinute) { _drainRatePerMinute = ratePerMinute; }

  Future<void> manuallyUpdatePosition(String userEmail, latlong.LatLng newPosition) async {
    if (isSimulating || isPaused || isCharging) return;
    final updatedVehicle = _vehicle.copyWith(
        latitude: newPosition.latitude, longitude: newPosition.longitude, speed: 0.0);
    await _firebaseService.updateVehicleState(email: userEmail, vehicle: updatedVehicle);
  }

  Future<void> manuallyUpdateBattery(String userEmail, double newBatteryLevel) async {
    if (isSimulating || isPaused || isCharging) return;
    final clampedLevel = newBatteryLevel.clamp(0.0, 100.0);
    final updatedVehicle = _vehicle.copyWith(batteryLevel: clampedLevel, speed: 0.0);
    await _firebaseService.updateVehicleState(email: userEmail, vehicle: updatedVehicle);
  }

  void startSimulation({
    required List<latlong.LatLng> route,
    required String userEmail,
    required double initialBattery,
    required double initialSpeedKmh,
    required double initialDrainRate,
    String? destinationStationId, 
  }) {
    if (_simulationTimer?.isActive ?? false) return;
    
    _notificationSent = false; 
    _stationFullNotificationSent = false; 
    _arrivedAtStationId = null; 
    _destinationStationId = destinationStationId; 

    _stationStatusSubscription?.cancel();
    if (destinationStationId != null) {
      print("Monitoring destination station via RTDB: $destinationStationId");
      _stationStatusSubscription = _firebaseService
          .getStationStatusStreamRTDB(destinationStationId)
          .listen((slots) => _onStationStatusChangedRTDB(slots, destinationStationId));
    }

    _vehicleSpeedKmh = initialSpeedKmh;
    _drainRatePerMinute = initialDrainRate;
    _route = route;
    _startTime = DateTime.now();
    _lastTickTime = DateTime.now();
    _lastKnownBattery = initialBattery;
    
    // Speed will be updated on the first tick, so no need to set it here.
    final startingVehicleState = _vehicle.copyWith(
      latitude: route.first.latitude, longitude: route.first.longitude,
      isRunning: true, isPaused: false, batteryLevel: initialBattery, isCharging: false,
    );
    _firebaseService.updateVehicleState(email: userEmail, vehicle: startingVehicleState);
    _startTimer(userEmail);
  }
  
  void pauseSimulation(String userEmail) {
    if (!isSimulating) return;
    _simulationTimer?.cancel();
    _pauseTime = DateTime.now();
    final pausedState = _vehicle.copyWith(isRunning: false, isPaused: true, speed: 0.0);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: pausedState);
  }

  void resumeSimulation(String userEmail) {
    if (!isPaused || _startTime == null || _pauseTime == null) return;
    final pausedDuration = DateTime.now().difference(_pauseTime!);
    _startTime = _startTime!.add(pausedDuration);
    _pauseTime = null;
    _lastTickTime = DateTime.now();
    // Speed will be updated on the next tick.
    final resumedState = _vehicle.copyWith(isRunning: true, isPaused: false);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: resumedState);
    _startTimer(userEmail);
  }

  void forceStopForOverride(String userEmail) {
    if (!isSimulating && !isPaused) return;
    _stationStatusSubscription?.cancel(); 
    _stationStatusSubscription = null;
    _stopSimulationTimer(clearRoute: true);
    final stoppedVehicleState = _vehicle.copyWith(isRunning: false, isPaused: false, isCharging: false, speed: 0.0);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: stoppedVehicleState);
  }

  void stopAndEndTrip(String userEmail) {
    forceStopForOverride(userEmail);
    _arrivedAtStationId = null; 
    _firebaseService.endNavigation(email: userEmail);
  }
  
  void _startTimer(String userEmail) {
     _simulationTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      _onTick(userEmail);
    });
  }

  Future<void> resetSimulation(String userEmail) async {
    stopAndEndTrip(userEmail);
    final resetState = _vehicle.copyWith(batteryLevel: 100.0, isRunning: false, isPaused: false, isCharging: false, speed: 0.0);
    await _firebaseService.updateVehicleState(email: userEmail, vehicle: resetState);
  }

  Future<void> startCharging(String userEmail) async {
    if (isSimulating || isPaused || isCharging || _arrivedAtStationId == null) return;
    
    final slotIndex = await _firebaseService.findAndOccupySlot(_arrivedAtStationId!);
    if (slotIndex != null) {
      _chargingSlotIndex = slotIndex;
      await _firebaseService.setVehicleIsCharging(email: userEmail);
      final chargingState = _vehicle.copyWith(isCharging: true, speed: 0.0);
      await _firebaseService.updateVehicleState(email: userEmail, vehicle: chargingState);
      
      _chargingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        _onChargeTick(userEmail);
      });
    } else {
      print("Could not start charging. No available slots found at $_arrivedAtStationId.");
      _arrivedAtStationId = null; 
      notifyListeners();
    }
  }

  void _onChargeTick(String userEmail) {
    if (_vehicle.batteryLevel >= 100) {
      finishCharging(userEmail);
      return;
    }
    
    final newBatteryLevel = (_vehicle.batteryLevel + 1.0).clamp(0.0, 100.0);
    // Only need to update battery, other states are static during charging.
    final updatedVehicle = _vehicle.copyWith(batteryLevel: newBatteryLevel);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: updatedVehicle);
  }

  Future<void> _endChargingProcess(String userEmail) async {
    if (!isCharging) return;

    _stopChargingTimer();

    if (_arrivedAtStationId != null && _chargingSlotIndex != null) {
      await _firebaseService.updateSlotStatus(
        stationId: _arrivedAtStationId!,
        slotIndex: _chargingSlotIndex!,
        isAvailable: true,
      );
    }
    
    final stoppedChargingState = _vehicle.copyWith(isCharging: false, speed: 0.0);
    await _firebaseService.updateVehicleState(email: userEmail, vehicle: stoppedChargingState);
    
    _arrivedAtStationId = null;
    _chargingSlotIndex = null;
  }

  Future<void> finishCharging(String userEmail) async {
    await _endChargingProcess(userEmail);
    await _firebaseService.setNavigationChargingComplete(email: userEmail);
  }

  Future<void> cancelCharging(String userEmail) async {
    await _endChargingProcess(userEmail);
    await _firebaseService.setNavigationChargingCancelled(email: userEmail);
  }

  void _onStationStatusChangedRTDB(List<bool>? availableSlots, String stationId) async {
    final userEmail = _currentUserEmail;
    if (userEmail == null || !isSimulating || _stationFullNotificationSent) {
      return;
    }
    if (availableSlots != null && !availableSlots.contains(true)) {
      final stationName = await _firebaseService.getStationName(stationId);
      print("Destination station '$stationName' is now full (via RTDB). Cancelling trip.");
      _stationFullNotificationSent = true;
      if (_userSettings != null && _userSettings!.fcmToken.isNotEmpty) {
        _firebaseService.sendStationFullNotification(fcmToken: _userSettings!.fcmToken, stationName: stationName);
      }
      forceStopForOverride(userEmail);
      _firebaseService.cancelNavigationForFullStation(email: userEmail, stationName: stationName);
      _stationStatusSubscription?.cancel();
      _stationStatusSubscription = null;
    }
  }

  void _onTick(String userEmail) {
    final lastTick = _lastTickTime;
    final startTime = _startTime;
    if (startTime == null || lastTick == null || _route.length < 2) { return; }
    
    final now = DateTime.now();
    final elapsedTotal = now.difference(startTime);
    final speedMetersPerSecond = _vehicleSpeedKmh * 1000 / 3600;
    final targetDistanceMeters = elapsedTotal.inMilliseconds * speedMetersPerSecond / 1000;
    final distance = const latlong.Distance();
    double distanceTraveled = 0;
    latlong.LatLng? currentPosition;

    for (int i = 0; i < _route.length - 1; i++) {
      final p1 = _route[i]; final p2 = _route[i+1];
      final segmentLength = distance.as(latlong.LengthUnit.Meter, p1, p2);
      if (distanceTraveled + segmentLength >= targetDistanceMeters) {
        final distanceIntoSegment = targetDistanceMeters - distanceTraveled;
        final fraction = (segmentLength > 0) ? distanceIntoSegment / segmentLength : 0;
        currentPosition = latlong.LatLng(p1.latitude + (p2.latitude - p1.latitude) * fraction, p1.longitude + (p2.longitude - p1.longitude) * fraction);
        break;
      }
      distanceTraveled += segmentLength;
    }
    
    if (currentPosition == null) {
      currentPosition = _route.last;
      _completeTrip(userEmail, currentPosition); 
      return; 
    }
    
    final deltaTime = now.difference(lastTick);
    final drainRatePerSecond = _drainRatePerMinute / 60.0;
    final drainedAmount = deltaTime.inMilliseconds / 1000.0 * drainRatePerSecond;
    _lastKnownBattery -= drainedAmount;
    if (_lastKnownBattery < 0) _lastKnownBattery = 0;
    _lastTickTime = now;
    
    if (_userSettings != null && !_notificationSent && _lastKnownBattery <= _userSettings!.threshold) {
      _notificationSent = true;
      _firebaseService.sendLowBatteryNotification(fcmToken: _userSettings!.fcmToken, batteryLevel: _lastKnownBattery);
    }
    
    // --- MODIFIED: Include the current speed in the update ---
    final updatedVehicle = _vehicle.copyWith(
      latitude: currentPosition.latitude,
      longitude: currentPosition.longitude,
      batteryLevel: _lastKnownBattery,
      speed: _vehicleSpeedKmh, // <-- THE KEY CHANGE
    );
    _firebaseService.updateVehicleState(email: userEmail, vehicle: updatedVehicle);
  }
  
  void _completeTrip(String userEmail, latlong.LatLng finalPosition) {
    _stopSimulationTimer(clearRoute: true);
    
    final finalState = _vehicle.copyWith(
      isRunning: false,
      isPaused: false,
      latitude: finalPosition.latitude,
      longitude: finalPosition.longitude,
      batteryLevel: _lastKnownBattery,
      speed: 0.0, // <-- Set speed to 0 on arrival
    );
    _firebaseService.updateVehicleState(email: userEmail, vehicle: finalState);

    if (_destinationStationId != null) {
      _arrivedAtStationId = _destinationStationId;
      _firebaseService.setVehicleReachedStation(email: userEmail);
    } else {
      _firebaseService.endNavigation(email: userEmail);
    }
    
    _destinationStationId = null; 
    _stationStatusSubscription?.cancel();
    _stationStatusSubscription = null;
    notifyListeners(); 
  }
  
  void _stopSimulationTimer({required bool clearRoute}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    if (clearRoute) _route = [];
    _startTime = null;
    _pauseTime = null;
    _lastTickTime = null;
  }

  void _stopChargingTimer() {
    _chargingTimer?.cancel();
    _chargingTimer = null;
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _chargingTimer?.cancel();
    _vehicleSubscription?.cancel();
    _stationStatusSubscription?.cancel(); 
    super.dispose();
  }
}
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as latlong;
import '../models/vehicle_model.dart';
import '../services/firebase_service.dart';

class VehicleProvider with ChangeNotifier {
  final FirebaseService _firebaseService;
  
  Vehicle _vehicle = Vehicle.initial();
  Vehicle get vehicle => _vehicle;

  bool get isSimulating => _vehicle.isRunning;
  bool get isPaused => _vehicle.isPaused;

  Timer? _simulationTimer;
  List<latlong.LatLng> _route = [];
  DateTime? _startTime;
  DateTime? _pauseTime;
  DateTime? _lastTickTime;
  double _lastKnownBattery = 100.0;

  double _vehicleSpeedKmh = 60.0;
  double _drainRatePerMinute = 1.0;
  
  StreamSubscription<Vehicle>? _vehicleSubscription;
  String? _currentUserEmail;

  VehicleProvider({required FirebaseService firebaseService}) : _firebaseService = firebaseService;

  void initialize(String userEmail) {
    if (_currentUserEmail == userEmail && _vehicleSubscription != null) return;
    _currentUserEmail = userEmail;
    _vehicleSubscription?.cancel();
    _vehicleSubscription = _firebaseService.getVehicleStream(email: userEmail).listen((vehicleData) {
      _vehicle = vehicleData;
      _lastKnownBattery = vehicleData.batteryLevel;
      if (!_vehicle.isRunning && (_simulationTimer?.isActive ?? false)) {
        _stopSimulationTimer(clearRoute: false);
      }
      notifyListeners();
    });
  }

  void updateVehicleSpeed(double speedKmh) { _vehicleSpeedKmh = speedKmh; }
  void updateDrainRate(double ratePerMinute) { _drainRatePerMinute = ratePerMinute; }
  Future<void> manuallyUpdatePosition(String userEmail, latlong.LatLng newPosition) async {
    if (isSimulating || isPaused) return;
    final updatedVehicle = _vehicle.copyWith(latitude: newPosition.latitude, longitude: newPosition.longitude);
    await _firebaseService.updateVehicleState(email: userEmail, vehicle: updatedVehicle);
  }

  // --- NEW: Method to manually set the vehicle's battery level ---
  Future<void> manuallyUpdateBattery(String userEmail, double newBatteryLevel) async {
    if (isSimulating || isPaused) return; // Prevent changing battery mid-trip

    // Clamp the value to be between 0 and 100
    final clampedLevel = newBatteryLevel.clamp(0.0, 100.0);
    final updatedVehicle = _vehicle.copyWith(batteryLevel: clampedLevel);
    await _firebaseService.updateVehicleState(email: userEmail, vehicle: updatedVehicle);
  }

  void startSimulation({
    required List<latlong.LatLng> route,
    required String userEmail,
    required double initialBattery,
    required double initialSpeedKmh,
    required double initialDrainRate,
  }) {
    if (isSimulating || route.isEmpty) return;
    _vehicleSpeedKmh = initialSpeedKmh;
    _drainRatePerMinute = initialDrainRate;
    _route = route;
    _startTime = DateTime.now();
    _lastTickTime = DateTime.now();
    _lastKnownBattery = initialBattery;
    final startingVehicleState = _vehicle.copyWith(
      latitude: route.first.latitude, longitude: route.first.longitude,
      isRunning: true, isPaused: false, batteryLevel: initialBattery,
    );
    _firebaseService.updateVehicleState(email: userEmail, vehicle: startingVehicleState);
    _startTimer(userEmail);
  }
  
  void pauseSimulation(String userEmail) {
    if (!isSimulating) return;
    _simulationTimer?.cancel();
    _pauseTime = DateTime.now();
    final pausedState = _vehicle.copyWith(isRunning: false, isPaused: true);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: pausedState);
  }

  void resumeSimulation(String userEmail) {
    if (!isPaused || _startTime == null || _pauseTime == null) return;
    final pausedDuration = DateTime.now().difference(_pauseTime!);
    _startTime = _startTime!.add(pausedDuration);
    _pauseTime = null;
    _lastTickTime = DateTime.now();
    final resumedState = _vehicle.copyWith(isRunning: true, isPaused: false);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: resumedState);
    _startTimer(userEmail);
  }

  void forceStopForOverride(String userEmail) {
    if (!isSimulating && !isPaused) return;
    _stopSimulationTimer(clearRoute: true);
    final stoppedVehicleState = _vehicle.copyWith(isRunning: false, isPaused: false);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: stoppedVehicleState);
  }

  void stopAndEndTrip(String userEmail) {
    forceStopForOverride(userEmail);
    _firebaseService.endNavigation(email: userEmail);
  }
  
  void _startTimer(String userEmail) {
     _simulationTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      _onTick(userEmail);
    });
  }

  Future<void> resetSimulation(String userEmail) async {
    stopAndEndTrip(userEmail);
    final resetState = _vehicle.copyWith(batteryLevel: 100.0, isRunning: false, isPaused: false);
    await _firebaseService.updateVehicleState(email: userEmail, vehicle: resetState);
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
      stopAndEndTrip(userEmail);
    }
    final deltaTime = now.difference(lastTick);
    final drainRatePerSecond = _drainRatePerMinute / 60.0;
    final drainedAmount = deltaTime.inMilliseconds / 1000.0 * drainRatePerSecond;
    _lastKnownBattery -= drainedAmount;
    if (_lastKnownBattery < 0) _lastKnownBattery = 0;
    _lastTickTime = now;
    final updatedVehicle = _vehicle.copyWith(latitude: currentPosition.latitude, longitude: currentPosition.longitude, batteryLevel: _lastKnownBattery);
    _firebaseService.updateVehicleState(email: userEmail, vehicle: updatedVehicle);
  }
  
  void _stopSimulationTimer({required bool clearRoute}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    if (clearRoute) _route = [];
    _startTime = null;
    _pauseTime = null;
    _lastTickTime = null;
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _vehicleSubscription?.cancel();
    super.dispose();
  }
}
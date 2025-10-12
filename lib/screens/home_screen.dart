import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/navigation_request_model.dart';
import '../models/station_model.dart';
import '../models/vehicle_model.dart';
import '../providers/station_provider.dart';
import '../providers/vehicle_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Controllers
  final MapController _mapController = MapController();
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _batteryController = TextEditingController();

  // State
  List<String> _userEmails = [];
  String? _selectedUserEmail;
  bool _isLoading = true;
  String _mapInstruction = "Loading simulator users...";
  bool _isEditingLocation = false;

  // Route Planning
  LatLng? _destinationPoint;
  List<LatLng> _routePoints = [];
  
  // Simulation parameters
  double _vehicleSpeedKmh = 60.0;
  double _drainRatePerMinute = 1.0;
  
  // State for handling remote navigation
  StreamSubscription? _navigationSubscription;
  bool _isProcessingRemoteNav = false; // State lock for remote commands

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }
  
  Future<void> _loadInitialData() async {
    final users = await _firebaseService.getUsers();
    await context.read<StationProvider>().fetchStations(); 
    if (!mounted) return;
    setState(() {
      _userEmails = users;
      _isLoading = false;
      _mapInstruction = users.isNotEmpty
          ? "Select a simulator user to begin."
          : "No users found in database.";
    });
  }

  @override
  void dispose() {
    _navigationSubscription?.cancel();
    _batteryController.dispose();
    super.dispose();
  }

  void _onUserSelected(String? email) {
    if (email == null || email == _selectedUserEmail) return;
    final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);
    if (vehicleProvider.isSimulating || vehicleProvider.isPaused) {
       vehicleProvider.stopAndEndTrip(_selectedUserEmail!);
    }
    _resetState(clearUser: false);
    setState(() { _selectedUserEmail = email; });
    vehicleProvider.initialize(email);
    
    _listenForRemoteNavigation(email);

    final vehicleStream = _firebaseService.getVehicleStream(email: email);
    StreamSubscription? tempSub;
    tempSub = vehicleStream.listen((vehicle) {
      if (mounted) {
        final vehicleLocation = LatLng(vehicle.latitude, vehicle.longitude);
        _mapController.move(vehicleLocation, 14.0);
        _batteryController.text = vehicle.batteryLevel.toStringAsFixed(0);
        setState(() {
          _mapInstruction = "Vehicle location set. Click map to set a Destination.";
        });
      }
      tempSub?.cancel();
    });
  }

  void _listenForRemoteNavigation(String email) {
    _navigationSubscription?.cancel();
    _navigationSubscription = _firebaseService.getNavigationStream(email: email).listen((navRequest) {
      if (navRequest != null && navRequest.isNavigating && !_isProcessingRemoteNav) {
        _startRemoteNavigation(navRequest);
      } 
      else if (navRequest == null || !navRequest.isNavigating) {
         if (_isProcessingRemoteNav) {
          setState(() {
            _isProcessingRemoteNav = false;
            _destinationPoint = null;
            _routePoints = [];
            _mapInstruction = "Remote trip ended. Set a new destination.";
          });
        }
      }
    });
  }

  Future<void> _startRemoteNavigation(NavigationRequest navRequest) async {
    final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);

    setState(() {
      _isProcessingRemoteNav = true;
      if (vehicleProvider.isSimulating || vehicleProvider.isPaused) {
        vehicleProvider.forceStopForOverride(_selectedUserEmail!);
      }
      _mapInstruction = "REMOTE COMMAND: Calculating route...";
      _destinationPoint = navRequest.end;
      _routePoints = [];
    });

    final newRoute = await _calculateAndDrawRoute(navRequest.start);
    if (newRoute != null) {
      vehicleProvider.startSimulation(
        route: newRoute,
        userEmail: _selectedUserEmail!,
        initialBattery: vehicleProvider.vehicle.batteryLevel,
        initialSpeedKmh: _vehicleSpeedKmh,
        initialDrainRate: _drainRatePerMinute,
      );
      setState(() { _mapInstruction = "AUTOMATIC TRIP IN PROGRESS..."; });
    } else {
      await _firebaseService.endNavigation(email: _selectedUserEmail!);
      setState(() { 
        _mapInstruction = "Failed to calculate remote route.";
        _isProcessingRemoteNav = false;
      });
    }
  }

  void _resetState({bool clearUser = false}) {
    setState(() {
      if (clearUser) {
        _selectedUserEmail = null;
        _navigationSubscription?.cancel();
      }
      _destinationPoint = null;
      _routePoints = [];
      _vehicleSpeedKmh = 60.0;
      _drainRatePerMinute = 1.0;
      _isEditingLocation = false;
      _isProcessingRemoteNav = false;
      _mapInstruction = "Select a user to begin.";
    });
  }

  Future<void> _onMapTap(TapPosition pos, LatLng latlng) async {
    final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);
    if (vehicleProvider.isSimulating || vehicleProvider.isPaused || _selectedUserEmail == null || _isProcessingRemoteNav) return;
    
    if (_isEditingLocation) {
      await vehicleProvider.manuallyUpdatePosition(_selectedUserEmail!, latlng);
      setState(() {
        _isEditingLocation = false;
        _mapInstruction = "Vehicle location set. Click map to set a Destination.";
      });
      return;
    }

    setState(() {
      _destinationPoint = latlng;
      _routePoints = [];
      _mapInstruction = "Destination set. Press Start to begin trip.";
    });
  }
  
  Future<List<LatLng>?> _calculateAndDrawRoute([LatLng? startPointOverride]) async {
    final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);
    final startPoint = startPointOverride ?? LatLng(vehicleProvider.vehicle.latitude, vehicleProvider.vehicle.longitude);
    
    if (_destinationPoint == null) return null;
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final points = await apiService.getRoute(startPoint, _destinationPoint!);
      if (points.isNotEmpty && mounted) {
        setState(() { _routePoints = points; });
        _mapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(50)));
        return points;
      } else { 
        throw Exception("No route found");
      }
    } catch (e) {
      if (!mounted) return null;
      setState(() { _destinationPoint = null; _mapInstruction = "Could not find a route. Pick a new destination."; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error calculating route: $e')));
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleProvider = Provider.of<VehicleProvider>(context);
    final stationProvider = Provider.of<StationProvider>(context);

    if (!vehicleProvider.isSimulating && !vehicleProvider.isPaused && _selectedUserEmail != null) {
      final providerValue = vehicleProvider.vehicle.batteryLevel.toStringAsFixed(0);
      if (_batteryController.text != providerValue) {
        _batteryController.text = providerValue;
      }
    }

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: LatLng(12.9716, 77.5946), initialZoom: 14, onTap: _onMapTap),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'dev.flutter.ev_simulator'),
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(polylines: [ Polyline(points: _routePoints, color: Colors.blue.withOpacity(0.8), strokeWidth: 5) ]),
                    MarkerLayer(markers: _buildMarkers(vehicleProvider.vehicle, stationProvider.stations)),
                  ],
                ),
                if (_userEmails.isNotEmpty) _buildUserSelector(vehicleProvider.isSimulating || vehicleProvider.isPaused || _isProcessingRemoteNav),
                _buildControlPanel(vehicleProvider),
              ],
            ),
    );
  }

  Widget _buildUserSelector(bool isLocked) {
    return Positioned(
      top: 10, left: 10, right: 10,
      child: SafeArea(
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: DropdownButtonFormField<String>(
              value: _selectedUserEmail, isExpanded: true,
              hint: const Text('Select Simulator User'),
              items: _userEmails.map((email) => DropdownMenuItem(value: email, child: Text(email, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: isLocked ? null : _onUserSelected,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel(VehicleProvider vehicleProvider) {
    final isSimulating = vehicleProvider.isSimulating;
    final isPaused = vehicleProvider.isPaused;
    final canStart = _destinationPoint != null && !isSimulating && !isPaused && _selectedUserEmail != null;

    Widget actionButton;
    Widget secondaryButton;
    if (isSimulating) {
      actionButton = _buildActionButton(icon: Icons.pause_rounded, text: 'Pause', color: Colors.amber.shade700,
        onPressed: () { vehicleProvider.pauseSimulation(_selectedUserEmail!); }
      );
    } else if (isPaused) {
      actionButton = _buildActionButton(icon: Icons.play_arrow_rounded, text: 'Resume', color: Colors.green.shade600,
        onPressed: () { vehicleProvider.resumeSimulation(_selectedUserEmail!); }
      );
    } else {
       actionButton = _buildActionButton(
        icon: Icons.play_arrow_rounded, text: 'Start', color: Colors.green.shade600,
        onPressed: !canStart || _isProcessingRemoteNav ? null : () async {
          setState(() { _mapInstruction = "Calculating route..."; });
          final newRoute = await _calculateAndDrawRoute();
          if (newRoute != null) {
            vehicleProvider.startSimulation(
              route: newRoute, userEmail: _selectedUserEmail!,
              initialBattery: vehicleProvider.vehicle.batteryLevel,
              initialSpeedKmh: _vehicleSpeedKmh, initialDrainRate: _drainRatePerMinute,
            );
            setState(() { _mapInstruction = "Simulation in progress..."; });
          }
        }
      );
    }
    
    secondaryButton = _buildActionButton(icon: Icons.stop_rounded, text: 'End Trip', color: Colors.red.shade600,
      onPressed: (!isSimulating && !isPaused) || _selectedUserEmail == null ? null : () {
        vehicleProvider.stopAndEndTrip(_selectedUserEmail!);
        setState(() {
          _destinationPoint = null;
          _routePoints = [];
          _mapInstruction = "Trip ended. Set a new destination.";
        });
      }
    );

    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: SafeArea(
        child: Card(
          margin: const EdgeInsets.all(12), elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Text("LIVE BATTERY", style: Theme.of(context).textTheme.labelSmall),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(vehicleProvider.vehicle.batteryLevel > 20 ? Icons.battery_full_rounded : Icons.battery_alert_rounded, color: vehicleProvider.vehicle.batteryLevel > 20 ? Colors.green.shade700 : Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text("${vehicleProvider.vehicle.batteryLevel.toStringAsFixed(0)}%", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    )),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _batteryController,
                              enabled: !isSimulating && !isPaused && _selectedUserEmail != null,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(labelText: 'Set Battery', suffixText: '%', isDense: true, border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check_circle),
                            color: Theme.of(context).primaryColor,
                            tooltip: 'Set Battery Level',
                            onPressed: isSimulating || isPaused || _selectedUserEmail == null ? null : () {
                              final newLevel = double.tryParse(_batteryController.text);
                              if (newLevel != null) {
                                vehicleProvider.manuallyUpdateBattery(_selectedUserEmail!, newLevel);
                                FocusScope.of(context).unfocus();
                              }
                            },
                          )
                        ],
                      ),
                    ),
                  ],
                ),
                if (_selectedUserEmail != null) ...[
                  const Divider(height: 24),
                  _buildSpeedSlider(vehicleProvider),
                  _buildDrainSlider(vehicleProvider),
                  const Divider(height: 24),
                ] else ...[
                  const SizedBox(height: 12),
                ],
                Text(_mapInstruction, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                Row(children: [ Expanded(child: actionButton), const SizedBox(width: 10), Expanded(child: secondaryButton) ]),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Reset Vehicle (100% Bat)'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                  onPressed: isSimulating || isPaused || _selectedUserEmail == null || _isProcessingRemoteNav ? null : () {
                    vehicleProvider.resetSimulation(_selectedUserEmail!);
                    setState(() { _routePoints = []; _destinationPoint = null; _mapInstruction = "Vehicle reset. Set a new destination."; });
                  },
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String text, required Color color, required VoidCallback? onPressed}) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        disabledBackgroundColor: color.withOpacity(0.4),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildSpeedSlider(VehicleProvider vehicleProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Vehicle Speed: ${_vehicleSpeedKmh.round()} km/h", style: Theme.of(context).textTheme.labelMedium),
        Slider(
          value: _vehicleSpeedKmh,
          min: 5,
          max: 140,
          divisions: 27,
          label: "${_vehicleSpeedKmh.round()} km/h",
          onChanged: (value) {
            setState(() => _vehicleSpeedKmh = value);
            vehicleProvider.updateVehicleSpeed(value);
          },
        ),
      ],
    );
  }

  Widget _buildDrainSlider(VehicleProvider vehicleProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Battery Drain: ${_drainRatePerMinute.toStringAsFixed(1)}% per minute", style: Theme.of(context).textTheme.labelMedium),
        Slider(
          value: _drainRatePerMinute,
          min: 0.5,
          max: 20.0,
          divisions: 39,
          label: "${_drainRatePerMinute.toStringAsFixed(1)}%",
          onChanged: (value) {
            setState(() => _drainRatePerMinute = value);
            vehicleProvider.updateDrainRate(value);
          },
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(Vehicle vehicle, List<Station> stations) {
    List<Marker> markers = [];
    if (_selectedUserEmail == null) return markers;

    for (final station in stations) {
      markers.add(
        Marker(
          point: LatLng(station.latitude, station.longitude),
          width: 40, height: 40,
          child: GestureDetector(
            onTap: () {
              _onMapTap(const TapPosition(Offset.zero, Offset.zero), LatLng(station.latitude, station.longitude));
            },
            child: Image.asset('assets/station_icon.png'),
          ),
        ),
      );
    }

    if (_destinationPoint != null) {
      markers.add(Marker(point: _destinationPoint!, width: 40, height: 40, child: const Icon(Icons.flag, color: Colors.red, size: 40)));
    }
    
    markers.add(Marker(
      point: LatLng(vehicle.latitude, vehicle.longitude),
      width: 40, height: 40,
      child: (vehicle.isRunning || vehicle.isPaused)
          ? Image.asset('assets/car_icon.png')
          : const Icon(Icons.location_on, color: Colors.green, size: 40),
    ));
    
    return markers;
  }
}
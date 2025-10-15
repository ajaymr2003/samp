//lib/models/vehicle_model.dart ---

class Vehicle {
  final double batteryLevel;
  final bool isRunning;
  final bool isPaused;
  final bool isCharging; // <-- NEW PROPERTY
  final double latitude;
  final double longitude;

  Vehicle({
    required this.batteryLevel,
    required this.isRunning,
    required this.isPaused,
    required this.isCharging, // <-- NEW
    required this.latitude,
    required this.longitude,
  });

  Vehicle copyWith({
    double? batteryLevel,
    bool? isRunning,
    bool? isPaused,
    bool? isCharging, // <-- NEW
    double? latitude,
    double? longitude,
  }) {
    return Vehicle(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      isCharging: isCharging ?? this.isCharging, // <-- NEW
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      batteryLevel: (json['batteryLevel'] ?? 100).toDouble(),
      isRunning: json['isRunning'] ?? false,
      isPaused: json['isPaused'] ?? false,
      isCharging: json['isCharging'] ?? false, // <-- NEW
      latitude: (json['latitude'] ?? 12.9716).toDouble(),
      longitude: (json['longitude'] ?? 77.5946).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batteryLevel': batteryLevel,
      'isRunning': isRunning,
      'isPaused': isPaused,
      'isCharging': isCharging, // <-- NEW
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Vehicle.initial() {
    return Vehicle(
      batteryLevel: 100,
      isRunning: false,
      isPaused: false,
      isCharging: false, // <-- NEW
      latitude: 12.9716,
      longitude: 77.5946,
    );
  }
}
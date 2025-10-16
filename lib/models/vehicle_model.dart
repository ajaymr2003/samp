//lib/models/vehicle_model.dart ---

class Vehicle {
  final double batteryLevel;
  final bool isRunning;
  final bool isPaused;
  final bool isCharging; 
  final double latitude;
  final double longitude;
  final double speed; // <-- NEW PROPERTY

  Vehicle({
    required this.batteryLevel,
    required this.isRunning,
    required this.isPaused,
    required this.isCharging, 
    required this.latitude,
    required this.longitude,
    required this.speed, // <-- NEW
  });

  Vehicle copyWith({
    double? batteryLevel,
    bool? isRunning,
    bool? isPaused,
    bool? isCharging, 
    double? latitude,
    double? longitude,
    double? speed, // <-- NEW
  }) {
    return Vehicle(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      isCharging: isCharging ?? this.isCharging, 
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speed: speed ?? this.speed, // <-- NEW
    );
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      batteryLevel: (json['batteryLevel'] ?? 100).toDouble(),
      isRunning: json['isRunning'] ?? false,
      isPaused: json['isPaused'] ?? false,
      isCharging: json['isCharging'] ?? false, 
      latitude: (json['latitude'] ?? 12.9716).toDouble(),
      longitude: (json['longitude'] ?? 77.5946).toDouble(),
      speed: (json['speed'] ?? 0.0).toDouble(), // <-- NEW
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batteryLevel': batteryLevel,
      'isRunning': isRunning,
      'isPaused': isPaused,
      'isCharging': isCharging, 
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed, // <-- NEW
    };
  }

  factory Vehicle.initial() {
    return Vehicle(
      batteryLevel: 100,
      isRunning: false,
      isPaused: false,
      isCharging: false, 
      latitude: 12.9716,
      longitude: 77.5946,
      speed: 0.0, // <-- NEW
    );
  }
}
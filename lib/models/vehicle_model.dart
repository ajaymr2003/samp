class Vehicle {
  final double batteryLevel;
  final bool isRunning;
  final bool isPaused; // <-- NEW PROPERTY
  final double latitude;
  final double longitude;

  Vehicle({
    required this.batteryLevel,
    required this.isRunning,
    required this.isPaused, // <-- NEW
    required this.latitude,
    required this.longitude,
  });

  Vehicle copyWith({
    double? batteryLevel,
    bool? isRunning,
    bool? isPaused, // <-- NEW
    double? latitude,
    double? longitude,
  }) {
    return Vehicle(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused, // <-- NEW
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      batteryLevel: (json['batteryLevel'] ?? 100).toDouble(),
      isRunning: json['isRunning'] ?? false,
      isPaused: json['isPaused'] ?? false, // <-- NEW
      latitude: (json['latitude'] ?? 12.9716).toDouble(),
      longitude: (json['longitude'] ?? 77.5946).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batteryLevel': batteryLevel,
      'isRunning': isRunning,
      'isPaused': isPaused, // <-- NEW
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Vehicle.initial() {
    return Vehicle(
      batteryLevel: 100,
      isRunning: false,
      isPaused: false, // <-- NEW
      latitude: 12.9716,
      longitude: 77.5946,
    );
  }
}
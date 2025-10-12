class Station {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final List<Slot> slots;
  final int totalSlots;
  final String operatingHours;
  final bool cctvAvailable;
  final bool foodNearby;
  final bool parkingAvailable;
  final bool restroomAvailable;
  final bool wifiAvailable;

  Station({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.slots,
    required this.totalSlots,
    required this.operatingHours,
    required this.cctvAvailable,
    required this.foodNearby,
    required this.parkingAvailable,
    required this.restroomAvailable,
    required this.wifiAvailable,
  });

  /// This getter remains the most reliable way to check current availability.
  /// It derives the state directly from the `slots` list's `isAvailable` flags.
  int get availableSlots => slots.where((s) => s.isAvailable).length;

  factory Station.fromJson(Map<String, dynamic> json) {
    var slotsList = json['slots'] as List? ?? [];
    List<Slot> parsedSlots = slotsList.map((i) => Slot.fromJson(i)).toList();
    return Station(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Station',
      address: json['address'] ?? 'No address',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      slots: parsedSlots,
      totalSlots: (json['totalSlots'] ?? parsedSlots.length).toInt(),
      operatingHours: json['operatingHours'] ?? 'N/A',
      cctvAvailable: json['cctvAvailable'] ?? false,
      foodNearby: json['foodNearby'] ?? false,
      parkingAvailable: json['parkingAvailable'] ?? false,
      restroomAvailable: json['restroomAvailable'] ?? false,
      wifiAvailable: json['wifiAvailable'] ?? false,
    );
  }

  Station copyWith({List<Slot>? slots}) {
    return Station(
      id: id,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      slots: slots ?? this.slots,
      totalSlots: totalSlots,
      operatingHours: operatingHours,
      cctvAvailable: cctvAvailable,
      foodNearby: foodNearby,
      parkingAvailable: parkingAvailable,
      restroomAvailable: restroomAvailable,
      wifiAvailable: wifiAvailable,
    );
  }
}

class Slot {
  final bool isAvailable;
  final String chargerType;
  final int powerKw;

  Slot({ required this.isAvailable, required this.chargerType, required this.powerKw });

  factory Slot.fromJson(Map<String, dynamic> json) {
    return Slot(isAvailable: json['isAvailable'] ?? false, chargerType: json['chargerType'] ?? 'Unknown', powerKw: (json['powerKw'] ?? 0).toInt());
  }

  // NEW: copyWith for easier immutable updates
  Slot copyWith({bool? isAvailable}) {
    return Slot(isAvailable: isAvailable ?? this.isAvailable, chargerType: chargerType, powerKw: powerKw);
  }
  
  // NEW: toJson for writing back to Firestore
  Map<String, dynamic> toJson() {
    return {'isAvailable': isAvailable, 'chargerType': chargerType, 'powerKw': powerKw};
  }
}
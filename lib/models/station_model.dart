class Station {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final List<Slot> slots;

  Station({ required this.id, required this.name, required this.address, required this.latitude, required this.longitude, required this.slots });

  int get availableSlots => slots.where((s) => s.isAvailable).length;

  factory Station.fromJson(Map<String, dynamic> json) {
    var slotsList = json['slots'] as List? ?? [];
    List<Slot> parsedSlots = slotsList.map((i) => Slot.fromJson(i)).toList();
    return Station(id: json['id'] ?? '', name: json['name'] ?? 'Unknown Station', address: json['address'] ?? 'No address', latitude: (json['latitude'] ?? 0.0).toDouble(), longitude: (json['longitude'] ?? 0.0).toDouble(), slots: parsedSlots);
  }

  // NEW: copyWith for easier immutable updates
  Station copyWith({List<Slot>? slots}) {
    return Station(id: id, name: name, address: address, latitude: latitude, longitude: longitude, slots: slots ?? this.slots);
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
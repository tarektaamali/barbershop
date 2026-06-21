class Service {
  const Service({
    required this.id,
    required this.salonId,
    required this.name,
    required this.durationMin,
    required this.price,
    required this.active,
  });

  final String id;
  final String salonId;
  final String name;
  final int durationMin;
  final double price;
  final bool active;

  factory Service.fromMap(Map<String, dynamic> map) {
    return Service(
      id: map['id'] as String,
      salonId: map['salon_id'] as String,
      name: map['name'] as String,
      durationMin: map['duration_min'] as int,
      price: (map['price'] as num? ?? 0).toDouble(),
      active: map['active'] as bool? ?? true,
    );
  }
}

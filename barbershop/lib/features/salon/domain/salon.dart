enum SalonStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  suspended('suspended');

  const SalonStatus(this.dbValue);

  final String dbValue;

  static SalonStatus fromDb(String value) {
    return SalonStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => SalonStatus.pending,
    );
  }
}

class Salon {
  const Salon({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.city,
    required this.status,
    required this.showPrices,
    required this.ratingAvg,
    required this.ratingCount,
    this.description,
    this.address,
    this.coverUrl,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String city;
  final String? address;
  final String? coverUrl;
  final SalonStatus status;
  final bool showPrices;
  final double ratingAvg;
  final int ratingCount;

  factory Salon.fromMap(Map<String, dynamic> map) {
    return Salon(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      city: map['city'] as String,
      address: map['address'] as String?,
      coverUrl: map['cover_url'] as String?,
      status: SalonStatus.fromDb(map['status'] as String? ?? 'pending'),
      showPrices: map['show_prices'] as bool? ?? true,
      ratingAvg: (map['rating_avg'] as num? ?? 0).toDouble(),
      ratingCount: map['rating_count'] as int? ?? 0,
    );
  }
}

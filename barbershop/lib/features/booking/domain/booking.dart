enum BookingStatus {
  pending('pending'),
  confirmed('confirmed'),
  declined('declined'),
  cancelled('cancelled'),
  completed('completed'),
  noShow('no_show');

  const BookingStatus(this.dbValue);

  final String dbValue;

  static BookingStatus fromDb(String value) {
    return BookingStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => BookingStatus.pending,
    );
  }
}

class Booking {
  const Booking({
    required this.id,
    required this.salonId,
    required this.serviceName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.priceDefault,
    this.staffId,
  });

  final String id;
  final String salonId;
  final String? staffId;
  final String serviceName;
  final String date;
  final String startTime;
  final String endTime;
  final BookingStatus status;
  final double priceDefault;

  String get startHm => _hm(startTime);
  String get endHm => _hm(endTime);

  static String _hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id'] as String,
      salonId: map['salon_id'] as String,
      staffId: map['staff_id'] as String?,
      serviceName: map['service_name_snapshot'] as String,
      date: map['date'] as String,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      status: BookingStatus.fromDb(map['status'] as String? ?? 'pending'),
      priceDefault: (map['price_default_snapshot'] as num? ?? 0).toDouble(),
    );
  }
}

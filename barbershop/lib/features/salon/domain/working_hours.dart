class WorkingHours {
  const WorkingHours({
    required this.id,
    required this.staffId,
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String staffId;
  final int weekday;
  final String startTime;
  final String endTime;

  String get startHm => _hm(startTime);
  String get endHm => _hm(endTime);

  static String _hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  factory WorkingHours.fromMap(Map<String, dynamic> map) {
    return WorkingHours(
      id: map['id'] as String,
      staffId: map['staff_id'] as String,
      weekday: map['weekday'] as int,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
    );
  }
}

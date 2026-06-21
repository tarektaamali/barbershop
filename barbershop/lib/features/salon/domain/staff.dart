class Staff {
  const Staff({
    required this.id,
    required this.salonId,
    required this.displayName,
    required this.active,
    this.specialty,
    this.avatarUrl,
  });

  final String id;
  final String salonId;
  final String displayName;
  final String? specialty;
  final String? avatarUrl;
  final bool active;

  factory Staff.fromMap(Map<String, dynamic> map) {
    return Staff(
      id: map['id'] as String,
      salonId: map['salon_id'] as String,
      displayName: map['display_name'] as String,
      specialty: map['specialty'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }
}

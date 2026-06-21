enum UserRole {
  customer('customer'),
  salonOwner('salon_owner'),
  staff('staff'),
  admin('admin');

  const UserRole(this.dbValue);

  final String dbValue;

  static UserRole fromDb(String value) {
    return UserRole.values.firstWhere(
      (r) => r.dbValue == value,
      orElse: () => UserRole.customer,
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.language,
    this.fullName,
  });

  final String id;
  final UserRole role;
  final String language;
  final String? fullName;

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      role: UserRole.fromDb(map['role'] as String? ?? 'customer'),
      fullName: map['full_name'] as String?,
      language: map['language'] as String? ?? 'fr',
    );
  }
}

class User {
  final String? id;
  final String firstName;
  final String lastName;
  final String email;
  final String username;
  final String password;
  final String? avatarUrl;
  final String? address;
  final String? gender;
  final String? resetCode;
  final DateTime? resetExpires;
  final DateTime createdAt;

  User({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.username,
    required this.password,
    this.avatarUrl,
    this.address,
    this.gender,
    this.resetCode,
    this.resetExpires,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      avatarUrl: json['avatar_url'] as String?,
      address: json['address'] as String?,
      gender: json['gender'] as String?,
      resetCode: json['reset_code'] as String?,
      resetExpires: json['reset_expires'] != null
          ? DateTime.parse(json['reset_expires'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'username': username,
      'avatar_url': avatarUrl,
      'address': address,
      'gender': gender,
      'reset_code': resetCode,
      'reset_expires': resetExpires?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

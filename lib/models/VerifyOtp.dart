class VerifyOtp {
  final String id;
  final String email;
  final String code;
  final DateTime expiresAt;
  final DateTime createdAt;

  VerifyOtp({
    required this.id,
    required this.email,
    required this.code,
    required this.expiresAt,
    required this.createdAt,
  });

  factory VerifyOtp.fromJson(Map<String, dynamic> json) {
    return VerifyOtp(
      id: json['id'] as String,
      email: json['email'] as String,
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'code': code,
      'expires_at': expiresAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

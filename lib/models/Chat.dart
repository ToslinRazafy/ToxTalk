class Chat {
  final String id;
  final String type;
  final String? name;
  final DateTime createdAt;

  Chat({
    required this.id,
    required this.type,
    this.name,
    required this.createdAt,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ChatMember {
  final String chatId;
  final String userId;
  final DateTime joinedAt;

  ChatMember({
    required this.chatId,
    required this.userId,
    required this.joinedAt,
  });

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    return ChatMember(
      chatId: json['chat_id'] as String,
      userId: json['user_id'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chat_id': chatId,
      'user_id': userId,
      'joined_at': joinedAt.toIso8601String(),
    };
  }
}

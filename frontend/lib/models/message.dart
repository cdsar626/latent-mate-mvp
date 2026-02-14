  final String? id;
  final String senderId;
  final String content;
  final bool isMe;
  final DateTime? timestamp;
  final String type;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    this.id,
    required this.senderId,
    required this.content,
    required this.isMe,
    this.timestamp,
    this.type = 'text',
    this.metadata,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String currentUserId) {
    DateTime? ts;
    if (json['timestamp'] != null) {
      ts = DateTime.tryParse(json['timestamp']);
    }
    return ChatMessage(
      id: json['id'],
      senderId: json['sender_id'] ?? '',
      content: json['content'] ?? '',
      isMe: json['sender_id'] == currentUserId,
      timestamp: ts,
      type: json['type'] ?? 'text',
      metadata: json['metadata'],
    );
  }
}

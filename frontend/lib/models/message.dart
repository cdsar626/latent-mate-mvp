class ChatMessage {
  final String senderId;
  final String content;
  final bool isMe;

  ChatMessage({required this.senderId, required this.content, required this.isMe});
}

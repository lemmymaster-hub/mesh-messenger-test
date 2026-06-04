class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime time;
  final String? senderName;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
    this.senderName,
  });
}
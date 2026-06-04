import 'dart:convert';

class MeshMessage {
  final String messageId;
  final String senderId;
  final String senderName;
  final String receiverId;
  final String text;
  final int hopCount;
  final int maxHops;
  final int timestamp;

  MeshMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.text,
    required this.hopCount,
    required this.maxHops,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'hopCount': hopCount,
      'maxHops': maxHops,
      'timestamp': timestamp,
    };
  }

  factory MeshMessage.fromJson(Map<String, dynamic> json) {
    return MeshMessage(
      messageId: json['messageId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      receiverId: json['receiverId'] ?? 'ALL',
      text: json['text'] ?? '',
      hopCount: json['hopCount'] ?? 0,
      maxHops: json['maxHops'] ?? 5,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  String encode() {
    return jsonEncode(toJson());
  }

  factory MeshMessage.decode(String data) {
    return MeshMessage.fromJson(
      jsonDecode(data),
    );
  }
}
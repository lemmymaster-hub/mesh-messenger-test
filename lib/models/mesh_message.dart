import 'dart:convert';

class MeshMessage {
  final String messageId;
  final String senderId;
  final String senderName;
  final String receiverId;
  final String text;
  final String type; // group, private, hello, sos, sos_accept, sos_reject, sos_cancel
  final int hopCount;
  final int maxHops;
  final int timestamp;

  final double? latitude;
  final double? longitude;
  final String? sosId;
  final String? sosReason;

  MeshMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.text,
    required this.type,
    required this.hopCount,
    required this.maxHops,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.sosId,
    this.sosReason,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'type': type,
      'hopCount': hopCount,
      'maxHops': maxHops,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'sosId': sosId,
      'sosReason': sosReason,
    };
  }

  factory MeshMessage.fromJson(Map<String, dynamic> json) {
    return MeshMessage(
      messageId: json['messageId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      receiverId: json['receiverId'] ?? 'ALL',
      text: json['text'] ?? '',
      type: json['type'] ?? 'group',
      hopCount: json['hopCount'] ?? 0,
      maxHops: json['maxHops'] ?? 5,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      latitude: json['latitude'] == null
          ? null
          : (json['latitude'] as num).toDouble(),
      longitude: json['longitude'] == null
          ? null
          : (json['longitude'] as num).toDouble(),
      sosId: json['sosId'],
      sosReason: json['sosReason'],
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
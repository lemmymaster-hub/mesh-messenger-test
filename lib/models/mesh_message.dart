import 'dart:convert';

class MeshMessage {
  static const Set<String> supportedTypes = {
    'group',
    'private',
    'hello',
    'location',
    'sos',
    'sos_accept',
    'sos_reject',
    'sos_cancel',
  };

  final String messageId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String receiverId;
  final String text;
  final String type;
  final int hopCount;
  final int maxHops;
  final int timestamp;

  final double? latitude;
  final double? longitude;
  final int? batteryLevel;
  final String? sosId;
  final String? sosReason;

  MeshMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    this.senderRole = 'Volonter',
    required this.receiverId,
    required this.text,
    required this.type,
    required this.hopCount,
    required this.maxHops,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.batteryLevel,
    this.sosId,
    this.sosReason,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'receiverId': receiverId,
      'text': text,
      'type': type,
      'hopCount': hopCount,
      'maxHops': maxHops,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'batteryLevel': batteryLevel,
      'sosId': sosId,
      'sosReason': sosReason,
    };
  }

  MeshMessage copyWith({int? hopCount}) {
    return MeshMessage(
      messageId: messageId,
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      receiverId: receiverId,
      text: text,
      type: type,
      hopCount: hopCount ?? this.hopCount,
      maxHops: maxHops,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      batteryLevel: batteryLevel,
      sosId: sosId,
      sosReason: sosReason,
    );
  }

  static String _asString(dynamic value, {String fallback = ''}) {
    return value is String ? value : fallback;
  }

  static int _asInt(dynamic value, {required int fallback}) {
    return value is num ? value.toInt() : fallback;
  }

  static double? _asDoubleOrNull(dynamic value) {
    return value is num ? value.toDouble() : null;
  }

  static int? _asIntOrNull(dynamic value) {
    return value is num ? value.toInt() : null;
  }

  factory MeshMessage.fromJson(Map<String, dynamic> json) {
    final messageId = _asString(json['messageId']).trim();
    final senderId = _asString(json['senderId']).trim();
    final type = _asString(json['type'], fallback: 'group').trim();
    final hopCount = _asInt(json['hopCount'], fallback: 0);
    final maxHops = _asInt(json['maxHops'], fallback: 5);

    if (messageId.isEmpty) {
      throw const FormatException('Mesh poruka nema messageId.');
    }

    if (senderId.isEmpty) {
      throw const FormatException('Mesh poruka nema senderId.');
    }

    if (!supportedTypes.contains(type)) {
      throw FormatException('Nepoznat tip mesh poruke: $type');
    }

    if (hopCount < 0 || maxHops < 0 || hopCount > maxHops || maxHops > 20) {
      throw const FormatException('Neispravna hop vrijednost mesh poruke.');
    }

    return MeshMessage(
      messageId: messageId,
      senderId: senderId,
      senderName: _asString(json['senderName']),
      senderRole: _asString(json['senderRole'], fallback: 'Volonter'),
      receiverId: _asString(json['receiverId'], fallback: 'ALL'),
      text: _asString(json['text']),
      type: type,
      hopCount: hopCount,
      maxHops: maxHops,
      timestamp: _asInt(
        json['timestamp'],
        fallback: DateTime.now().millisecondsSinceEpoch,
      ),
      latitude: _asDoubleOrNull(json['latitude']),
      longitude: _asDoubleOrNull(json['longitude']),
      batteryLevel: _asIntOrNull(json['batteryLevel']),
      sosId: json['sosId'] is String ? json['sosId'] as String : null,
      sosReason: json['sosReason'] is String
          ? json['sosReason'] as String
          : null,
    );
  }

  String encode() {
    return jsonEncode(toJson());
  }

  factory MeshMessage.decode(String data) {
    final decoded = jsonDecode(data);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Mesh payload nije JSON objekat.');
    }

    return MeshMessage.fromJson(decoded);
  }
}

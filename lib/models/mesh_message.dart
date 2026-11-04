import 'dart:convert';

class MeshMessage {
  static const Set<String> supportedTypes = {
    'group',
    'command',
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

  static int? _optionalInt(Object? value, String field) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value.abs() <= 8640000000000000) {
      return value.toInt();
    }
    throw FormatException('Neispravna vrijednost polja $field.');
  }

  static double? _optionalCoordinate(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw const FormatException('Neispravne GPS koordinate.');
  }

  factory MeshMessage.fromJson(Map<String, dynamic> json) {
    final messageId = _asString(json['messageId']).trim();
    final senderId = _asString(json['senderId']).trim();
    final type = _asString(json['type'], fallback: 'group').trim();
    final hopCount = _optionalInt(json['hopCount'], 'hopCount') ?? 0;
    final maxHops = _optionalInt(json['maxHops'], 'maxHops') ?? 5;

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

    final lat = _optionalCoordinate(json['latitude']);
    final lng = _optionalCoordinate(json['longitude']);
    if ((lat == null) != (lng == null) ||
        (lat != null && (!lat.isFinite || lat.abs() > 90)) ||
        (lng != null && (!lng.isFinite || lng.abs() > 180))) {
      throw const FormatException('Neispravne GPS koordinate.');
    }
    final battery = _optionalInt(json['batteryLevel'], 'batteryLevel');
    if (battery != null && (battery < 0 || battery > 100)) {
      throw const FormatException('Neispravna baterija.');
    }
    final receiverId = _asString(json['receiverId'], fallback: 'ALL').trim();
    if (type == 'private' && (receiverId.isEmpty || receiverId == 'ALL')) {
      throw const FormatException('Privatna mesh poruka nema primaoca.');
    }
    final timestamp =
        _optionalInt(json['timestamp'], 'timestamp') ??
        DateTime.now().millisecondsSinceEpoch;
    if (timestamp < 0 || timestamp > 8640000000000000) {
      throw const FormatException('Neispravno vrijeme mesh poruke.');
    }
    final sosId = _asString(json['sosId']).trim();
    if ((type == 'sos_accept' ||
            type == 'sos_reject' ||
            type == 'sos_cancel') &&
        sosId.isEmpty) {
      throw const FormatException('SOS poruka nema ID incidenta.');
    }
    return MeshMessage(
      messageId: messageId,
      senderId: senderId,
      senderName: _asString(json['senderName']),
      senderRole: _asString(json['senderRole'], fallback: 'Volonter'),
      receiverId: receiverId,
      text: _asString(json['text']),
      type: type,
      hopCount: hopCount,
      maxHops: maxHops,
      timestamp: timestamp,
      latitude: lat,
      longitude: lng,
      batteryLevel: battery,
      sosId: sosId.isEmpty ? null : sosId,
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

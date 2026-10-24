import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_test/models/mesh_message.dart';

void main() {
  test('JPEG envelope stays below legacy Nearby 32 KB bytes limit', () {
    final bytes = List<int>.filled(20000, 0);
    bytes[0] = 0xff;
    bytes[1] = 0xd8;
    final message = MeshMessage(
      messageId: 'photo-message',
      senderId: 'sender',
      senderName: 'Terenski tim',
      receiverId: 'ALL',
      text: jsonEncode({
        'op': 'photo',
        'data': {'id': 'photo', 'bytes': base64Encode(bytes)},
      }),
      type: 'command',
      hopCount: 5,
      maxHops: 5,
      timestamp: 123456789,
    );
    expect(utf8.encode(message.encode()).length, lessThanOrEqualTo(32768));
  });

  test('rejects invalid GPS coordinates and preserves zero battery', () {
    final data = {
      'messageId': 'm',
      'senderId': 'a',
      'type': 'location',
      'latitude': 43.0,
      'longitude': 18.0,
      'batteryLevel': 0,
    };
    expect(MeshMessage.fromJson(data).batteryLevel, 0);
    expect(
      () => MeshMessage.fromJson({...data, 'latitude': 91}),
      throwsFormatException,
    );
    expect(
      () => MeshMessage.fromJson({...data, 'longitude': null}),
      throwsFormatException,
    );
    expect(
      () => MeshMessage.fromJson({...data, 'batteryLevel': 101}),
      throwsFormatException,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_test/models/mesh_message.dart';

void main() {
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

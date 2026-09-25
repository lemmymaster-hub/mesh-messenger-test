import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_test/models/mesh_message.dart';

void main() {
  group('MeshMessage', () {
    test('čuva sva relay, GPS i SOS polja kroz encode/decode', () {
      final original = MeshMessage(
        messageId: 'message-1',
        senderId: 'device-a',
        senderName: 'Mile',
        senderRole: 'Komandant',
        receiverId: 'ALL',
        text: 'SOS test',
        type: 'sos',
        hopCount: 1,
        maxHops: 5,
        timestamp: 123456789,
        latitude: 43.8563,
        longitude: 18.4131,
        batteryLevel: 74,
        sosId: 'sos-1',
        sosReason: 'Test',
      );

      final decoded = MeshMessage.decode(original.encode());

      expect(decoded.messageId, original.messageId);
      expect(decoded.senderId, original.senderId);
      expect(decoded.senderRole, original.senderRole);
      expect(decoded.hopCount, 1);
      expect(decoded.latitude, 43.8563);
      expect(decoded.longitude, 18.4131);
      expect(decoded.batteryLevel, 74);
      expect(decoded.sosId, 'sos-1');
      expect(decoded.sosReason, 'Test');
    });

    test('relay copy povećava hop i ne gubi bateriju ili SOS ID', () {
      final original = MeshMessage(
        messageId: 'message-2',
        senderId: 'device-b',
        senderName: 'Relay korisnik',
        receiverId: 'ALL',
        text: 'LOCATION_UPDATE',
        type: 'location',
        hopCount: 0,
        maxHops: 5,
        timestamp: 123456789,
        latitude: 44.0,
        longitude: 18.0,
        batteryLevel: 51,
        sosId: 'incident-2',
      );

      final relayed = original.copyWith(hopCount: 1);

      expect(relayed.messageId, original.messageId);
      expect(relayed.hopCount, 1);
      expect(relayed.batteryLevel, 51);
      expect(relayed.sosId, 'incident-2');
      expect(relayed.latitude, 44.0);
      expect(relayed.longitude, 18.0);
    });

    test('odbacuje poruku bez identiteta i nepoznat tip', () {
      expect(
        () => MeshMessage.fromJson({
          'messageId': '',
          'senderId': 'device-a',
          'type': 'group',
        }),
        throwsFormatException,
      );

      expect(
        () => MeshMessage.fromJson({
          'messageId': 'message-3',
          'senderId': 'device-a',
          'type': 'remote_command',
        }),
        throwsFormatException,
      );
    });
  });
}

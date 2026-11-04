import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_test/services/nearby_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ba.noria.nrnmesh/transport');

  test('counts only peers whose Nearby submission was accepted', () async {
    final transport = NearbyService()
      ..deviceId = 'sender'
      ..deviceName = 'Komanda'
      ..connectedDevices.addAll({'A': 'Tim A', 'B': 'Tim B'});
    final messenger = binding.defaultBinaryMessenger;
    addTearDown(() {
      transport.connectedDevices.clear();
      transport.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'submitBytes');
      if (call.arguments['endpointId'] == 'B') {
        throw PlatformException(code: 'NEARBY_SEND');
      }
      return null;
    });

    final result = await transport.sendMessage('Provjera veze');
    expect(result!.attemptedCount, 2);
    expect(result.submittedEndpointIds, ['A']);
    expect(result.failedCount, 1);
  });
}

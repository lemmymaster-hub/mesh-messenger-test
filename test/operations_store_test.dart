import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_messenger_test/models/mesh_message.dart';
import 'package:mesh_messenger_test/services/nearby_service.dart';
import 'package:mesh_messenger_test/modules/command_center/services/operations_store.dart';

class TestTransport extends NearbyService {
  TestTransport() {
    deviceId = 'commander';
    deviceName = 'Komanda';
  }
  Map<String, dynamic>? lastCommand;
  @override
  Future<MeshSendResult?> sendCommand(Map<String, dynamic> data) async {
    lastCommand = data;
    return null;
  }

  @override
  void dispose() {
    super.dispose();
  }
}

MeshMessage event(
  String sender,
  String op,
  Map<String, dynamic> data, {
  int time = 100,
}) => MeshMessage(
  messageId: '$sender-$op-$time',
  senderId: sender,
  senderName: sender,
  receiverId: 'ALL',
  text: jsonEncode({'op': op, 'data': data}),
  type: 'command',
  hopCount: 0,
  maxHops: 5,
  timestamp: time,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'offline assignment persists and never claims recipient delivery',
    () async {
      final transport = TestTransport();
      final ops = OperationsStore(transport);
      await ops.ready;
      final result = await ops.publish('team', {
        'id': 't1',
        'name': 'GSS',
        'members': ['a'],
        'color': 0xFF1687FF,
      });
      expect(result, contains('nije poslato'));
      await ops.publish('mission', {
        'id': 'm1',
        'teamId': 't1',
        'members': ['intruder'],
        'task': 'Pretraga',
      });
      expect(ops.missions['m1']!['members'], ['a']);
      await ops.save();
      ops.dispose();
      final restored = OperationsStore(transport);
      await restored.ready;
      expect(restored.teams['t1']!['name'], 'GSS');
      expect(restored.missions['m1']!['task'], 'Pretraga');
      restored.dispose();
    },
  );
  test('only assigned member may report progress and old status cannot replace new', () async {
    final ops = OperationsStore(TestTransport());
    await ops.ready;
    await ops.publish('team', {
      'id': 't1',
      'name': 'GSS',
      'members': ['a'],
    });
    await ops.publish('mission', {
      'id': 'm1',
      'teamId': 't1',
      'task': 'Pretraga',
    });
    ops.receive(
      event('stranger', 'progress', {'id': 'm1', 'status': 'Završeno'}),
    );
    expect(ops.missions['m1']!['progress'], isEmpty);
    ops.receive(
      event('a', 'progress', {'id': 'm1', 'status': 'Na lokaciji'}, time: 200),
    );
    ops.receive(
      event('a', 'progress', {'id': 'm1', 'status': 'Na putu'}, time: 150),
    );
    expect(
      (ops.missions['m1']!['progress'] as Map)['a']['status'],
      'Na lokaciji',
    );
    await ops.save();
    ops.dispose();
  });
  test('cancel affects the correct SOS and requires original sender', () async {
    final ops = OperationsStore(TestTransport());
    await ops.ready;
    ops.syncIncidents({
      's1': {'senderId': 'a', 'status': 'active'},
      's2': {'senderId': 'b', 'status': 'active'},
    });
    MeshMessage cancel(String sender) => MeshMessage(
      messageId: 'cancel-$sender',
      senderId: sender,
      senderName: sender,
      receiverId: 'ALL',
      text: '',
      type: 'sos_cancel',
      hopCount: 0,
      maxHops: 5,
      timestamp: 100,
      sosId: 's1',
    );
    ops.receive(cancel('stranger'));
    expect(ops.incidents['s1']!['status'], 'active');
    ops.receive(cancel('a'));
    expect(ops.incidents['s1']!['status'], 'resolved');
    expect(ops.incidents['s2']!['status'], 'active');
    ops.syncIncidents({
      's1': {'senderId': 'a', 'status': 'active'},
    });
    expect(ops.incidents['s1']!['status'], 'resolved');
    await ops.save();
    ops.dispose();
  });
  test('rejects malformed operational messages without crashing', () async {
    final ops = OperationsStore(TestTransport());
    await ops.ready;
    ops.receive(
      event('a', 'team', {'id': 't1', 'name': 'Broken', 'members': 42}),
    );
    ops.receive(event('a', 'photo', {'id': 'p1', 'bytes': 'not base64'}));
    expect(ops.teams, isEmpty);
    expect(ops.photos, isEmpty);
    ops.dispose();
  });
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_messenger_test/modules/command_center/screens/command_center_screen.dart';
import 'package:mesh_messenger_test/modules/command_center/services/operations_store.dart';
import 'package:mesh_messenger_test/modules/offline_planner/planner_screen.dart';
import '../operations_store_test.dart' show TestTransport;

void main() {
  testWidgets(
    'Reference console opens offline planner with stable-ID ledger data and returns intact',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      await tester.binding.setSurfaceSize(const Size(844, 390));
      final cache = Directory.systemTemp.createTempSync('nrn-bridge-');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => cache.path,
      );
      addTearDown(() async {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        await tester.binding.setSurfaceSize(null);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        cache.deleteSync(recursive: true);
      });
      final mesh = TestTransport();
      final ops = OperationsStore(mesh);
      await ops.ready;
      ops.teams['t1'] = {
        'id': 't1',
        'name': 'Tim Alfa',
        'members': ['a'],
        'owner': 'commander',
      };
      final live = ValueNotifier(0);
      final now = DateTime.now().millisecondsSinceEpoch;
      await tester.pumpWidget(
        MaterialApp(
          home: CommandCenterScreen(
            meshUserLocations: {
              'commander': {'lat': 43.84, 'lng': 18.4, 'time': now},
              'a': {'lat': 43.85, 'lng': 18.41, 'time': now},
            },
            meshSosLocations: {
              's1': {
                'senderId': 'a',
                'lat': 43.86,
                'lng': 18.42,
                'time': now,
                'status': 'active',
              },
            },
            transport: mesh,
            operations: ops,
            live: live,
            batteryLevel: () => 80,
            onSos: () async {},
            onCancelSos: () async {},
            onSosResponded: (_) {},
            onOfflineMaps: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('command-center-overview')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('open-offline-planner')));
      await tester.pumpAndSettle();
      final planner = tester.widget<OfflinePlannerScreen>(
        find.byType(OfflinePlannerScreen),
      );
      expect(planner.meshInput!['hq']['lat'], 43.84);
      expect(planner.meshInput!['incident']['lat'], 43.86);
      expect(planner.meshInput!['teams'][0]['id'], 't1');
      expect(planner.meshInput!['teams'][0]['available'], false);
      expect(planner.meshInput!['teams'][0]['skills'], isEmpty);
      expect(ops.teams['t1']!['members'], ['a']);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('command-center-overview')),
        findsOneWidget,
      );
      expect(find.text('Foto zid'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      ops.dispose();
      live.dispose();
      mesh.dispose();
    },
  );
}

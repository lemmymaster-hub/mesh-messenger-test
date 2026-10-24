import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_messenger_test/modules/command_center/screens/command_center_screen.dart';
import 'package:mesh_messenger_test/modules/command_center/services/operations_store.dart';

import 'operations_store_test.dart' show TestTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(390, 844), const Size(1600, 1000)]) {
    testWidgets(
      'command center is usable at $size and team creation is functional',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(size);
        final transport = TestTransport();
        final ops = OperationsStore(transport);
        await ops.ready;
        final live = ValueNotifier(0);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: CommandCenterScreen(
              meshUserLocations: const {},
              meshSosLocations: const {},
              transport: transport,
              operations: ops,
              live: live,
              batteryLevel: () => 0,
              onSos: () async {},
              onCancelSos: () async {},
              onOfflineMaps: () {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        if (size.width < 1200) {
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Timovi').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Formiraj tim'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Tim ALFA');
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Formiraj'));
        await tester.pumpAndSettle();
        expect(ops.teams.values.single['name'], 'Tim ALFA');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        ops.dispose();
        live.dispose();
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
}

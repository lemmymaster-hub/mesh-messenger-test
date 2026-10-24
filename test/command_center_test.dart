import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_messenger_test/modules/command_center/screens/command_center_screen.dart';
import 'package:mesh_messenger_test/modules/command_center/services/operations_store.dart';

import 'operations_store_test.dart' show TestTransport;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final cache = Directory.systemTemp.createTempSync('nrn-widget-test-');
  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => cache.path,
    );
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final fontFile = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (fontFile.existsSync()) {
      final loader = FontLoader('ReviewSans')
        ..addFont(
          Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
        );
      await loader.load();
    }
  });
  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    cache.deleteSync(recursive: true);
  });
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
        final screenshotKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme:
                ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF1687FF),
                    brightness: Brightness.dark,
                  ),
                ).copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: 'ReviewSans',
                  ),
                ),
            home: RepaintBoundary(
              key: screenshotKey,
              child: CommandCenterScreen(
                meshUserLocations: const {},
                meshSosLocations: const {},
                transport: transport,
                operations: ops,
                live: live,
                batteryLevel: () => 0,
                onSosResponded: (_) {},
                onSos: () async {},
                onCancelSos: () async {},
                onOfflineMaps: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'test-output/command-center-${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
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

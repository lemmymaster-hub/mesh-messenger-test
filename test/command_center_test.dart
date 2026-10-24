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
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(() {
          tester.view.resetViewInsets();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
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
  for (final spec in [
    (const Size(320, 640), 1.0),
    (const Size(360, 740), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(844, 390), 1.0),
    (const Size(360, 740), 1.4),
  ]) {
    testWidgets('phone navigation and keyboard fit ${spec.$1} scale ${spec.$2}', (
      tester,
    ) async {
      final size = spec.$1;
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(size);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final transport = TestTransport()..knownDevices['a'] = 'Vatrogasac 1';
      final ops = OperationsStore(transport);
      await ops.ready;
      ops.teams['test-team'] = {
        'id': 'test-team',
        'name': 'Tim ALFA',
        'owner': 'commander',
        'members': ['commander', 'a'],
      };
      ops.missions['test-mission'] = {
        'id': 'test-mission',
        'teamId': 'test-team',
        'owner': 'commander',
        'task':
            'Provjera pristupa ugroženom području i izvještaj komandnom centru',
        'members': ['commander', 'a'],
        'progress': <String, dynamic>{},
      };
      ops.syncIncidents({
        'test-sos': {
          'senderId': 'a',
          'sender': 'Vatrogasac 1',
          'status': 'active',
          'message':
              'Potreban dodatni tim na terenu. Provjeriti pristup lokaciji.',
          'lat': 43.85,
          'lng': 18.38,
          'time': DateTime.now().millisecondsSinceEpoch,
        },
      });
      await ops.recordOutgoing('Ekipa je krenula prema lokaciji.', null);
      final live = ValueNotifier(0);
      final captureKey = GlobalKey();
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(spec.$2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: captureKey,
            child: CommandCenterScreen(
              meshUserLocations: const {},
              meshSosLocations: const {},
              transport: transport,
              operations: ops,
              live: live,
              batteryLevel: () => 74,
              onSosResponded: (_) {},
              onSos: () async {},
              onCancelSos: () async {},
              onOfflineMaps: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('command-center-overview')), findsOneWidget);
      expect(find.text('Foto zid'), findsWidgets);
      expect(tester.takeException(), isNull);
      Future<void> capture(String tab) async {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'test-output/phone-${size.width.toInt()}-${size.height.toInt()}-${spec.$2}-$tab.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('overview');
      for (final tab in ['Situacijska mapa', 'SOS centar', 'Dispatch centar', 'Komunikacije', 'Postavke', 'Dashboard']) {
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Console $tab at $size');
        if (tab == 'Komunikacije') {
          await tester.tap(find.byType(TextField).first);
          await tester.pumpAndSettle();
          expect(find.text('Broadcast poruka'), findsOneWidget);
          await tester.enterText(find.byType(TextField).last, 'Terenski izvještaj');
          tester.view.viewInsets = const FakeViewPadding(bottom: 160);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Message composer with keyboard at $size');
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Nazad'));
          await tester.pumpAndSettle();
        }
      }
      expect(find.byTooltip('Nazad u chat'), findsOneWidget);
      expect(find.text('OFFLINE MAPE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      ops.dispose();
      live.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }
}

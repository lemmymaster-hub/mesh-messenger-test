import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_messenger_test/screens/map/mesh_map_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final cache = Directory.systemTemp.createTempSync('nrn-offline-review-');
  setUpAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => cache.path,
    );
  });
  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null,
    );
    cache.deleteSync(recursive: true);
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('offline download is visible and opens at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const MeshMapScreen(meshUserLocations: {}, meshSosLocations: {}),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('download-offline-area')));
      await tester.pumpAndSettle();
      expect(find.text('Preuzmi područje mape'), findsOneWidget);
      expect(find.text('Preuzmi'), findsOneWidget);
      await tester.tap(find.text('Otkaži'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('saved tiles use the local image without a network provider', () async {
    final file = File('${cache.path}/13/4520/2980.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([137, 80, 78, 71]);
    final image = BslOfflineTileProvider(cache.path).getImage(
      TileCoordinates(4520, 2980, 13), TileLayer(),
    );
    expect(image, isA<FileImage>());
    expect((image as FileImage).file.path, file.path);
  });
}

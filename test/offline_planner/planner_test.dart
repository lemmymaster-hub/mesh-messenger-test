import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_messenger_test/modules/offline_planner/planner_engine.dart';
import 'package:mesh_messenger_test/modules/offline_planner/planner_scenario.dart';
import 'package:mesh_messenger_test/modules/offline_planner/planner_screen.dart';
import 'package:mesh_messenger_test/modules/offline_planner/planner_store.dart';

import 'engine_checks.dart' as engine_checks;

void main() {
  test('Offline engine invariants', engine_checks.main);

  test('Local store round-trips the full plan and approval', () async {
    SharedPreferences.setMockInitialValues({});
    final input = demoScenario();
    final state = {
      'input': jsonEncode(input),
      'plan': PlannerEngine().plan(input),
      'approval': null,
      'reports': <Json>[],
      'audit': <Json>[],
    };
    await PlannerStore().save(state);
    expect(await PlannerStore().load(), state);
  });

  testWidgets('Commander can generate an offline draft from the input screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: OfflinePlannerScreen(meshInput: demoScenario())),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Izradi offline prijedlog'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Izradi offline prijedlog'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if ((await PlannerStore().load())?['plan'] != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('NACRT — čeka pregled komandira'),
      findsOneWidget,
    );
    final saved = await PlannerStore().load();
    expect(saved!['plan']['network']['status'], 'estimated');
    expect(saved['approval'], isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Commander approval persists and changed inputs invalidate it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final input = demoScenario();
    final plan = PlannerEngine().plan(input);
    SharedPreferences.setMockInitialValues({
      PlannerStore.key: jsonEncode({
        'input': jsonEncode(input),
        'plan': plan,
        'approval': null,
        'reports': <Json>[],
        'audit': <Json>[],
      }),
    });
    await tester.pumpWidget(const MaterialApp(home: OfflinePlannerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prijedlog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pregledano — odobri prijedlog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Test komandir');
    await tester.tap(find.text('Odobri prijedlog'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ODOBREN PRIJEDLOG'), findsOneWidget);
    final saved = await PlannerStore().load();
    expect(saved!['approval']['commander'], 'Test komandir');
    await tester.tap(find.text('Unos'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Uredi akciju i pragove'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uredi akciju i pragove'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Izmijenjena akcija',
    );
    await tester.tap(find.text('Primijeni unos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prijedlog'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ZASTARJEO'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

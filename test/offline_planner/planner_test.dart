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

  testWidgets('Commander approval persists and changed inputs invalidate it', (
    tester,
  ) async {
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
    await tester.ensureVisible(find.text('Uredi akciju i pragove'));
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

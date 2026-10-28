// Standalone, no pub packages or network. Run: dart test/offline_planner/engine_checks.dart
// These imports and console output keep this executable usable without pub.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:convert';

import '../../lib/modules/offline_planner/planner_engine.dart';
import '../../lib/modules/offline_planner/planner_scenario.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void rejects(void Function() fn, String message) {
  try {
    fn();
  } on FormatException {
    return;
  }
  throw StateError(message);
}

void main() {
  final engine = PlannerEngine();
  var tests = 0;
  void test(String name, void Function() body) {
    body();
    tests++;
    print('PASS $name');
  }

  test('Missing operational equipment/coordinates rejected', () {
    rejects(() => engine.plan(emptyScenario()), 'Incomplete input must fail');
  });
  test('Terrain blocks direct link and station provides path', () {
    final p = engine.plan(demoScenario());
    final network = p['network'] as Json;
    check(network['status'] == 'estimated', 'Ground path');
    check((network['path'] as List).length == 3, 'One relay');
    final direct = (network['links'] as List).firstWhere(
      (l) => l['from'] == 'stab' && l['to'] == 'incident',
    );
    check(direct['status'] == 'blocked', 'Ridge obstruction');
    check(p['airRelay']['status'] == 'notRequired', 'No unnecessary flight');
  });
  test('Missing profiles never create links', () {
    final s = demoScenario()..['profiles'] = <Json>[];
    final p = engine.plan(s);
    check(p['network']['status'] == 'unresolved', 'Unknown ground');
    check(p['airRelay']['status'] == 'unavailable', 'Unknown air');
    check(
      (p['network']['links'] as List).every((l) => l['status'] == 'unknown'),
      'No guessed links',
    );
  });
  test('Unknown endpoint altitude is not zero', () {
    final s = demoScenario();
    s['hq']['elevationM'] = null;
    final p = engine.plan(s);
    check(p['network']['status'] == 'unresolved', 'Unknown HQ');
  });
  test('Station inventory enforced; air height has AGL and AMSL', () {
    final s = demoScenario()..['stationLimit'] = 0;
    final p = engine.plan(s);
    check(p['network']['status'] == 'unresolved', 'No available ground relays');
    check(p['airRelay']['status'] == 'estimated', 'Air path');
    check(
      p['airRelay']['amslM'] == 620 + p['airRelay']['aglM'],
      'Altitude reference',
    );
  });
  test('Battery reserve/transit and flight confirmation enforced', () {
    final s = demoScenario()..['stationLimit'] = 0;
    s['drone']['enduranceMinutes'] = 20;
    check(
      engine.plan(s)['airRelay']['status'] == 'unavailable',
      'Reserve consumed',
    );
    s['drone']['enduranceMinutes'] = 35;
    s['drone']['conditionsConfirmed'] = false;
    check(
      engine.plan(s)['airRelay']['status'] == 'unavailable',
      'Unconfirmed flight',
    );
  });
  test('Inaccessible stations cannot be selected', () {
    final s = demoScenario();
    s['stations'][0]['accessible'] = false;
    check(
      engine.plan(s)['network']['status'] == 'unresolved',
      'Inaccessible site',
    );
  });
  test('Assignments enforce skills and no double booking', () {
    final s = demoScenario();
    final p = engine.plan(s);
    final a = (p['assignments'] as List).cast<Json>();
    check(
      a.length == 2 && a.map((e) => e['teamId']).toSet().length == 2,
      'Unique teams',
    );
    s['teams'][0]['available'] = false;
    check(
      (engine.plan(s)['unassigned'] as List).length == 1,
      'Unavailable specialist',
    );
    s['teams'][0]['available'] = true;
    s['tasks'][0]['routeConfirmed'] = false;
    check((engine.plan(s)['unassigned'] as List).length == 1, 'Unknown route');
  });
  test('Optimizer preserves specialist for constrained task', () {
    final s = demoScenario();
    s['teams'][0]['skills'] = ['prva_pomoc', 'radio'];
    s['teams'][1]['skills'] = ['radio'];
    final tasks = s['tasks'] as List;
    s['tasks'] = tasks.reversed.toList();
    final a = engine.plan(s)['assignments'] as List;
    check(a.length == 2, 'Do not greedily consume specialist');
    check(
      a.firstWhere((a) => a['taskId'] == 'pomoc')['teamId'] == 'alfa',
      'Correct specialist',
    );
  });
  test('High priority wins when only one team is available', () {
    final s = demoScenario();
    s['teams'][0]['skills'] = ['prva_pomoc', 'radio'];
    s['teams'][1]['available'] = false;
    final a = engine.plan(s)['assignments'] as List;
    check(a.length == 1 && a.first['taskId'] == 'pomoc', 'Priority objective');
  });
  test('Duplicate ids, invalid coordinates/profiles rejected', () {
    final s = demoScenario();
    s['incident']['id'] = 'stab';
    rejects(() => engine.plan(s), 'duplicate ID');
    final b = demoScenario();
    b['hq']['lat'] = 91;
    rejects(() => engine.plan(b), 'bad latitude');
    final c = demoScenario();
    c['profiles'][0]['samples'] = [600, 'bad', 600];
    rejects(() => engine.plan(c), 'bad sample');
  });
  test('Reverse terrain profiles give reciprocal results', () {
    final s = demoScenario();
    final a = s['hq'] as Json, b = s['stations'][0] as Json;
    final f = engine.link(
      a,
      b,
      s['radio'],
      (s['profiles'] as List).cast<Json>(),
    );
    final r = engine.link(
      b,
      a,
      s['radio'],
      (s['profiles'] as List).cast<Json>(),
    );
    check(f['status'] == r['status'], 'Reciprocity');
    check(
      (f['clearanceM'] - r['clearanceM']).abs() < 0.00001,
      'Reverse samples',
    );
  });
  test('Monitoring uses newest report, stale and absent remain explicit', () {
    final s = demoScenario(), p = engine.plan(demoScenario());
    final now = DateTime.utc(2026, 10, 28, 10);
    final reports = <Json>[
      {
        'teamId': 'alfa',
        'at': now.subtract(const Duration(minutes: 20)).toIso8601String(),
        'battery': 10,
        'status': 'help',
      },
      {
        'teamId': 'alfa',
        'at': now.toIso8601String(),
        'battery': 80,
        'status': 'ok',
      },
    ];
    final alerts = engine.monitor(s, p, reports, now);
    check(
      alerts.length == 1 && alerts.first['teamId'] == 'bravo',
      'Newest report only',
    );
    reports.removeLast();
    check(
      engine.monitor(s, p, reports, now).length == 4,
      'stale+battery+help+missing',
    );
  });
  test('Snapshot ignores key order but changes invalidate approval', () {
    check(
      PlannerEngine.snapshot({'b': 2, 'a': 1}) ==
          PlannerEngine.snapshot({'a': 1, 'b': 2}),
      'Canonical',
    );
    final s = demoScenario(), p = engine.plan(demoScenario());
    check(p['inputSnapshot'] == PlannerEngine.snapshot(s), 'Same input');
    s['stationLimit'] = 0;
    check(p['inputSnapshot'] != PlannerEngine.snapshot(s), 'Changed input');
    check(jsonDecode(jsonEncode(p))['version'] == 1, 'Serializable');
  });
  print('$tests offline engine checks passed.');
}

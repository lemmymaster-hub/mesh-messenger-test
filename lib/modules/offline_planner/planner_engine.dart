import 'dart:convert';
import 'dart:math' as math;

typedef Json = Map<String, dynamic>;

/// Offline symbolic decision support. No HTTP, model download or flight control.
class PlannerEngine {
  static double number(Json j, String key, {double? min, double? max}) {
    final v = j[key];
    if (v is! num ||
        !v.isFinite ||
        (min != null && v < min) ||
        (max != null && v > max)) {
      throw FormatException('Neispravno polje: $key');
    }
    return v.toDouble();
  }

  static Json object(dynamic v) {
    if (v is! Map<String, dynamic>) {
      throw const FormatException('Očekivan objekat.');
    }
    return v;
  }

  static List<Json> objects(dynamic v) {
    if (v is! List || v.length > 100) {
      throw const FormatException('Očekivana lista sa najviše 100 elemenata.');
    }
    return v.map(object).toList();
  }

  static String text(Json j, String key) {
    final v = j[key];
    if (v is! String || v.trim().isEmpty || v.length > 500) {
      throw FormatException('Obavezno tekstualno polje: $key');
    }
    return v;
  }

  static void point(Json p) {
    number(p, 'lat', min: -90, max: 90);
    number(p, 'lng', min: -180, max: 180);
    if (p['elevationM'] != null) number(p, 'elevationM', min: -500, max: 9000);
  }

  static double distance(Json a, Json b) {
    final p = math.pi / 180;
    final dLat = (number(b, 'lat') - number(a, 'lat')) * p;
    final dLng = (number(b, 'lng') - number(a, 'lng')) * p;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(number(a, 'lat') * p) *
            math.cos(number(b, 'lat') * p) *
            math.pow(math.sin(dLng / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
  }

  /// Canonical full snapshot; stored with approval, not a lossy hash.
  static String snapshot(dynamic value) {
    dynamic canonical(dynamic v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: canonical(v[k])};
      }
      if (v is List) return v.map(canonical).toList();
      return v;
    }

    return jsonEncode(canonical(value));
  }

  void validate(Json s) {
    if (s['schemaVersion'] != 1) {
      throw const FormatException('Nepodržana verzija.');
    }
    text(s, 'mission');
    final hq = object(s['hq']);
    final incident = object(s['incident']);
    final sites = objects(s['stations']);
    final air = objects(s['airSites']);
    if (sites.length > 20 || air.length > 20) {
      throw const FormatException(
        'Najviše 20 kandidata stanica i vazdušnih položaja.',
      );
    }
    final ids = <String>{};
    for (final n in [hq, incident, ...sites, ...air]) {
      point(n);
      final id = text(n, 'id');
      if (!ids.add(id)) throw FormatException('Dupli ID lokacije: $id');
      number(n, 'antennaM', min: 0, max: 1000);
    }
    for (final n in [...sites, ...air]) {
      if (n['accessible'] is! bool) {
        throw const FormatException('Nedostaje accessible.');
      }
    }
    number(s, 'stationLimit', min: 0, max: 20);
    if (s['stationLimit'] != (s['stationLimit'] as num).round()) {
      throw const FormatException('Broj stanica mora biti cijeli broj.');
    }
    final rf = object(s['radio']);
    number(rf, 'frequencyMHz', min: 100, max: 6000);
    number(rf, 'txDbm', min: -30, max: 50);
    number(rf, 'sensitivityDbm', min: -160, max: -20);
    number(rf, 'gainDbi', min: -20, max: 40);
    number(rf, 'lossDb', min: 0, max: 100);
    number(rf, 'requiredMarginDb', min: 0, max: 60);
    final pairIds = <String>{};
    for (final p in objects(s['profiles'])) {
      final from = text(p, 'from');
      final to = text(p, 'to');
      final pair = [from, to]..sort();
      if (!ids.contains(from) ||
          !ids.contains(to) ||
          from == to ||
          !pairIds.add(pair.join('|'))) {
        throw const FormatException('Neispravan ili dupli par profila.');
      }
      text(p, 'source');
      final samples = p['samples'];
      if (samples is! List || samples.length < 3 || samples.length > 20000) {
        throw const FormatException('Profil mora imati 3–20000 uzoraka.');
      }
      for (final sample in samples) {
        if (sample is! num ||
            !sample.isFinite ||
            sample < -500 ||
            sample > 9000) {
          throw const FormatException('Neispravna visina u profilu.');
        }
      }
    }
    final teams = objects(s['teams']);
    final tasks = objects(s['tasks']);
    if (teams.length > 12 || tasks.length > 12) {
      throw const FormatException(
        'Prva verzija podržava do 12 timova i zadataka.',
      );
    }
    for (final list in [teams, tasks]) {
      final seen = <String>{};
      for (final item in list) {
        if (!seen.add(text(item, 'id'))) {
          throw const FormatException('Dupli ID tima/zadatka.');
        }
        text(item, 'name');
        point(item);
      }
    }
    for (final team in teams) {
      _strings(team['skills']);
      if (team['available'] is! bool) {
        throw const FormatException('Nedostaje available.');
      }
    }
    for (final task in tasks) {
      _strings(task['requires']);
      number(task, 'priority', min: 1, max: 5);
      if (task['routeConfirmed'] is! bool) {
        throw const FormatException('Nedostaje routeConfirmed.');
      }
    }
    final drone = object(s['drone']);
    number(drone, 'minAglM', min: 1, max: 1000);
    number(drone, 'maxAglM', min: 1, max: 1000);
    number(drone, 'stepM', min: 1, max: 1000);
    if (drone['minAglM'] > drone['maxAglM']) {
      throw const FormatException('Neispravan raspon AGL.');
    }
    if ((drone['maxAglM'] - drone['minAglM']) / drone['stepM'] > 100) {
      throw const FormatException(
        'Najviše 101 kandidat visine. Povećajte stepM.',
      );
    }
    number(drone, 'enduranceMinutes', min: 0, max: 1440);
    number(drone, 'transitMinutes', min: 0, max: 1440);
    number(drone, 'reserveMinutes', min: 0, max: 1440);
    number(drone, 'requiredMinutes', min: 1, max: 1440);
    if (drone['conditionsConfirmed'] is! bool) {
      throw const FormatException('Nedostaje conditionsConfirmed.');
    }
    number(s, 'reportTimeoutMinutes', min: 1, max: 1440);
    number(s, 'batteryAlertPercent', min: 1, max: 100);
  }

  static List<String> _strings(dynamic value) {
    if (value is! List || value.any((e) => e is! String || e.isEmpty)) {
      throw const FormatException('Očekivana lista sposobnosti.');
    }
    return value.cast<String>();
  }

  /// Screening only: reciprocal radio, FSPL + sampled terrain/Fresnel clearance.
  /// Never marks missing terrain as a usable link.
  Json link(Json a, Json b, Json radio, List<Json> profiles) {
    final base = <String, dynamic>{'from': a['id'], 'to': b['id']};
    Json unknown(String reason) => {
      ...base,
      'status': 'unknown',
      'reason': reason,
    };
    if (a['elevationM'] == null || b['elevationM'] == null) {
      return unknown('Nedostaje nadmorska visina krajnje tačke.');
    }
    final matches = profiles.where(
      (p) =>
          (p['from'] == a['id'] && p['to'] == b['id']) ||
          (p['to'] == a['id'] && p['from'] == b['id']),
    );
    if (matches.isEmpty) return unknown('Nedostaje profil terena i prepreka.');
    final profile = matches.first;
    final original = (profile['samples'] as List).cast<num>();
    final samples = profile['from'] == a['id']
        ? original
        : original.reversed.toList();
    if ((samples.first - a['elevationM']).abs() > 5 ||
        (samples.last - b['elevationM']).abs() > 5) {
      return unknown('Krajevi profila ne odgovaraju visinama lokacija.');
    }
    final d = math.max(1.0, distance(a, b));
    final wavelength = 299.792458 / number(radio, 'frequencyMHz');
    final start = number(a, 'elevationM') + number(a, 'antennaM');
    final end = number(b, 'elevationM') + number(b, 'antennaM');
    var clearance = double.infinity;
    for (var i = 1; i < samples.length - 1; i++) {
      final t = i / (samples.length - 1);
      final d1 = d * t;
      final d2 = d - d1;
      final fresnel = math.sqrt(wavelength * d1 * d2 / d);
      final curvature = d1 * d2 / (2 * 6371000 * 4 / 3);
      clearance = math.min(
        clearance,
        start + (end - start) * t - samples[i] - curvature - 0.6 * fresnel,
      );
    }
    final fspl =
        32.44 +
        20 * math.log(d / 1000) / math.ln10 +
        20 * math.log(number(radio, 'frequencyMHz')) / math.ln10;
    final margin =
        number(radio, 'txDbm') +
        2 * number(radio, 'gainDbi') -
        number(radio, 'lossDb') -
        fspl -
        number(radio, 'sensitivityDbm');
    final usable =
        clearance >= 0 && margin >= number(radio, 'requiredMarginDb');
    return {
      ...base,
      'status': usable ? 'estimated' : 'blocked',
      'distanceM': d,
      'marginDb': margin,
      'clearanceM': clearance,
      'profileSource': profile['source'],
      'reason': clearance < 0
          ? 'Teren/prepreka zadire u traženu Fresnel zonu.'
          : usable
          ? 'Model prolazi; potrebna terenska provjera.'
          : 'Nedovoljna rezerva radio-veze.',
    };
  }

  List<Json>? _path(
    List<Json> nodes,
    List<Json> links,
    int limit,
    String target,
  ) {
    final byId = {for (final n in nodes) n['id'] as String: n};
    final queue = <List<String>>[
      [nodes.first['id'] as String],
    ];
    final visited = <String>{'${nodes.first['id']}:0'};
    for (var i = 0; i < queue.length; i++) {
      final path = queue[i];
      if (path.last == target) return path.map((id) => byId[id]!).toList();
      for (final edge in links.where((l) => l['status'] == 'estimated')) {
        final next = edge['from'] == path.last
            ? edge['to']
            : edge['to'] == path.last
            ? edge['from']
            : null;
        if (next is! String || path.contains(next)) continue;
        final candidate = [...path, next];
        final stations = candidate
            .where((id) => byId[id]!['kind'] == 'station')
            .length;
        if (stations > limit || !visited.add('$next:$stations')) continue;
        queue.add(candidate);
      }
    }
    return null;
  }

  Json plan(Json scenario, {DateTime? now}) {
    validate(scenario);
    final s = object(jsonDecode(jsonEncode(scenario)));
    final hq = {...object(s['hq']), 'kind': 'hq'};
    final incident = {...object(s['incident']), 'kind': 'incident'};
    final stations = objects(s['stations'])
        .where((n) => n['accessible'] == true)
        .map((n) => {...n, 'kind': 'station'})
        .toList();
    final nodes = [hq, ...stations, incident];
    final radio = object(s['radio']);
    final profiles = objects(s['profiles']);
    final links = <Json>[];
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        links.add(link(nodes[i], nodes[j], radio, profiles));
      }
    }
    final path = _path(
      nodes,
      links,
      (s['stationLimit'] as num).toInt(),
      incident['id'],
    );
    final drone = object(s['drone']);
    final usableMinutes =
        number(drone, 'enduranceMinutes') -
        number(drone, 'transitMinutes') -
        number(drone, 'reserveMinutes');
    Json airPlan = {
      'status': 'unavailable',
      'reason': 'Nema izvodljivog kandidata sa unesenim podacima.',
    };
    // Ascending AGL gives the lowest model-feasible height among supplied sites.
    for (
      double agl = number(drone, 'minAglM');
      agl <= number(drone, 'maxAglM');
      agl += number(drone, 'stepM')
    ) {
      if (drone['conditionsConfirmed'] != true ||
          usableMinutes < number(drone, 'requiredMinutes')) {
        break;
      }
      for (final site in objects(
        s['airSites'],
      ).where((n) => n['accessible'] == true)) {
        final airborne = {...site, 'antennaM': agl, 'kind': 'air'};
        final airLinks = [
          ...links,
          for (final node in nodes) link(node, airborne, radio, profiles),
        ];
        final airPath = _path(
          [hq, ...stations, airborne, incident],
          airLinks,
          (s['stationLimit'] as num).toInt(),
          incident['id'],
        );
        if (airPath != null && airPath.any((n) => n['kind'] == 'air')) {
          airPlan = {
            'status': 'estimated',
            'site': airborne,
            'aglM': agl,
            'amslM': number(site, 'elevationM') + agl,
            'availableMinutes': usableMinutes,
            'path': airPath,
            'reason':
                'Najniža ispitana AGL visina među unesenim kandidatima; nije nalog za let.',
          };
          break;
        }
      }
      if (airPlan['status'] == 'estimated') break;
    }
    if (path != null) {
      airPlan = {
        'status': 'notRequired',
        'reason':
            'Zemaljska putanja prolazi model; vazdušni relej nije potreban za ovu vezu.',
      };
    }
    if (path == null && drone['conditionsConfirmed'] != true) {
      airPlan['reason'] = 'Komandir nije potvrdio uslove i ograničenja leta.';
    } else if (path == null &&
        usableMinutes < number(drone, 'requiredMinutes')) {
      airPlan['reason'] =
          'Nedovoljno trajanje nakon odlaska, povratka i rezerve.';
    }
    final assignments = _assign(objects(s['teams']), objects(s['tasks']));
    final pending = objects(s['tasks'])
        .where((t) => !assignments.any((a) => a['taskId'] == t['id']))
        .map(
          (t) => {
            'taskId': t['id'],
            'name': t['name'],
            'reason': t['routeConfirmed'] != true
                ? 'Pristupna ruta nije potvrđena.'
                : 'Nema slobodnog tima sa svim potrebnim sposobnostima.',
          },
        )
        .toList();
    final warnings = <String>[
      'Procjena, ne izmjerena pokrivenost. Nije potvrđena operativna spremnost.',
      'Radio model koristi jednake profile opreme, slobodni prostor i uzorkovane prepreke; ne modelira smetnje, difrakciju ni kapacitet mreže.',
      'Putanja mreže povezuje štab i incident; ne predstavlja mapu pokrivenosti svih timova.',
      if (links.any((l) => l['status'] == 'unknown'))
        'Za dio veza nedostaju pouzdani profili/visine.',
      if (pending.isNotEmpty) 'Postoje neraspoređeni zadaci.',
      'Udaljenosti timova su vazdušne; nisu dužina prohodne rute niti vrijeme dolaska.',
    ];
    final selected = path ?? (airPlan['path'] as List?)?.cast<Json>();
    return {
      'version': 1,
      'mission': s['mission'],
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'inputSnapshot': snapshot(s),
      'network': {
        'status': path == null ? 'unresolved' : 'estimated',
        'path': path ?? <Json>[],
        'links': links,
      },
      'airRelay': airPlan,
      'assignments': assignments,
      'unassigned': pending,
      'warnings': warnings,
      'steps': <String>[
        'Potvrditi lokaciju incidenta, pristupne rute, opremu i raspoloživost timova.',
        if (selected != null)
          'Provjeriti komunikacionu putanju: ${selected.map((n) => n['id']).join(' → ')}.'
        else
          'Veza štab–incident nije riješena. Dopuniti profile ili kandidatske lokacije.',
        'Izmjeriti veze i potvrditi komunikaciju prije angažovanja zavisnih zadataka.',
        ...assignments.map(
          (a) => 'Prijedlog: ${a['teamName']} → ${a['taskName']}.',
        ),
        'Komandir provjerava i odobrava verziju plana; slanje naredbi je odvojeno.',
        'Pratiti izvještaje, baterije i prekide veze; izmjene zahtijevaju novo odobrenje.',
      ],
    };
  }

  /// Bounded dynamic programming: maximize priority served, then minimize
  /// straight-line distance. One team per task, one task per team.
  List<Json> _assign(List<Json> teams, List<Json> tasks) {
    final available = teams.where((t) => t['available'] == true).toList();
    final memo =
        <String, ({double score, double distance, List<Json> items})>{};
    ({double score, double distance, List<Json> items}) solve(int i, int mask) {
      if (i == tasks.length) return (score: 0, distance: 0, items: []);
      final key = '$i:$mask';
      if (memo.containsKey(key)) return memo[key]!;
      final task = tasks[i];
      var best = solve(i + 1, mask);
      if (task['routeConfirmed'] == true) {
        for (var j = 0; j < available.length; j++) {
          final team = available[j];
          if (mask & (1 << j) != 0 ||
              !_strings(
                task['requires'],
              ).every(_strings(team['skills']).contains)) {
            continue;
          }
          final tail = solve(i + 1, mask | (1 << j));
          final d = distance(team, task);
          final score = tail.score + number(task, 'priority');
          if (score > best.score ||
              (score == best.score && tail.distance + d < best.distance)) {
            best = (
              score: score,
              distance: tail.distance + d,
              items: [
                {
                  'teamId': team['id'],
                  'teamName': team['name'],
                  'taskId': task['id'],
                  'taskName': task['name'],
                  'straightLineM': d,
                  'priority': task['priority'],
                },
                ...tail.items,
              ],
            );
          }
        }
      }
      memo[key] = best;
      return best;
    }

    return solve(0, 0).items;
  }

  List<Json> monitor(
    Json scenario,
    Json plan,
    List<Json> reports,
    DateTime now,
  ) {
    validate(scenario);
    final alerts = <Json>[];
    for (final assignment in (plan['assignments'] as List).cast<Json>()) {
      final id = assignment['teamId'];
      final matching = reports.where((r) => r['teamId'] == id).toList()
        ..sort(
          (a, b) => DateTime.parse(b['at']).compareTo(DateTime.parse(a['at'])),
        );
      if (matching.isEmpty) {
        alerts.add({
          'teamId': id,
          'message': 'Nema izvještaja; stanje je nepoznato.',
        });
        continue;
      }
      final r = matching.first;
      final at = DateTime.parse(r['at']);
      final minutes = now.difference(at).inSeconds / 60;
      if (minutes < -1) {
        alerts.add({
          'teamId': id,
          'message': 'Vrijeme izvještaja je u budućnosti; provjeriti sat.',
        });
      }
      if (minutes > number(scenario, 'reportTimeoutMinutes')) {
        alerts.add({
          'teamId': id,
          'message':
              'Izvještaj kasni; ne znači automatski da je tim u opasnosti.',
        });
      }
      if (r['battery'] is num &&
          r['battery'] >= 0 &&
          r['battery'] < number(scenario, 'batteryAlertPercent')) {
        alerts.add({
          'teamId': id,
          'message': 'Prijavljena niska baterija: ${r['battery']}%.',
        });
      }
      if (r['status'] == 'blocked' || r['status'] == 'help') {
        alerts.add({
          'teamId': id,
          'message':
              'Tim prijavljuje: ${r['status']}. Komandir treba da procijeni izmjenu plana.',
        });
      }
    }
    return alerts;
  }
}

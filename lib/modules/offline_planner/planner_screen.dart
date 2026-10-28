import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'planner_engine.dart';
import 'planner_scenario.dart';
import 'planner_store.dart';

Json _buildPlan(Json input) => PlannerEngine().plan(input);

class OfflinePlannerScreen extends StatefulWidget {
  final Json? meshInput;
  const OfflinePlannerScreen({super.key, this.meshInput});

  @override
  State<OfflinePlannerScreen> createState() => _OfflinePlannerScreenState();
}

class _OfflinePlannerScreenState extends State<OfflinePlannerScreen> {
  final _engine = PlannerEngine();
  final _store = PlannerStore();
  final _editor = TextEditingController();
  final _commander = TextEditingController();
  final _note = TextEditingController();
  final _battery = TextEditingController();
  Json? _plan;
  Json? _approval;
  List<Json> _reports = [];
  List<Json> _audit = [];
  String? _teamId;
  String _reportStatus = 'ok';
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _planning = false;
  int _tab = 0;
  Timer? _clock;
  static const _pretty = JsonEncoder.withIndent('  ');

  @override
  void initState() {
    super.initState();
    _editor.text = _pretty.convert(widget.meshInput ?? emptyScenario());
    _load();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    try {
      final state = await _store.load();
      if (!mounted) return;
      if (state != null) {
        _editor.text = state['input'] as String;
        _plan = state['plan'] == null
            ? null
            : PlannerEngine.object(state['plan']);
        _approval = state['approval'] == null
            ? null
            : PlannerEngine.object(state['approval']);
        _reports = (state['reports'] as List)
            .map(PlannerEngine.object)
            .toList();
        _audit = (state['audit'] as List).map(PlannerEngine.object).toList();
      }
    } catch (_) {
      _error =
          'Učitavanje sačuvanog plana nije uspjelo. Podaci nisu prepisani.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Json _input() => PlannerEngine.object(jsonDecode(_editor.text));

  bool get _current {
    try {
      return _plan?['inputSnapshot'] == PlannerEngine.snapshot(_input());
    } catch (_) {
      return false;
    }
  }

  bool get _approved =>
      _current &&
      _approval != null &&
      _approval!['planCreatedAt'] == _plan?['createdAt'] &&
      _approval!['inputSnapshot'] == _plan?['inputSnapshot'];

  Json _state() => {
    'input': _editor.text,
    'plan': _plan,
    'approval': _approval,
    'reports': _reports,
    'audit': _audit,
  };

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Freeze before await so the stored approval and input always agree.
      final state = PlannerEngine.object(jsonDecode(jsonEncode(_state())));
      await _store.save(state);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sačuvano lokalno na ovom uređaju.')),
        );
    } catch (e) {
      if (mounted) setState(() => _error = 'Čuvanje nije uspjelo: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _planning = true;
      _error = null;
    });
    try {
      final input = _input();
      final plan = await compute(_buildPlan, input);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _approval = null;
        _error = null;
        _teamId = null;
        _tab = 1;
        _audit.add({
          'at': DateTime.now().toUtc().toIso8601String(),
          'event': 'generated',
          'planCreatedAt': plan['createdAt'],
        });
      });
      _save();
    } catch (e) {
      if (mounted) setState(() => _error = 'Plan nije izrađen: $e');
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  static const _labels = <String, String>{
    'mission': 'Naziv akcije',
    'id': 'Jedinstvena oznaka',
    'name': 'Naziv',
    'lat': 'Geografska širina (stepeni)',
    'lng': 'Geografska dužina (stepeni)',
    'elevationM': 'Nadmorska visina tla (m; prazno = nepoznato)',
    'antennaM': 'Visina antene iznad tla (m)',
    'accessible': 'Pristup lokaciji potvrđen',
    'stationLimit': 'Broj raspoloživih prenosnih stanica',
    'frequencyMHz': 'Frekvencija (MHz)',
    'txDbm': 'Predajna snaga (dBm)',
    'sensitivityDbm': 'Osjetljivost prijemnika (dBm)',
    'gainDbi': 'Dobitak svake antene (dBi)',
    'lossDb': 'Ukupni dodatni gubici veze (dB)',
    'requiredMarginDb': 'Tražena rezerva veze (dB)',
    'minAglM': 'Najniža kandidatska visina iznad tla (m)',
    'maxAglM': 'Najviša dozvoljena kandidatska visina iznad tla (m)',
    'stepM': 'Korak ispitivanja visine (m)',
    'enduranceMinutes': 'Potvrđena autonomija sa ovom opremom (min)',
    'transitMinutes': 'Ukupno vrijeme odlaska i povratka (min)',
    'reserveMinutes': 'Rezerva energije izražena u minutima',
    'requiredMinutes': 'Potrebno prisustvo na položaju (min)',
    'conditionsConfirmed': 'Provjereni uslovi i ograničenja leta',
    'skills': 'Potvrđene sposobnosti (odvojene zarezom)',
    'available': 'Tim raspoloživ za novi zadatak',
    'requires': 'Potrebne sposobnosti (iste oznake kao kod timova)',
    'priority': 'Prioritet zadatka (1–5; 5 je najviši)',
    'routeConfirmed': 'Prohodnost pristupne rute potvrđena',
    'from': 'Oznaka početne lokacije',
    'to': 'Oznaka krajnje lokacije',
    'source': 'Izvor profila i datum podataka',
    'samples': 'Visine profila i prepreka (m nad morem, odvojene zarezom)',
    'reportTimeoutMinutes': 'Upozori poslije izostanka izvještaja (min)',
    'batteryAlertPercent': 'Prag upozorenja na bateriju (%)',
  };

  Future<Json?> _editObject(String title, Json value) async {
    final working = PlannerEngine.object(jsonDecode(jsonEncode(value)));
    final fields = {
      for (final key in working.keys.where(_labels.containsKey))
        key: TextEditingController(
          text: working[key] is List
              ? (working[key] as List).join(', ')
              : working[key]?.toString() ?? '',
        ),
    };
    final form = GlobalKey<FormState>();
    final result = await showDialog<Json>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final key in fields.keys)
                      if (working[key] is bool)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_labels[key]!),
                          value: working[key] as bool,
                          onChanged: (v) => update(() => working[key] = v),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller: fields[key],
                            minLines: 1,
                            maxLines: key == 'samples' ? 5 : 2,
                            decoration: InputDecoration(
                              labelText: _labels[key],
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType:
                                working[key] is num || working[key] == null
                                ? const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  )
                                : TextInputType.text,
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (working[key] is List) {
                                if (key == 'samples' &&
                                    text
                                        .split(',')
                                        .any(
                                          (s) =>
                                              num.tryParse(s.trim()) == null ||
                                              !num.parse(s.trim()).isFinite,
                                        )) {
                                  return 'Unesite brojeve odvojene zarezima.';
                                }
                                return null;
                              }
                              if (working[key] is num || working[key] == null) {
                                if (text.isEmpty &&
                                    (working[key] == null ||
                                        key == 'elevationM'))
                                  return null;
                                if (num.tryParse(text) == null ||
                                    !num.parse(text).isFinite)
                                  return 'Unesite konačan broj.';
                              } else if (text.isEmpty) {
                                return 'Obavezno polje.';
                              }
                              return null;
                            },
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Otkaži'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                for (final key in fields.keys) {
                  final text = fields[key]!.text.trim();
                  if (working[key] is bool) continue;
                  if (working[key] is List) {
                    working[key] = text.isEmpty
                        ? []
                        : key == 'samples'
                        ? text
                              .split(',')
                              .map((s) => num.parse(s.trim()))
                              .toList()
                        : text
                              .split(',')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty)
                              .toList();
                  } else if (working[key] is num || working[key] == null) {
                    working[key] = text.isEmpty ? null : num.parse(text);
                  } else {
                    working[key] = text;
                  }
                }
                Navigator.pop(dialogContext, working);
              },
              child: const Text('Primijeni unos'),
            ),
          ],
        ),
      ),
    );
    // Dialog route can still be transitioning while its fields are disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in fields.values) {
        controller.dispose();
      }
    });
    return result;
  }

  void _applyInput(Json input) => setState(() {
    _editor.text = _pretty.convert(input);
    _approval = null;
    _error = null;
  });

  Future<void> _editSection(String key, String title) async {
    try {
      final input = _input();
      final result = await _editObject(title, PlannerEngine.object(input[key]));
      if (result != null && mounted) {
        input[key] = result;
        _applyInput(input);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Unos nije ispravan: $e');
    }
  }

  Widget _resourceList(Json input, String key, String title, Json template) {
    final list = PlannerEngine.objects(input[key]);
    return _card(title, [
      for (var i = 0; i < list.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${list[i]['name'] ?? list[i]['id'] ?? '${list[i]['from']} → ${list[i]['to']}'}',
          ),
          subtitle: const Text('Dodirnite za pregled i izmjenu'),
          onTap: _saving || _planning
              ? null
              : () async {
                  final result = await _editObject(title, list[i]);
                  if (result == null || !mounted) return;
                  list[i] = result;
                  input[key] = list;
                  _applyInput(input);
                },
          trailing: IconButton(
            tooltip: 'Ukloni iz radnog unosa',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _saving || _planning
                ? null
                : () {
                    list.removeAt(i);
                    input[key] = list;
                    _applyInput(input);
                  },
          ),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Dodaj'),
        onPressed: _saving || _planning
            ? null
            : () async {
                final result = await _editObject(title, template);
                if (result == null || !mounted) return;
                list.add(result);
                input[key] = list;
                _applyInput(input);
              },
      ),
    ]);
  }

  List<Widget> _structuredInput() {
    try {
      final input = _input();
      return [
        _card('Akcija i osnovni parametri', [
          _line('${input['mission']}'),
          if (input['importNote'] != null) _line(input['importNote'] as String),
          OutlinedButton(
            onPressed: _saving || _planning
                ? null
                : () async {
                    final result = await _editObject('Akcija i praćenje', {
                      for (final k in [
                        'mission',
                        'stationLimit',
                        'reportTimeoutMinutes',
                        'batteryAlertPercent',
                      ])
                        k: input[k],
                    });
                    if (result != null && mounted) {
                      input.addAll(result);
                      _applyInput(input);
                    }
                  },
            child: const Text('Uredi akciju i pragove'),
          ),
          for (final section in {
            'hq': 'Štab',
            'incident': 'Mjesto nesreće',
            'radio': 'Radio-oprema (isti profil na oba kraja)',
            'drone': 'Dron i ograničenja',
          }.entries)
            OutlinedButton(
              onPressed: _saving || _planning
                  ? null
                  : () => _editSection(section.key, section.value),
              child: Text(section.value),
            ),
        ]),
        _resourceList(input, 'stations', 'Kandidatske lokacije stanica', {
          'id': '',
          'lat': null,
          'lng': null,
          'elevationM': null,
          'antennaM': 2,
          'accessible': false,
        }),
        _resourceList(
          input,
          'airSites',
          'Kandidatski položaji vazdušnog releja',
          {
            'id': '',
            'lat': null,
            'lng': null,
            'elevationM': null,
            'antennaM': 0,
            'accessible': false,
          },
        ),
        _resourceList(input, 'profiles', 'Profili terena i prepreka', {
          'from': '',
          'to': '',
          'source': '',
          'samples': <num>[],
        }),
        _resourceList(input, 'teams', 'Raspoloživi timovi', {
          'id': '',
          'name': '',
          'lat': null,
          'lng': null,
          'skills': <String>[],
          'available': false,
        }),
        _resourceList(input, 'tasks', 'Zadaci', {
          'id': '',
          'name': '',
          'lat': null,
          'lng': null,
          'requires': <String>[],
          'priority': 3,
          'routeConfirmed': false,
        }),
      ];
    } catch (_) {
      return [_line('Ispravite napredni JSON unos ili učitajte novi unos.')];
    }
  }

  Future<void> _approve() async {
    if (!_current) return;
    _commander.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odobrenje planskog prijedloga'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Potvrđujem da sam pregledao procjene, neriješene veze i neraspoređene zadatke. '
              'Odobrenje ne šalje naredbe timovima i ne upravlja dronom.',
            ),
            TextField(
              controller: _commander,
              decoration: const InputDecoration(labelText: 'Ime komandira'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Otkaži'),
          ),
          FilledButton(
            onPressed: () {
              if (_commander.text.trim().isNotEmpty)
                Navigator.pop(context, true);
            },
            child: const Text('Odobri prijedlog'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || !_current) return;
    setState(() {
      _approval = {
        'commander': _commander.text.trim(),
        'at': DateTime.now().toUtc().toIso8601String(),
        'inputSnapshot': _plan!['inputSnapshot'],
        'planCreatedAt': _plan!['createdAt'],
      };
      _audit.add({..._approval!, 'event': 'approved'});
    });
    await _save();
  }

  Future<void> _replace(Json value) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zamijeni radni unos?'),
        content: const Text(
          'Trenutni unos i prijedlog će biti zamijenjeni. Odobrenje se poništava. '
          'Prethodno ih možete kopirati dugmetom Izvoz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Otkaži'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zamijeni'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _editor.text = _pretty.convert(value);
      _plan = null;
      _approval = null;
      _reports = [];
      _teamId = null;
      _error = null;
      _tab = 0;
      _audit.add({
        'event': 'inputReplaced',
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  void _addReport() {
    if (_teamId == null || !_approved) return;
    final battery = _battery.text.trim().isEmpty
        ? null
        : double.tryParse(_battery.text);
    if (_battery.text.trim().isNotEmpty &&
        (battery == null ||
            !battery.isFinite ||
            battery < 0 ||
            battery > 100)) {
      setState(
        () =>
            _error = 'Baterija mora biti od 0 do 100 ili prazna za nepoznato.',
      );
      return;
    }
    setState(() {
      _reports.add({
        'teamId': _teamId,
        'at': DateTime.now().toUtc().toIso8601String(),
        'battery': battery,
        'status': _reportStatus,
        'note': _note.text.trim(),
        'source': 'manual',
        'planCreatedAt': _plan!['createdAt'],
      });
      _error = null;
      _note.clear();
      _battery.clear();
    });
    _save();
  }

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );

  Widget _line(String value) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(value));

  Widget _inputs() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _card('Unos komandira — radi bez interneta', [
        _line(
          'Lokalni ekspertni sistem pravila i proračuna. Nema jezičkog modela niti cloud poziva. '
          'Unesite stvarne podatke opreme, kandidatske lokacije i profile terena prije planiranja.',
        ),
        _line(
          'Profili: ravnomjerno raspoređene visine terena/prepreka u metrima nad morem, '
          'uključujući obje krajnje tačke. accessible znači provjeren pristup lokaciji. '
          'routeConfirmed znači potvrđenu rutu zadatka. AGL je visina iznad tla.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _saving || _planning
                  ? null
                  : () => _replace(emptyScenario()),
              child: const Text('Novi unos'),
            ),
            OutlinedButton(
              onPressed: _saving || _planning
                  ? null
                  : () => _replace(demoScenario()),
              child: const Text('DEMO vježba'),
            ),
            if (widget.meshInput != null)
              OutlinedButton(
                onPressed: _saving || _planning
                    ? null
                    : () => _replace(widget.meshInput!),
                child: const Text('Preuzmi podatke iz štaba'),
              ),
            OutlinedButton(
              onPressed: _saving || _planning
                  ? null
                  : () async {
                      try {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (!mounted) return;
                        final decoded = PlannerEngine.object(
                          jsonDecode(data?.text ?? ''),
                        );
                        // Export envelopes can also be used to restore just the input.
                        final value = decoded['input'] is String
                            ? PlannerEngine.object(jsonDecode(decoded['input']))
                            : decoded;
                        await _replace(value);
                      } catch (e) {
                        if (mounted)
                          setState(() => _error = 'Uvoz nije uspio: $e');
                      }
                    },
              child: const Text('Uvezi JSON iz međuspremnika'),
            ),
          ],
        ),
      ]),
      ..._structuredInput(),
      ExpansionTile(
        title: const Text('Napredni unos / razmjena podataka'),
        children: [
          TextField(
            controller: _editor,
            minLines: 18,
            maxLines: 36,
            enabled: !_saving && !_planning,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Strukturisani podaci akcije (JSON)',
            ),
            onChanged: (_) => setState(() {
              _approval = null;
              _error = null;
            }),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _saving || _planning ? null : _generate,
        icon: const Icon(Icons.psychology),
        label: Text(
          _planning ? 'Proračun je u toku…' : 'Izradi offline prijedlog',
        ),
      ),
    ],
  );

  Widget _results() {
    if (_plan == null)
      return const Center(child: Text('Unesite podatke i izradite prijedlog.'));
    final network = PlannerEngine.object(_plan!['network']);
    final air = PlannerEngine.object(_plan!['airRelay']);
    final path = (network['path'] as List).cast<Json>();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card('Verzija plana', [
          _line('${_plan!['mission']}\n${_plan!['createdAt']}'),
          _line(
            !_current
                ? 'ZASTARJEO — unos je promijenjen. Izradite novi prijedlog.'
                : _approved
                ? 'ODOBREN PRIJEDLOG — ${_approval!['commander']}'
                : 'NACRT — čeka pregled komandira.',
          ),
          FilledButton(
            onPressed: _current && !_approved && !_saving && !_planning
                ? _approve
                : null,
            child: const Text('Pregledano — odobri prijedlog'),
          ),
        ]),
        _card('1. Planiranje mreže', [
          _line(
            path.isEmpty
                ? 'Zemaljska putanja nije riješena sa dostupnim podacima.'
                : 'Procijenjena putanja: ${path.map((p) => p['id']).join(' → ')}',
          ),
          for (final node in path.where((n) => n['kind'] == 'station'))
            _line(
              '${node['id']}: ${node['lat']}, ${node['lng']}; antena ${node['antennaM']} m iznad tla.',
            ),
          ExpansionTile(
            title: const Text('Pregled veza i nedostajućih podataka'),
            children: [
              for (final link in (network['links'] as List).cast<Json>())
                ListTile(
                  title: Text(
                    '${link['from']} ↔ ${link['to']}: ${link['status']}',
                  ),
                  subtitle: Text(
                    '${link['reason']}'
                    '${link['marginDb'] == null ? '' : '\nRezerva: ${(link['marginDb'] as num).toStringAsFixed(1)} dB'}',
                  ),
                ),
            ],
          ),
        ]),
        _card('2. Planiranje vazdušnog releja', [
          _line('${air['status']}: ${air['reason']}'),
          if (air['status'] == 'estimated') ...[
            _line('Pozicija: ${air['site']['lat']}, ${air['site']['lng']}'),
            _line(
              'AGL: ${air['aglM']} m iznad tla; AMSL: ${air['amslM']} m nad morem.',
            ),
            _line(
              'Unesena raspoloživa autonomija na položaju: ${air['availableMinutes']} min.',
            ),
            _line(
              'Putanja: ${(air['path'] as List).map((n) => n['id']).join(' → ')}',
            ),
          ],
        ]),
        _card('3. Raspored timova', [
          for (final a in (_plan!['assignments'] as List).cast<Json>())
            _line(
              '${a['teamName']} → ${a['taskName']} '
              '(vazdušna udaljenost ${(a['straightLineM'] as num).toStringAsFixed(0)} m)',
            ),
          if ((_plan!['assignments'] as List).isEmpty)
            _line('Nema izvodljivih dodjela.'),
          for (final t in (_plan!['unassigned'] as List).cast<Json>())
            _line('NERASPOREĐENO: ${t['name']} — ${t['reason']}'),
        ]),
        _card('4. Predloženi plan akcije', [
          for (final step in _plan!['steps']) _line(step as String),
        ]),
        _card('Pretpostavke i ograničenja', [
          for (final warning in _plan!['warnings']) _line(warning as String),
        ]),
      ],
    );
  }

  Widget _monitoring() {
    if (_plan == null) return const Center(child: Text('Prvo izradite plan.'));
    final assignments = (_plan!['assignments'] as List).cast<Json>();
    final reports = _reports
        .where((r) => r['planCreatedAt'] == _plan!['createdAt'])
        .toList();
    List<Json> alerts = [];
    try {
      alerts = _engine.monitor(_input(), _plan!, reports, DateTime.now());
    } catch (_) {
      /* A changed/invalid input is explicitly displayed below. */
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card('5. Praćenje izvođenja', [
          _line(
            _approved
                ? 'Odobren prijedlog. Unosite potvrđene izvještaje timova.'
                : 'Praćenje ove verzije nije aktivno: potreban je važeći odobren prijedlog.',
          ),
          _line(
            'Ova verzija koristi ručne izvještaje komandira. Nije priključena na telemetriju drona ili radio-stanica.',
          ),
          for (final a in alerts) _line('${a['teamId']}: ${a['message']}'),
          if (alerts.isEmpty)
            _line(
              'Nema upozorenja iz dostupnih izvještaja; to nije potvrda bezbjednosti.',
            ),
        ]),
        _card('Novi izvještaj', [
          DropdownButtonFormField<String>(
            key: ValueKey(_plan!['createdAt']),
            initialValue: _teamId,
            decoration: const InputDecoration(labelText: 'Tim'),
            items: assignments
                .map(
                  (a) => DropdownMenuItem<String>(
                    value: a['teamId'],
                    child: Text(a['teamName']),
                  ),
                )
                .toList(),
            onChanged: _approved ? (v) => setState(() => _teamId = v) : null,
          ),
          DropdownButtonFormField<String>(
            initialValue: _reportStatus,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'ok', child: Text('U radu')),
              DropdownMenuItem(value: 'done', child: Text('Zadatak završen')),
              DropdownMenuItem(
                value: 'blocked',
                child: Text('Pristup onemogućen'),
              ),
              DropdownMenuItem(value: 'help', child: Text('Potrebna pomoć')),
            ],
            onChanged: _approved
                ? (v) => setState(() => _reportStatus = v!)
                : null,
          ),
          TextField(
            controller: _battery,
            enabled: _approved && !_saving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Baterija % (prazno = nepoznato)',
            ),
          ),
          TextField(
            controller: _note,
            enabled: _approved && !_saving,
            decoration: const InputDecoration(
              labelText: 'Bilješka / položaj / izmjerena veza',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _approved && !_saving ? _addReport : null,
            child: const Text('Zabilježi izvještaj'),
          ),
        ]),
        for (final r in reports.reversed)
          ListTile(
            title: Text('${r['teamId']}: ${r['status']}'),
            subtitle: Text('${r['at']}\n${r['note']}'),
          ),
        ExpansionTile(
          title: const Text('Dnevnik verzija i odobrenja'),
          children: [
            for (final a in _audit.reversed)
              ListTile(
                title: Text('${a['event']}'),
                subtitle: Text('${a['at']}'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('NRN • Offline planer'),
      actions: [
        IconButton(
          tooltip: 'Izvoz JSON u međuspremnik',
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: _pretty.convert(_state())),
            );
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Unos, plan i dnevnik kopirani.')),
              );
          },
        ),
        IconButton(
          tooltip: 'Sačuvaj lokalno',
          icon: const Icon(Icons.save),
          onPressed: _loading || _saving || _planning ? null : _save,
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: const Text('Zatvori'),
                    ),
                  ],
                ),
              Expanded(
                child: switch (_tab) {
                  0 => _inputs(),
                  1 => _results(),
                  _ => _monitoring(),
                },
              ),
            ],
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.edit_note), label: 'Unos'),
        NavigationDestination(icon: Icon(Icons.route), label: 'Prijedlog'),
        NavigationDestination(
          icon: Icon(Icons.monitor_heart),
          label: 'Praćenje',
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _clock?.cancel();
    _editor.dispose();
    _commander.dispose();
    _note.dispose();
    _battery.dispose();
    super.dispose();
  }
}

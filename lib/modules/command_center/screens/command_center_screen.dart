import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../services/nearby_service.dart';
import '../services/operations_store.dart';
import '../widgets/command_center_map_panel.dart';

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({
    super.key,
    required this.meshUserLocations,
    required this.meshSosLocations,
    required this.transport,
    required this.operations,
    required this.live,
    required this.batteryLevel,
    required this.onSos,
    required this.onCancelSos,
    required this.onSosResponded,
    required this.onOfflineMaps,
  });
  final Map<String, Map<String, dynamic>> meshUserLocations, meshSosLocations;
  final NearbyService transport;
  final OperationsStore operations;
  final Listenable live;
  final int Function() batteryLevel;
  final Future<void> Function() onSos, onCancelSos;
  final VoidCallback onOfflineMaps;
  final void Function(String id) onSosResponded;
  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  static const bg = Color(0xFF070D14),
      panel = Color(0xFF0C1620),
      line = Color(0xFF23313D),
      blue = Color(0xFF1687FF);
  final _focus = ValueNotifier<LatLng?>(null);
  final _message = TextEditingController();
  late final Listenable _changes;
  Timer? _clock;
  int _page = 0, _sosTab = 0;
  bool _busy = false;
  String? _recipient;
  OperationsStore get ops => widget.operations;
  NearbyService get mesh => widget.transport;
  static const labels = [
    'Dashboard',
    'Situacijska mapa',
    'SOS centar',
    'Dispatch centar',
    'Timovi',
    'Korisnici',
    'Komunikacije',
    'Foto zid',
    'Mreža',
    'Resursi',
    'Postavke',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.map_outlined,
    Icons.sos,
    Icons.assignment_outlined,
    Icons.groups_outlined,
    Icons.people_outline,
    Icons.forum_outlined,
    Icons.photo_library_outlined,
    Icons.hub_outlined,
    Icons.inventory_2_outlined,
    Icons.settings_outlined,
  ];
  @override
  void initState() {
    super.initState();
    _changes = Listenable.merge([widget.live, mesh, ops]);
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    ops.ready.then((_) {
      if (mounted) ops.syncIncidents(widget.meshSosLocations);
    });
  }

  Future<T?> _safeDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    final result = await Navigator.of(context).push(route);
    // Text controllers must outlive the reverse route transition.
    await route.completed;
    return result;
  }

  String _name(String id) =>
      widget.meshUserLocations[id]?['deviceName']?.toString() ??
      mesh.knownDevices[id] ??
      id;
  String _time(dynamic value) {
    final stamp = value is num ? value.toInt() : 0;
    if (stamp <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(stamp).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _toast(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _toast(await action());
    } catch (e) {
      _toast('Akcija nije završena: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
    ),
  );
  Widget _box(String title, Widget child, {Widget? action}) => Container(
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
        ),
        const Divider(height: 1, color: line),
        Expanded(child: child),
      ],
    ),
  );
  Widget _all(int page) => TextButton(
    onPressed: () => setState(() => _page = page),
    child: const Text('PRIKAŽI SVE', style: TextStyle(fontSize: 9)),
  );
  Widget _stat(String title, String value, IconData icon, Color color) =>
      Container(
        width: 154,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Colors.white54),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  Widget _stats() {
    final fresh = widget.meshUserLocations.values
        .where(
          (e) =>
              DateTime.now().millisecondsSinceEpoch -
                  ((e['time'] as num?)?.toInt() ?? 0) <=
              120000,
        )
        .length;
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _stat('SVJEŽE GPS POZICIJE', '$fresh', Icons.person_pin_circle, blue),
          _stat(
            'AKTIVNI SOS',
            '${ops.incidents.values.where((e) => e['status'] != 'resolved').length}',
            Icons.sos,
            Colors.redAccent,
          ),
          _stat('TIMOVI', '${ops.teams.length}', Icons.groups, blue),
          _stat(
            'DIREKTNE VEZE',
            '${mesh.connectedDevices.length}',
            Icons.wifi_tethering,
            Colors.greenAccent,
          ),
          _stat(
            'BATERIJA UREĐAJA',
            widget.batteryLevel() >= 0 ? '${widget.batteryLevel()}%' : '—',
            Icons.battery_std,
            Colors.greenAccent,
          ),
          _stat(
            'PRIPRAVNOST • LOKALNO',
            ops.readiness,
            Icons.shield_outlined,
            Colors.amber,
          ),
        ],
      ),
    );
  }

  Widget _menu() => ListView(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 8, 24),
        child: Text(
          'NRN MESH\nCOMMAND CENTER',
          style: TextStyle(
            color: blue,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
      for (var i = 0; i < labels.length; i++)
        ListTile(
          dense: true,
          selected: _page == i,
          selectedTileColor: blue.withValues(alpha: .22),
          selectedColor: Colors.white,
          leading: Icon(
            icons[i],
            size: 18,
            color: _page == i ? blue : Colors.white54,
          ),
          title: Text(labels[i], style: const TextStyle(fontSize: 11)),
          onTap: () {
            setState(() => _page = i);
          },
        ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'NRN radi preko lokalnih veza.\nGPS pozicija nije dokaz aktivne veze.',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ),
    ],
  );
  Widget _map() => CommandCenterMapPanel(
    meshUserLocations: widget.meshUserLocations,
    meshSosLocations: Map.fromEntries(
      ops.incidents.entries.where((e) => e.value['status'] != 'resolved'),
    ),
    focus: _focus,
    resources: ops.resources,
    teamColorsByMember: {
      for (final team in ops.teams.values)
        for (final id in team['members'] as List)
          '$id': Color((team['color'] as num?)?.toInt() ?? 0xFF1687FF),
    },
    onUserMarkerTap: _userDetails,
  );

  void _userDetails(String id) {
    final data = widget.meshUserLocations[id] ?? {};
    _safeDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_name(id)),
        content: Text(
          '${data['role'] ?? mesh.knownDeviceRoles[id] ?? 'Korisnik'}\nGPS: ${data['lat'] ?? '—'}, ${data['lng'] ?? '—'}\nBaterija: ${data['battery'] ?? '—'}%\nPozicija primljena: ${_time(data['time'])}\nID: $id',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _recipient = id;
                _page = 6;
              });
            },
            child: const Text('Privatna poruka'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  Widget _sosPanel() {
    final entries = ops.incidents.entries
        .where(
          (e) => _sosTab == 0
              ? e.value['status'] != 'resolved'
              : e.value['status'] == 'resolved',
        )
        .toList();
    return _box(
      'SOS centar',
      Column(
        children: [
          Row(
            children: [
              for (final (i, label) in [(0, 'AKTIVNI'), (1, 'ZAVRŠENI')])
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _sosTab = i),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: _sosTab == i ? blue : Colors.white38,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: entries.isEmpty
                ? _empty('Nema događaja u ovoj kategoriji')
                : ListView(
                    children: [
                      for (final e in entries)
                        ListTile(
                          dense: true,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF4B1520),
                            child: Icon(Icons.sos, color: Colors.redAccent),
                          ),
                          title: Text(
                            '${e.value['sender'] ?? 'SOS'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            '${e.value['message'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: Text(
                            _time(e.value['time']),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                            ),
                          ),
                          onTap: () => _incident(e.key, e.value),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      action: _all(2),
    );
  }

  void _incident(String id, Map<String, dynamic> incident) {
    _safeDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('SOS • ${incident['sender'] ?? id}'),
        content: SingleChildScrollView(
          child: Text(
            '${incident['message'] ?? ''}\n\nStatus: ${incident['status']}\nLokacija: ${incident['lat'] ?? 'nije dostupna'}, ${incident['lng'] ?? '—'}\nOdgovori: ${(incident['responses'] as Map? ?? {}).length}',
          ),
        ),
        actions: [
          if (meshPoint(incident) != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _page = 1);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _focus.value = meshPoint(incident),
                );
              },
              child: const Text('Na mapi'),
            ),
          if (incident['status'] != 'resolved')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _run(() async {
                  final result = await mesh.sendSosResponse(
                    sosId: id,
                    responseType: 'sos_accept',
                  );
                  if (result == null) return 'Odgovor nije poslat';
                  widget.onSosResponded(id);
                  final responses = Map<String, dynamic>.from(
                    incident['responses'] as Map? ?? {},
                  );
                  responses[mesh.deviceId] = 'sos_accept';
                  incident['responses'] = responses;
                  await ops.save();
                  return 'Prihvatanje predato vezama: ${result.deliveredCount}';
                });
              },
              child: const Text('Prihvati SOS'),
            ),
          if (incident['senderId'] == mesh.deviceId &&
              incident['status'] != 'resolved')
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await widget.onCancelSos();
                ops.syncIncidents(widget.meshSosLocations);
              },
              child: const Text('Završi moj SOS'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  Widget _teams() => _box(
    'Timovi',
    ops.teams.isEmpty
        ? _empty('Formiraj tim od poznatih uređaja')
        : ListView(
            children: [
              for (final t in ops.teams.values)
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.groups,
                    color: Color((t['color'] as num?)?.toInt() ?? 0xFF1687FF),
                  ),
                  title: Text(
                    '${t['name']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    '${(t['members'] as List).length} članova',
                    style: const TextStyle(fontSize: 10),
                  ),
                  onTap: () => _safeDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('${t['name']}'),
                      content: Text(
                        (t['members'] as List)
                            .map((id) => _name('$id'))
                            .join('\n'),
                      ),
                      actions: [
                        if (t['owner'] == mesh.deviceId)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _run(
                                () => ops.transmit({'op': 'team', 'data': t}),
                              );
                            },
                            child: const Text('Ponovo pošalji'),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Zatvori'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
    action: IconButton(
      tooltip: 'Formiraj tim',
      onPressed: _createTeam,
      icon: const Icon(Icons.group_add, size: 18),
    ),
  );
  Future<void> _createTeam() async {
    await ops.ready;
    if (!mounted) return;
    final name = TextEditingController();
    final selected = <String>{};
    final users = {...mesh.knownDevices, mesh.deviceId: mesh.deviceName}
      ..removeWhere((id, name) => id.isEmpty || name.isEmpty);
    final result = await _safeDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Formiraj tim'),
          content: SizedBox(
            width: 380,
            height: 360,
            child: Column(
              children: [
                TextField(
                  controller: name,
                  onChanged: (_) => update(() {}),
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Naziv tima'),
                ),
                Expanded(
                  child: users.isEmpty
                      ? _empty('Prvo postavi ime uređaja i poveži učesnike')
                      : ListView(
                          children: [
                            for (final e in users.entries)
                              CheckboxListTile(
                                title: Text(e.value),
                                subtitle: Text(
                                  e.key == mesh.deviceId
                                      ? 'Ovaj uređaj'
                                      : 'Poznat uređaj • veza nije garantovana',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                value: selected.contains(e.key),
                                onChanged: (value) => update(() {
                                  if (value == true) {
                                    selected.add(e.key);
                                  } else {
                                    selected.remove(e.key);
                                  }
                                }),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Otkaži'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty || selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Formiraj'),
            ),
          ],
        ),
      ),
    );
    // Rebuild validity as the user types without recreating the controller.
    if (result == true)
      await _run(
        () => ops.publish('team', {
          'id': const Uuid().v4(),
          'name': name.text.trim(),
          'members': selected.toList(),
          'color': blue.toARGB32(),
        }),
      );
    name.dispose();
  }

  Widget _dispatch() => _box(
    'Dispatch centar',
    Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _assign,
              icon: const Icon(Icons.send, size: 16),
              label: const Text(
                'Dodijeli zadatak',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Članovi potvrđuju status na svom uređaju. Slanje nije potvrda prijema.',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ),
        Expanded(
          child: ops.missions.isEmpty
              ? _empty('Nema dodijeljenih zadataka')
              : ListView(
                  children: [
                    for (final m in ops.missions.values.toList().reversed)
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.assignment_outlined,
                          size: 18,
                          color: blue,
                        ),
                        title: Text(
                          '${m['task']}',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 11),
                        ),
                        subtitle: Text(
                          '${ops.teams[m['teamId']]?['name'] ?? 'Tim'} • ${_time(m['time'])}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        onTap: () => _mission(m),
                      ),
                  ],
                ),
        ),
      ],
    ),
    action: _all(3),
  );
  Future<void> _assign() async {
    final owned = ops.teams.values
        .where((e) => e['owner'] == mesh.deviceId)
        .toList();
    if (owned.isEmpty) {
      _toast('Prvo formiraj svoj tim.');
      return;
    }
    String teamId = '${owned.first['id']}';
    String? sosId;
    final task = TextEditingController();
    final result = await _safeDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Dodijeli zadatak'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: teamId,
                  decoration: const InputDecoration(labelText: 'Tim'),
                  items: [
                    for (final t in owned)
                      DropdownMenuItem(
                        value: '${t['id']}',
                        child: Text('${t['name']}'),
                      ),
                  ],
                  onChanged: (v) => update(() => teamId = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: '',
                  decoration: const InputDecoration(labelText: 'Incident'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Samostalan zadatak'),
                    ),
                    for (final e in ops.incidents.entries.where(
                      (e) => e.value['status'] != 'resolved',
                    ))
                      DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.value['sender'] ?? 'SOS'}'),
                      ),
                  ],
                  onChanged: (v) => sosId = v == '' ? null : v,
                ),
                TextField(
                  controller: task,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Zadatak • obavezno',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Otkaži'),
            ),
            FilledButton(
              onPressed: () {
                if (task.text.trim().isNotEmpty) Navigator.pop(context, true);
              },
              child: const Text('Dodijeli'),
            ),
          ],
        ),
      ),
    );
    if (result == true)
      await _run(
        () => ops.publish('mission', {
          'id': const Uuid().v4(),
          'teamId': teamId,
          'members': List.of(ops.teams[teamId]!['members'] as List),
          'task': task.text.trim(),
          'sosId': sosId,
        }),
      );
    task.dispose();
  }

  void _mission(Map<String, dynamic> m) {
    final progress = m['progress'] as Map? ?? {};
    _safeDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Praćenje misije'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${m['task']}'),
                const SizedBox(height: 16),
                for (final id in m['members'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${_name('$id')}: ${(progress[id] as Map?)?['status'] ?? 'Čeka potvrdu'}',
                    ),
                  ),
                if ((m['members'] as List).contains(mesh.deviceId))
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final status in [
                        'Prihvaćen',
                        'Na putu',
                        'Na lokaciji',
                        'Završeno',
                        'Odbijen',
                      ])
                        ActionChip(
                          label: Text(status),
                          onPressed: () {
                            Navigator.pop(context);
                            _run(
                              () => ops.publish('progress', {
                                'id': m['id'],
                                'status': status,
                              }),
                            );
                          },
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (m['owner'] == mesh.deviceId)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _run(() async {
                  final team = ops.teams[m['teamId']];
                  if (team != null)
                    await ops.transmit({'op': 'team', 'data': team});
                  return ops.transmit({'op': 'mission', 'data': m});
                });
              },
              child: const Text('Ponovi slanje'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  Widget _missionPanel() => _box(
    'Praćenje misija',
    ops.missions.isEmpty
        ? _empty('Nema aktivnih misija')
        : ListView(
            children: [
              for (final m in ops.missions.values.toList().reversed)
                ListTile(
                  dense: true,
                  title: Text(
                    '${m['task']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    'Odgovori: ${(m['progress'] as Map? ?? {}).length}/${(m['members'] as List).length}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _mission(m),
                ),
            ],
          ),
  );
  Widget _communications() {
    final recipients = {...mesh.knownDevices}..remove(mesh.deviceId);
    if (!recipients.containsKey(_recipient)) _recipient = null;
    return _box(
      'Komunikacije',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButton<String>(
              isExpanded: true,
              value: _recipient ?? '',
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text(
                    'Broadcast • svima',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                for (final e in recipients.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      'Privatno • ${e.value}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _recipient = v == '' ? null : v),
            ),
          ),
          Expanded(
            child: ops.communications.isEmpty
                ? _empty('Nema poruka')
                : ListView(
                    reverse: true,
                    children: [
                      for (final m in ops.communications.reversed)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${m['sender']} • ${m['channel'] == 'private' ? 'Privatno' : 'Broadcast'} • ${_time(m['time'])}',
                            style: const TextStyle(fontSize: 10, color: blue),
                          ),
                          subtitle: Text(
                            '${m['text']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _message,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'Napiši poruku…',
                      counterText: '',
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
                IconButton(
                  tooltip: 'Pošalji poruku',
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final text = _message.text.trim();
                          if (text.isEmpty) return 'Upiši poruku';
                          final result = await ops.communicate(
                            text,
                            _recipient,
                          );
                          if (!result.startsWith('Nije')) _message.clear();
                          return result;
                        }),
                  icon: const Icon(Icons.send, color: blue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _photo() async {
    await _run(() async {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 360,
        maxHeight: 360,
        imageQuality: 32,
      );
      if (file == null) return 'Odabir otkazan';
      final bytes = await file.readAsBytes();
      if (bytes.length > 36000 ||
          bytes.length < 3 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8)
        return 'Odaberi manju JPEG fotografiju (do 36 KB).';
      return ops.publish('photo', {
        'id': const Uuid().v4(),
        'bytes': base64Encode(bytes),
        'caption': 'Terenska fotografija',
      });
    });
  }

  Widget _photos() => _box(
    'Foto zid',
    ops.photos.isEmpty
        ? _empty(
            'Dodaj terensku fotografiju. Šalje se kompresovana JPEG slika preko mesh veze.',
          )
        : GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.3,
            ),
            itemCount: ops.photos.length,
            itemBuilder: (context, index) {
              final photo = ops.photos.reversed.toList()[index];
              return InkWell(
                onTap: () => _safeDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('${photo['sender']} • ${_time(photo['time'])}'),
                    content: Image.memory(
                      base64Decode('${photo['bytes']}'),
                      errorBuilder: (_, _, _) =>
                          const Text('Slika nije dostupna'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _run(
                            () => ops.transmit({'op': 'photo', 'data': photo}),
                          );
                        },
                        child: const Text('Ponovi slanje'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Zatvori'),
                      ),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Image.memory(
                        base64Decode('${photo['bytes']}'),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image),
                      ),
                    ),
                    Text(
                      '${photo['sender']} • ${_time(photo['time'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              );
            },
          ),
    action: IconButton(
      tooltip: 'Dodaj fotografiju',
      onPressed: _busy ? null : _photo,
      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
    ),
  );
  Widget _network() => _box(
    'Mreža • stvarne direktne veze',
    Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Prikazane su potvrđene direktne veze ovog uređaja. Putanje drugih uređaja, ping i propusnost nisu izmjereni.',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ),
        Expanded(
          child: mesh.connectedDevices.isEmpty
              ? _empty('Nema povezanih uređaja')
              : CustomPaint(
                  painter: _NetworkPainter(
                    mesh.connectedDevices.values.toList(),
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
        Text(
          'Veze: ${mesh.connectedDevices.length}  •  Poznati uređaji: ${mesh.knownDevices.length}',
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 8),
      ],
    ),
    action: _all(8),
  );
  Widget _users() => _box(
    'Korisnici i veze',
    ListView(
      children: [
        for (final e in mesh.connectedDevices.entries)
          ListTile(
            leading: const Icon(Icons.link, color: Colors.greenAccent),
            title: Text(e.value),
            subtitle: const Text('Direktna veza'),
            trailing: IconButton(
              tooltip: 'Prekini vezu',
              icon: const Icon(Icons.link_off),
              onPressed: () async {
                try {
                  await mesh.disconnect(e.key);
                } catch (e) {
                  _toast('$e');
                }
              },
            ),
            onTap: () => _userDetails(mesh.endpointDeviceIds[e.key] ?? e.key),
          ),
        for (final e in mesh.foundDevices.entries)
          ListTile(
            leading: const Icon(Icons.bluetooth_searching),
            title: Text(e.value),
            subtitle: const Text('Otkriven uređaj'),
            trailing: TextButton(
              onPressed: () => mesh.connectToDevice(e.key),
              child: const Text('Poveži'),
            ),
          ),
        for (final e in widget.meshUserLocations.entries)
          ListTile(
            leading: const Icon(Icons.person_pin_circle_outlined),
            title: Text(_name(e.key)),
            subtitle: Text('GPS primljen: ${_time(e.value['time'])}'),
            onTap: () => _userDetails(e.key),
          ),
        if (mesh.connectedDevices.isEmpty &&
            mesh.foundDevices.isEmpty &&
            widget.meshUserLocations.isEmpty)
          _empty('Pokreni otkrivanje mreže u postavkama'),
      ],
    ),
  );
  Widget _resources() => _box(
    'Resursi • lokalna evidencija',
    ops.resources.isEmpty
        ? _empty(
            'Evidentiraj repetitor, vozilo, dron ili opremu. Status i lokacija unose se ručno.',
          )
        : ListView(
            children: [
              for (final r in ops.resources)
                ListTile(
                  title: Text('${r['name']}'),
                  subtitle: Text('${r['type']} • ${r['status']} • ručni unos'),
                  onTap: meshPoint(r) == null
                      ? null
                      : () {
                          setState(() => _page = 1);
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _focus.value = meshPoint(r),
                          );
                        },
                  trailing: IconButton(
                    tooltip: 'Ukloni resurs',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ops.removeResource('${r['id']}'),
                  ),
                ),
            ],
          ),
    action: IconButton(
      tooltip: 'Dodaj resurs',
      onPressed: _addResource,
      icon: const Icon(Icons.add),
    ),
  );
  Future<void> _addResource() async {
    final name = TextEditingController(),
        lat = TextEditingController(),
        lng = TextEditingController();
    String type = 'Repetitor', status = 'Nepoznato';
    final ok = await _safeDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Evidentiraj resurs'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Naziv • obavezno',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: [
                  for (final t in ['Repetitor', 'Vozilo', 'Dron', 'Oprema'])
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => type = v!,
              ),
              DropdownButtonFormField<String>(
                initialValue: status,
                items: [
                  for (final t in [
                    'Nepoznato',
                    'Dostupno',
                    'Zauzeto',
                    'Van funkcije',
                  ])
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => status = v!,
              ),
              TextField(
                controller: lat,
                decoration: const InputDecoration(
                  labelText: 'Geografska širina • opciono',
                ),
              ),
              TextField(
                controller: lng,
                decoration: const InputDecoration(
                  labelText: 'Geografska dužina • opciono',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Otkaži'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              if ((lat.text.trim().isNotEmpty || lng.text.trim().isNotEmpty) &&
                  meshPoint({'lat': lat.text, 'lng': lng.text}) == null) {
                _toast('Neispravne koordinate');
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Sačuvaj'),
          ),
        ],
      ),
    );
    if (ok == true)
      await ops.addResource({
        'id': const Uuid().v4(),
        'name': name.text.trim(),
        'type': type,
        'status': status,
        'lat': double.tryParse(lat.text),
        'lng': double.tryParse(lng.text),
      });
    name.dispose();
    lat.dispose();
    lng.dispose();
  }

  Widget _settings() => _box(
    'Postavke',
    ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${mesh.deviceName} • ${mesh.deviceRole}',
          style: const TextStyle(fontSize: 18),
        ),
        Text(
          mesh.deviceId,
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey(ops.readiness),
          initialValue: ops.readiness,
          decoration: const InputDecoration(
            labelText: 'Nivo pripravnosti • ovaj komandni centar',
          ),
          items: [
            for (final value in ['Redovna', 'Povećana', 'Vanredna'])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (value) {
            if (value != null) ops.setReadiness(value);
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await mesh.startAdvertising();
                  await mesh.startDiscovery();
                  return 'Oglašavanje: ${mesh.advertising} • otkrivanje: ${mesh.discovering}';
                }),
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Pokreni mrežu'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await mesh.stopAll();
                  return 'Mreža zaustavljena';
                }),
          icon: const Icon(Icons.stop),
          label: const Text('Zaustavi mrežu'),
        ),
        OutlinedButton.icon(
          onPressed: widget.onOfflineMaps,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: const Text('Offline mape i preuzeta područja'),
        ),
        const SizedBox(height: 20),
        const Text(
          'Fotografije su kompresovane radi ograničenja mesh poruka. Repetitori, vozila i dronovi imaju ručnu evidenciju; upravljanje hardverom nije povezano. Uloge su korisničke oznake i nisu provjera identiteta.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    ),
  );
  Widget _dashboard(double width) {
    if (width < 950)
      return ListView(
        children: [
          SizedBox(height: 420, child: _map()),
          const SizedBox(height: 10),
          for (final child in [
            _sosPanel(),
            _teams(),
            _dispatch(),
            _missionPanel(),
            _communications(),
            _photos(),
            _network(),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(height: 310, child: child),
            ),
        ],
      );
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight < 720
            ? 720.0
            : constraints.maxHeight;
        return SingleChildScrollView(
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Expanded(
                  flex: 6,
                  child: Row(
                    children: [
                      Expanded(flex: 7, child: _map()),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            Expanded(child: _sosPanel()),
                            const SizedBox(height: 10),
                            Expanded(child: _photos()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  flex: 4,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _teams()),
                      const SizedBox(width: 10),
                      Expanded(child: _dispatch()),
                      const SizedBox(width: 10),
                      Expanded(child: _missionPanel()),
                      const SizedBox(width: 10),
                      Expanded(child: _communications()),
                      const SizedBox(width: 10),
                      Expanded(child: _network()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _content(double width) => switch (_page) {
    0 => _dashboard(width),
    1 => _map(),
    2 => _sosPanel(),
    3 =>
      width < 650
          ? ListView(
              children: [
                SizedBox(height: 300, child: _dispatch()),
                const SizedBox(height: 10),
                SizedBox(height: 400, child: _missionPanel()),
              ],
            )
          : Row(
              children: [
                Expanded(child: _dispatch()),
                const SizedBox(width: 10),
                Expanded(child: _missionPanel()),
              ],
            ),
    4 => _teams(),
    5 => _users(),
    6 => _communications(),
    7 => _photos(),
    8 => _network(),
    9 => _resources(),
    _ => _settings(),
  };
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _changes,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1200;
        return Scaffold(
          backgroundColor: bg,
          drawer: wide
              ? null
              : Drawer(
                  backgroundColor: bg,
                  child: Builder(
                    builder: (context) => _menuWithContext(context),
                  ),
                ),
          appBar: AppBar(
            backgroundColor: bg,
            title: Text(
              'NRN / ${labels[_page].toUpperCase()}',
              style: const TextStyle(fontSize: 14, letterSpacing: 1),
            ),
            actions: [
              TextButton.icon(
                onPressed: widget.onSos,
                icon: const Icon(Icons.sos, color: Colors.redAccent),
                label: const Text(
                  'SOS',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              IconButton(
                tooltip: 'Nazad u chat',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
            ],
          ),
          body: Row(
            children: [
              if (wide) SizedBox(width: 180, child: _menu()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Column(
                    children: [
                      _stats(),
                      const SizedBox(height: 10),
                      if (_busy) const LinearProgressIndicator(minHeight: 2),
                      if (ops.storageError != null)
                        Text(
                          ops.storageError!,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      Expanded(
                        child: _content(
                          constraints.maxWidth - (wide ? 200 : 20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'NRN MESH  •  ${mesh.connectedDevices.isEmpty ? 'NEMA DIREKTNIH VEZA' : '${mesh.connectedDevices.length} DIREKTNIH VEZA'}  •  ${_time(DateTime.now().millisecondsSinceEpoch)}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  Widget _menuWithContext(BuildContext drawerContext) => ListView(
    children: [
      const ListTile(
        title: Text('NRN MESH', style: TextStyle(color: blue)),
      ),
      for (var i = 0; i < labels.length; i++)
        ListTile(
          leading: Icon(icons[i]),
          title: Text(labels[i]),
          selected: _page == i,
          onTap: () {
            setState(() => _page = i);
            Navigator.pop(drawerContext);
          },
        ),
    ],
  );
  @override
  void dispose() {
    _clock?.cancel();
    _focus.dispose();
    _message.dispose();
    super.dispose();
  }
}

class _NetworkPainter extends CustomPainter {
  _NetworkPainter(this.names);
  final List<String> names;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFF1687FF)
      ..strokeWidth = 1.5;
    for (var i = 0; i < names.length; i++) {
      final p = Offset(
        size.width * (i + 1) / (names.length + 1),
        size.height * (i.isEven ? .22 : .78),
      );
      canvas.drawLine(center, p, paint..color = const Color(0xFF254664));
      canvas.drawCircle(p, 5, paint..color = const Color(0xFF1687FF));
      final text = TextPainter(
        text: TextSpan(
          text: names[i],
          style: const TextStyle(fontSize: 9, color: Colors.white70),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      text.paint(
        canvas,
        Offset(
          (p.dx - text.width / 2).clamp(0, size.width - text.width),
          p.dy + 8,
        ),
      );
    }
    canvas.drawCircle(center, 17, paint..color = const Color(0xFF163D2D));
    canvas.drawCircle(center, 6, paint..color = Colors.greenAccent);
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) => true;
}

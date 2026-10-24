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
  bool _onlyMyTasks = false;
  Size? _layoutSize;
  bool get _isPhone {
    final size = _layoutSize ?? MediaQuery.sizeOf(context);
    return size.width < 700 || (size.width < 1100 && size.height < 500);
  }

  int get _activeSosCount =>
      ops.incidents.values.where((e) => e['status'] != 'resolved').length;
  bool get _phoneMapSelected => _page == 0 || _page == 1;
  int get _phoneNavIndex => switch (_page) {
    0 || 1 => 0,
    2 => 1,
    3 => 2,
    6 => 3,
    _ => 4,
  };
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
      if (mounted) {
        setState(() {});
      }
    });
    ops.ready.then((_) {
      if (mounted) {
        ops.syncIncidents(widget.meshSosLocations);
      }
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
    if (stamp <= 0) {
      return '—';
    }
    final d = DateTime.fromMillisecondsSinceEpoch(stamp).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      _toast(await action());
    } catch (e) {
      _toast('Akcija nije završena: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54, fontSize: _isPhone ? 15 : 12),
      ),
    ),
  );
  Widget _box(
    String title,
    Widget child, {
    Widget? action,
    bool showHeader = true,
  }) => Material(
    color: panel,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: line),
      borderRadius: BorderRadius.circular(_isPhone ? 16 : 7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isPhone ? title : title.toUpperCase(),
                    style: TextStyle(
                      fontSize: _isPhone ? 16 : 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
        if (showHeader) const Divider(height: 1, color: line),
        Expanded(child: child),
      ],
    ),
  );
  Widget _all(int page) => TextButton(
    onPressed: () => setState(() => _page = page),
    child: Text(
      _isPhone ? 'Otvori' : 'PRIKAŽI SVE',
      style: TextStyle(fontSize: _isPhone ? 14 : 9),
    ),
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
    compact: _isPhone,
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
        scrollable: true,
        insetPadding: _isPhone
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
        scrollable: true,
        insetPadding: _isPhone
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
                  if (result == null) {
                    return 'Odgovor nije poslat';
                  }
                  widget.onSosResponded(id);
                  await ops.recordSosResponse(id, 'sos_accept');
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
                  dense: !_isPhone,
                  leading: Icon(
                    Icons.groups,
                    color: Color((t['color'] as num?)?.toInt() ?? 0xFF1687FF),
                  ),
                  title: Text(
                    '${t['name']}',
                    style: TextStyle(fontSize: _isPhone ? 16 : 12),
                  ),
                  subtitle: Text(
                    '${(t['members'] as List).length} članova',
                    style: TextStyle(fontSize: _isPhone ? 13 : 10),
                  ),
                  onTap: () => _safeDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      scrollable: true,
                      insetPadding: _isPhone
                          ? const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 20,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 24,
                            ),
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
  Widget _teamMemberOption(
    MapEntry<String, String> entry,
    Set<String> selected,
    StateSetter update,
  ) => CheckboxListTile(
    title: Text(entry.value),
    subtitle: Text(
      entry.key == mesh.deviceId
          ? 'Ovaj uređaj'
          : 'Poznat uređaj • veza nije garantovana',
      style: TextStyle(fontSize: _isPhone ? 13 : 10),
    ),
    value: selected.contains(entry.key),
    onChanged: (value) => update(() {
      if (value == true) {
        selected.add(entry.key);
      } else {
        selected.remove(entry.key);
      }
    }),
  );

  Future<void> _createTeam() async {
    await ops.ready;
    if (!mounted) {
      return;
    }
    final name = TextEditingController();
    final selected = <String>{};
    final users = {...mesh.knownDevices, mesh.deviceId: mesh.deviceName}
      ..removeWhere((id, name) => id.isEmpty || name.isEmpty);
    final result = await _safeDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          insetPadding: _isPhone
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          title: const Text('Formiraj tim'),
          content: SizedBox(
            width: 380,
            height: _isPhone ? null : 360,
            child: Column(
              mainAxisSize: _isPhone ? MainAxisSize.min : MainAxisSize.max,
              children: [
                TextField(
                  controller: name,
                  onChanged: (_) => update(() {}),
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(labelText: 'Naziv tima'),
                ),
                if (_isPhone) ...[
                  if (users.isEmpty)
                    _empty('Prvo postavi ime uređaja i poveži učesnike'),
                  for (final entry in users.entries)
                    _teamMemberOption(entry, selected, update),
                ] else
                  Expanded(
                    child: users.isEmpty
                        ? _empty('Prvo postavi ime uređaja i poveži učesnike')
                        : ListView(
                            children: [
                              for (final entry in users.entries)
                                _teamMemberOption(entry, selected, update),
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
    if (result == true) {
      await _run(
        () => ops.publish('team', {
          'id': const Uuid().v4(),
          'name': name.text.trim(),
          'members': selected.toList(),
          'color': blue.toARGB32(),
        }),
      );
    }
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
          scrollable: true,
          insetPadding: _isPhone
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
                if (task.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Dodijeli'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await _run(
        () => ops.publish('mission', {
          'id': const Uuid().v4(),
          'teamId': teamId,
          'members': List.of(ops.teams[teamId]!['members'] as List),
          'task': task.text.trim(),
          'sosId': sosId,
        }),
      );
    }
    task.dispose();
  }

  void _mission(Map<String, dynamic> m) {
    final progress = m['progress'] as Map? ?? {};
    _safeDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding: _isPhone
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
                  if (team != null) {
                    await ops.transmit({'op': 'team', 'data': team});
                  }
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
    if (!recipients.containsKey(_recipient)) {
      _recipient = null;
    }
    final messages = ops.conversation(_recipient);
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
                      style: TextStyle(fontSize: _isPhone ? 14 : 11),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _recipient = v == '' ? null : v),
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? _empty('Nema poruka')
                : ListView(
                    reverse: true,
                    children: [
                      for (final m in messages.reversed)
                        ListTile(
                          dense: !_isPhone,
                          title: Text(
                            '${m['sender']} • ${m['channel'] == 'private' ? 'Privatno' : 'Broadcast'} • ${_time(m['time'])}',
                            style: TextStyle(
                              fontSize: _isPhone ? 13 : 10,
                              color: blue,
                            ),
                          ),
                          subtitle: Text(
                            '${m['text']}',
                            style: TextStyle(fontSize: _isPhone ? 16 : 12),
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
                    readOnly: MediaQuery.sizeOf(context).shortestSide < 600,
                    onTap: MediaQuery.sizeOf(context).shortestSide < 600 ? _composeMessage : null,
                    maxLength: 2000,
                    style: TextStyle(fontSize: _isPhone ? 16 : 14),
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
                  onPressed: _busy ? null : _sendCommunication,
                  icon: const Icon(Icons.send, color: blue),
                ),
              ],
            ),
          ),
        ],
      ),
      showHeader: !_isPhone,
    );
  }

  Future<void> _composeMessage() async {
    await _safeDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(_recipient == null ? 'Broadcast poruka' : 'Poruka: ${_name(_recipient!)}'),
      content: TextField(
        controller: _message, autofocus: true, maxLength: 2000,
        minLines: 1, maxLines: 4,
        decoration: const InputDecoration(hintText: 'Napiši poruku…'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Nazad')),
        FilledButton(onPressed: () {
          Navigator.pop(dialogContext);
          _sendCommunication();
        }, child: const Text('Pošalji')),
      ],
    ));
  }

  Future<void> _sendCommunication() => _run(() async {
    final text = _message.text.trim();
    if (text.isEmpty) { return 'Upiši poruku'; }
    final result = await ops.communicate(text, _recipient);
    if (!result.startsWith('Nije')) { _message.clear(); }
    return result;
  });

  Future<void> _photo() async {
    await _run(() async {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 320,
        maxHeight: 320,
        imageQuality: 25,
      );
      if (file == null) {
        return 'Odabir otkazan';
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 20000 ||
          bytes.length < 3 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8) {
        return 'Odaberi manju JPEG fotografiju (do 20 KB).';
      }
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
                    scrollable: true,
                    insetPadding: _isPhone
                        ? const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 20,
                          )
                        : const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 24,
                          ),
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
        scrollable: true,
        insetPadding: _isPhone
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
              if (name.text.trim().isEmpty) {
                return;
              }
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
    if (ok == true) {
      await ops.addResource({
        'id': const Uuid().v4(),
        'name': name.text.trim(),
        'type': type,
        'status': status,
        'lat': double.tryParse(lat.text),
        'lng': double.tryParse(lng.text),
      });
    }
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
            if (value != null) {
              ops.setReadiness(value);
            }
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
  Widget _phoneEmpty(IconData icon, String title, String detail) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white38),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white60,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _phoneStatusButton(
    String label,
    String value,
    IconData icon,
    Color color,
    VoidCallback tap,
  ) => Expanded(
    child: TextButton(
      onPressed: tap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 44),
        foregroundColor: color,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _phoneIncidents() {
    final entries = ops.incidents.entries
        .where(
          (e) => _sosTab == 0
              ? e.value['status'] != 'resolved'
              : e.value['status'] == 'resolved',
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text('Aktivni ($_activeSosCount)'),
                ),
                const ButtonSegment(value: 1, label: Text('Završeni')),
              ],
              selected: {_sosTab},
              onSelectionChanged: (values) =>
                  setState(() => _sosTab = values.first),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? _phoneEmpty(
                  Icons.health_and_safety_outlined,
                  'Nema SOS događaja',
                  'Primljeni pozivi za pomoć prikazat će se ovdje.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Material(
                      color: panel,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _incident(entry.key, entry.value),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFF4B1520),
                                child: Icon(Icons.sos, color: Colors.redAccent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${entry.value['sender'] ?? 'SOS poziv'}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${entry.value['message'] ?? ''}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_time(entry.value['time'])} • Dodirni za odgovor',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.white38,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _phoneTasks() {
    final missions = ops.missions.values
        .where(
          (m) =>
              !_onlyMyTasks || (m['members'] as List).contains(mesh.deviceId),
        )
        .toList()
        .reversed
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _assign,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.add),
                  label: const Text('Novi zadatak'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Timovi',
                onPressed: () => setState(() => _page = 4),
                icon: const Icon(Icons.groups_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Svi zadaci'),
                  selected: !_onlyMyTasks,
                  onSelected: (_) => setState(() => _onlyMyTasks = false),
                ),
                ChoiceChip(
                  label: const Text('Moji zadaci'),
                  selected: _onlyMyTasks,
                  onSelected: (_) => setState(() => _onlyMyTasks = true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: missions.isEmpty
              ? _phoneEmpty(
                  Icons.assignment_outlined,
                  'Nema zadataka',
                  'Formiraj tim, dodijeli zadatak i prati potvrde članova.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: missions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final mission = missions[index];
                    final progress = mission['progress'] as Map? ?? {};
                    final status =
                        (progress[mesh.deviceId] as Map?)?['status'] ??
                        'Čeka potvrdu';
                    return Material(
                      color: panel,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          '${mission['task']}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${ops.teams[mission['teamId']]?['name'] ?? 'Tim'} • ${progress.length}/${(mission['members'] as List).length} odgovora\n$status',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white60,
                              height: 1.5,
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _mission(mission),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _phoneMore() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Material(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.hub_outlined,
                color: mesh.connectedDevices.isEmpty
                    ? Colors.amber
                    : Colors.greenAccent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mesh.connectedDevices.isEmpty
                          ? 'Nema direktnih veza'
                          : '${mesh.connectedDevices.length} direktnih veza',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ops.teams.length} timova • Pripravnost: ${ops.readiness}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      for (final (page, detail) in [
        (4, 'Formiranje i članovi timova'),
        (5, 'Uređaji i povezivanje'),
        (7, 'Terenske fotografije'),
        (8, 'Direktne veze i poznati uređaji'),
        (9, 'Vozila, dronovi i oprema'),
        (10, 'Mreža, pripravnost i offline mape'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              minVerticalPadding: 14,
              leading: Icon(icons[page], color: blue),
              title: Text(
                labels[page],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                detail,
                style: const TextStyle(fontSize: 13, color: Colors.white54),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => setState(() => _page = page),
            ),
          ),
        ),
    ],
  );

  Widget _phoneSecondary() => switch (_page) {
    2 => _phoneIncidents(),
    3 => _phoneTasks(),
    4 => _teams(),
    5 => _users(),
    6 => _communications(),
    7 => _photos(),
    8 => _network(),
    9 => _resources(),
    10 => _settings(),
    _ => _phoneMore(),
  };

  Widget _phoneShell() {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final short = (_layoutSize ?? MediaQuery.sizeOf(context)).height < 500;
    final title = switch (_page) {
      0 || 1 => 'Situacijska mapa',
      2 => 'SOS centar',
      3 => 'Zadaci',
      6 => 'Poruke',
      11 => 'Više opcija',
      _ => labels[_page],
    };
    return PopScope(
      canPop: _phoneMapSelected,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() => _page = 1);
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          toolbarHeight: short ? 52 : 64,
          leading: IconButton(
            tooltip: 'Nazad u chat',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NRN MESH',
                style: TextStyle(
                  fontSize: 11,
                  color: blue,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Povezani uređaji',
              onPressed: () => setState(() => _page = 5),
              icon: const Icon(Icons.people_outline),
            ),
            IconButton(
              tooltip: 'Aktiviraj SOS',
              onPressed: widget.onSos,
              icon: const Icon(Icons.sos, color: Colors.redAccent),
            ),
          ],
        ),
        bottomNavigationBar: keyboard
            ? null
            : NavigationBarTheme(
                data: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                child: NavigationBar(
                  key: const ValueKey('phone-navigation'),
                  height: 72,
                  backgroundColor: panel,
                  indicatorColor: blue.withValues(alpha: .22),
                  selectedIndex: _phoneNavIndex,
                  onDestinationSelected: (index) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => _page = [1, 2, 3, 6, 11][index]);
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map, color: blue),
                      label: 'Mapa',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: _activeSosCount > 0,
                        label: Text('$_activeSosCount'),
                        child: const Icon(Icons.sos),
                      ),
                      label: 'SOS',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.assignment_outlined),
                      label: 'Zadaci',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.forum_outlined),
                      label: 'Poruke',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      label: 'Više',
                    ),
                  ],
                ),
              ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (ops.storageError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    ops.storageError!,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              if (_phoneMapSelected && !short && !keyboard)
                Material(
                  color: panel,
                  child: Row(
                    children: [
                      _phoneStatusButton(
                        'Veze',
                        '${mesh.connectedDevices.length}',
                        Icons.wifi_tethering,
                        Colors.greenAccent,
                        () => setState(() => _page = 8),
                      ),
                      _phoneStatusButton(
                        'SOS',
                        '$_activeSosCount',
                        Icons.sos,
                        Colors.redAccent,
                        () => setState(() => _page = 2),
                      ),
                      _phoneStatusButton(
                        '',
                        widget.batteryLevel() < 0
                            ? '—'
                            : '${widget.batteryLevel()}%',
                        Icons.battery_std,
                        Colors.white70,
                        () => setState(() => _page = 10),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _phoneMapSelected ? 0 : 1,
                  children: [
                    Padding(padding: const EdgeInsets.all(8), child: _map()),
                    _phoneMapSelected
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                            child: _phoneSecondary(),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboard(double width) {
    if (width < 950) {
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
    }
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    resizeToAvoidBottomInset: false,
    body: SafeArea(
      child: LayoutBuilder(builder: (context, viewport) {
        // Keep the entire operational overview visible on landscape phones.
        const canvas = Size(1600, 900);
        return Center(
          child: FittedBox(
            key: const ValueKey('command-center-overview'),
            fit: BoxFit.contain,
            child: SizedBox(
              width: canvas.width,
              height: canvas.height,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: canvas,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  viewInsets: EdgeInsets.zero,
                  textScaler: TextScaler.noScaling,
                ),
                child: _buildConsole(context),
              ),
            ),
          ),
        );
      }),
    ),
  );

  Widget _buildConsole(BuildContext context) => AnimatedBuilder(
    animation: _changes,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        _layoutSize = constraints.biggest;
        if (_isPhone) {
          return _phoneShell();
        }
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
                onPressed: widget.onOfflineMaps,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('OFFLINE MAPE'),
              ),
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

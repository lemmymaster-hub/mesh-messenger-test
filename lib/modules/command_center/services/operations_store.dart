import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/mesh_message.dart';
import '../../../services/nearby_service.dart';

/// Local operational ledger. Transport submission is never a recipient ACK.
class OperationsStore extends ChangeNotifier {
  OperationsStore(this.transport) {
    _subscription = transport.messages.listen(receive);
    ready = _load();
  }
  final NearbyService transport;
  late final Future<void> ready;
  late final StreamSubscription<MeshMessage> _subscription;
  final Map<String, Map<String, dynamic>> teams = {};
  final Map<String, Map<String, dynamic>> missions = {};
  final Map<String, Map<String, dynamic>> incidents = {};
  final List<Map<String, dynamic>> communications = [];
  final List<Map<String, dynamic>> photos = [];
  final List<Map<String, dynamic>> resources = [];
  final Set<String> _resolved = {};
  final List<MeshMessage> _pending = [];
  bool _loaded = false;
  bool _disposed = false;
  String readiness = 'Redovna';
  String? storageError;
  Future<void> _writes = Future.value();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('nrn_operations_v1');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        for (final pair in [
          (teams, 'teams'),
          (missions, 'missions'),
          (incidents, 'incidents'),
        ]) {
          final source = data[pair.$2];
          if (source is Map) {
            for (final entry in source.entries) {
              if (entry.value is Map)
                pair.$1[entry.key.toString()] = Map<String, dynamic>.from(
                  entry.value,
                );
            }
          }
        }
        for (final pair in [
          (communications, 'communications'),
          (photos, 'photos'),
          (resources, 'resources'),
        ]) {
          final source = data[pair.$2];
          if (source is List)
            pair.$1.addAll(
              source.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        }
        readiness = data['readiness']?.toString() ?? 'Redovna';
        _resolved.addAll((data['resolved'] as List? ?? []).whereType<String>());
      }
    } catch (_) {
      storageError = 'Sačuvani operativni podaci nisu učitani.';
    }
    _loaded = true;
    for (final message in List<MeshMessage>.of(_pending)) {
      receive(message);
    }
    _pending.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> save() {
    final snapshot = jsonEncode({
      'teams': teams,
      'missions': missions,
      'incidents': incidents,
      'communications': communications,
      'photos': photos,
      'resources': resources,
      'readiness': readiness,
      'resolved': _resolved.toList(),
    });
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString('nrn_operations_v1', snapshot))
          throw StateError('write');
        storageError = null;
      } catch (_) {
        storageError = 'Promjene nisu sačuvane na uređaju.';
      }
      if (!_disposed) notifyListeners();
    });
    return _writes;
  }

  void syncIncidents(Map<String, Map<String, dynamic>> live) {
    if (!_loaded) return;
    var changed = false;
    for (final e in live.entries) {
      if (_resolved.contains(e.key)) continue;
      final existing = incidents[e.key];
      if (existing == null) {
        incidents[e.key] = Map.of(e.value);
        changed = true;
      }
    }
    if (changed) {
      unawaited(save());
    }
  }

  void receive(MeshMessage message) {
    if (_disposed) return;
    if (!_loaded) {
      _pending.add(message);
      return;
    }
    try {
      if (message.type == 'sos') {
        final id = message.sosId ?? message.messageId;
        if (!_resolved.contains(id)) {
          incidents[id] = {
            'sosId': id,
            'sender': message.senderName,
            'senderId': message.senderId,
            'message': message.text,
            'lat': message.latitude,
            'lng': message.longitude,
            'time': message.timestamp,
            'status': 'active',
          };
        }
      } else if (message.type == 'sos_cancel') {
        final id = message.sosId;
        if (id != null && incidents[id]?['senderId'] == message.senderId) {
          incidents[id]!['status'] = 'resolved';
          _resolved.add(id);
        }
      } else if (message.type == 'sos_accept' || message.type == 'sos_reject') {
        final incident = incidents[message.sosId];
        if (incident != null) {
          final responses = Map<String, dynamic>.from(
            incident['responses'] as Map? ?? {},
          );
          responses[message.senderId] = message.type;
          incident['responses'] = responses;
        }
      } else if (message.type == 'group' || message.type == 'private') {
        if (message.type == 'private' &&
            message.receiverId != transport.deviceId)
          return;
        communications.add({
          'sender': message.senderName,
          'text': message.text,
          'time': message.timestamp,
          'channel': message.type,
        });
      } else if (message.type == 'command') {
        final decoded = jsonDecode(message.text);
        if (decoded is! Map<String, dynamic>) return;
        if (!_apply(
          decoded,
          message.senderId,
          message.senderName,
          message.timestamp,
        ))
          return;
      } else {
        return;
      }
      _trim();
      notifyListeners();
      unawaited(save());
    } catch (_) {
      /* Invalid operational data never breaks transport reception. */
    }
  }

  bool _apply(Map<String, dynamic> data, String sender, String name, int time) {
    final op = data['op'];
    final body = data['data'];
    if (body is! Map<String, dynamic>) return false;
    final id = body['id'];
    if (id is! String || id.isEmpty || id.length > 100) return false;
    if (op == 'team') {
      if (body['name'] is! String ||
          body['members'] is! List ||
          (body['members'] as List).isEmpty ||
          !(body['members'] as List).every((e) => e is String))
        return false;
      if (teams[id] != null && teams[id]!['owner'] != sender) return false;
      if ((body['name'] as String).trim().isEmpty ||
          (body['name'] as String).length > 80 ||
          (body['members'] as List).length > 100)
        return false;
      final color = body['color'];
      if (color != null && (color is! int || color < 0 || color > 0xffffffff))
        return false;
      teams[id] = {...body, 'owner': sender};
    } else if (op == 'mission') {
      final team = teams[body['teamId']];
      if (team == null || team['owner'] != sender || body['task'] is! String)
        return false;
      if (missions[id] != null) return false;
      missions[id] = {
        ...body,
        'owner': sender,
        'members': List.of(team['members'] as List),
        'progress': <String, dynamic>{},
        'time': time,
      };
    } else if (op == 'progress') {
      final mission = missions[id];
      if (mission == null ||
          ![
            'Prihvaćen',
            'Na putu',
            'Na lokaciji',
            'Završeno',
            'Odbijen',
          ].contains(body['status']))
        return false;
      final members = mission['members'] as List? ?? [];
      if (!members.contains(sender)) return false;
      final progress = Map<String, dynamic>.from(
        mission['progress'] as Map? ?? {},
      );
      if ((progress[sender] as Map?)?['time'] is num &&
          ((progress[sender] as Map)['time'] as num) > time)
        return false;
      progress[sender] = {'status': body['status'], 'time': time, 'name': name};
      mission['progress'] = progress;
    } else if (op == 'photo') {
      if (body['bytes'] is! String || (body['bytes'] as String).length > 27000)
        return false;
      final bytes = base64Decode(body['bytes'] as String);
      if (bytes.length < 3 ||
          bytes.length > 20000 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8)
        return false;
      if (!photos.any((e) => e['id'] == id))
        photos.add({...body, 'sender': name, 'time': time});
    } else {
      return false;
    }
    return true;
  }

  void _trim() {
    if (communications.length > 300)
      communications.removeRange(0, communications.length - 300);
    if (photos.length > 24) photos.removeRange(0, photos.length - 24);
  }

  Future<String> publish(String op, Map<String, dynamic> body) async {
    await ready;
    final data = {'op': op, 'data': body};
    if (transport.deviceId.isEmpty || transport.deviceName.isEmpty) {
      throw StateError('Prvo postavi profil uređaja.');
    }
    // Save work locally even without a peer; user explicitly retries transmission.
    if (!_apply(
      data,
      transport.deviceId,
      transport.deviceName,
      DateTime.now().millisecondsSinceEpoch,
    )) {
      throw StateError(
        'Neispravna akcija ili nemaš pravo izmjene ovog zapisa.',
      );
    }
    _trim();
    notifyListeners();
    await save();
    return transmit(data);
  }

  Future<String> transmit(Map<String, dynamic> data) async {
    final result = await transport.sendCommand(data);
    if (result == null || !result.delivered)
      return 'Sačuvano lokalno • nije poslato';
    return 'Predato vezama: ${result.deliveredCount}/${result.attemptedCount} • čeka odgovor primaoca';
  }

  Future<String> communicate(String text, String? receiver) async {
    final result = receiver == null
        ? await transport.sendMessage(text)
        : await transport.sendPrivateMessage(
            text: text,
            receiverDeviceId: receiver,
          );
    if (result == null || !result.delivered)
      return 'Nije poslato • nema uspješne veze';
    communications.add({
      'sender': 'Ja',
      'text': text,
      'time': DateTime.now().millisecondsSinceEpoch,
      'channel': receiver == null ? 'group' : 'private',
    });
    _trim();
    notifyListeners();
    await save();
    return 'Predato vezama: ${result.deliveredCount}/${result.attemptedCount}';
  }

  Future<void> resolveLocal(String id) async {
    await ready;
    if (incidents[id] != null) incidents[id]!['status'] = 'resolved';
    _resolved.add(id);
    await save();
  }

  Future<void> setReadiness(String value) async {
    await ready;
    readiness = value;
    await save();
  }

  Future<void> addResource(Map<String, dynamic> value) async {
    await ready;
    resources.add(value);
    await save();
  }

  Future<void> removeResource(String id) async {
    await ready;
    resources.removeWhere((e) => e['id'] == id);
    await save();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}

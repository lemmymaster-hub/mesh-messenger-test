import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/mesh_message.dart';
import 'processed_message_cache.dart';

typedef MeshMessageReceivedCallback = void Function(
  MeshMessage message,
  String receivedFromEndpointId,
);

class MeshSendResult {
  const MeshSendResult({
    required this.messageId,
    required this.attemptedCount,
    required this.submittedEndpointIds,
  });

  final String messageId;
  final int attemptedCount;
  final List<String> submittedEndpointIds;
  int get submittedCount => submittedEndpointIds.length;

  int get failedCount => attemptedCount - submittedCount;
  bool get submitted => submittedCount > 0;
}

class NearbyService extends ChangeNotifier {
  final _events = StreamController<MeshMessage>.broadcast(sync: true);
  Stream<MeshMessage> get messages => _events.stream;
  void _devicesChanged() {
    if (_disposed) return;
    onDevicesChanged?.call();
    notifyListeners();
  }

  final Set<String> _connecting = {};
  bool _disposed = false;
  int _session = 0;
  bool _startingAdvertising = false;
  bool _startingDiscovery = false;
  Future<void>? _stopping;
  Future<void>? _identityLoad;
  static const _transport = MethodChannel('ba.noria.nrnmesh/transport');
  bool advertising = false;
  bool discovering = false;
  final uuid = const Uuid();
  final ProcessedMessageCache _processedMessages = ProcessedMessageCache();

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = 'bsl.mesh.test';
  static const int _maxIncomingBytes = 32 * 1024;

  String deviceName = '';
  String deviceRole = 'Volonter';
  String deviceId = '';

  final Map<String, String> foundDevices = {};
  final Map<String, String> connectedDevices = {};
  final Map<String, String> knownDevices = {};
  final Map<String, String> knownDeviceRoles = {};
  final Map<String, String> endpointDeviceIds = {};

  Function(String log)? onLog;

  MeshMessageReceivedCallback? onMessageReceived;

  Function(
    String deviceId,
    String deviceName,
    String deviceRole,
    double latitude,
    double longitude,
    int timestamp,
    int? batteryLevel,
  )?
  onLocationReceived;

  Function()? onDevicesChanged;

  NearbyService();

  String _shortId(String value) {
    return value.length >= 8 ? value.substring(0, 8) : value;
  }

  Future<void> _submitBytes(String endpointId, Uint8List bytes) => _transport
      .invokeMethod<void>('submitBytes', {
        'endpointId': endpointId,
        'bytes': bytes,
      })
      .timeout(const Duration(seconds: 5));

  Future<MeshSendResult> _sendToConnectedPeers(
    MeshMessage message, {
    String? excludeEndpointId,
    required String logLabel,
  }) async {
    final endpointIds = connectedDevices.keys
        .where((endpointId) => endpointId != excludeEndpointId)
        .toList(growable: false);
    final payload = Uint8List.fromList(utf8.encode(message.encode()));
    if (payload.length > _maxIncomingBytes) {
      throw const FormatException('Poruka prelazi 32 KB.');
    }
    final submissions = await Future.wait(
      endpointIds.map((endpointId) async {
        try {
          await _submitBytes(endpointId, payload);
          onLog?.call(
            '$logLabel -> ${connectedDevices[endpointId] ?? endpointId}',
          );
          return endpointId;
        } catch (e) {
          onLog?.call('$logLabel nije predat ka $endpointId: $e');
          return null;
        }
      }),
    );

    return MeshSendResult(
      messageId: message.messageId,
      attemptedCount: endpointIds.length,
      submittedEndpointIds: List.unmodifiable(submissions.whereType<String>()),
    );
  }

  Future<void> connectToDevice(String endpointId) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    if (_disposed ||
        _stopping != null ||
        connectedDevices.containsKey(endpointId) ||
        !_connecting.add(endpointId)) {
      return;
    }
    try {
      await Nearby().requestConnection(
        deviceName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      onLog?.call(
        'Zahtjev za povezivanje poslat: ${foundDevices[endpointId] ?? endpointId}',
      );
    } catch (e) {
      _connecting.remove(endpointId);
      onLog?.call('Greška povezivanja: $e');
    }
  }

  Future<void> sendHello(String endpointId) async {
    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    final hello = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: 'ALL',
      text: '',
      type: 'hello',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _processedMessages.markIfNew(hello.messageId);

    try {
      await _submitBytes(
        endpointId,
        Uint8List.fromList(utf8.encode(hello.encode())),
      );
      onLog?.call('HELLO poslat -> $endpointId');
    } catch (e) {
      onLog?.call('HELLO nije poslat ka $endpointId: $e');
    }
  }

  Future<String?> loadDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    deviceName = prefs.getString('mesh_device_name') ?? '';
    return deviceName.isEmpty ? null : deviceName;
  }

  Future<String> loadDeviceRole() async {
    final prefs = await SharedPreferences.getInstance();
    deviceRole = prefs.getString('mesh_device_role') ?? 'Volonter';
    return deviceRole;
  }

  Future<void> loadOrCreateDeviceId() => _identityLoad ??= _loadIdentity()
      .whenComplete(() => _identityLoad = null);

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('mesh_device_id') ?? '';

    if (deviceId.isEmpty) {
      deviceId = uuid.v4();
      if (!await prefs.setString('mesh_device_id', deviceId)) {
        deviceId = '';
        throw StateError('Identitet uređaja nije sačuvan.');
      }
      onLog?.call('Novi Device ID kreiran');
    } else {
      onLog?.call('Device ID učitan');
    }

    if (deviceName.isNotEmpty && deviceId.isNotEmpty) {
      knownDevices[deviceId] = deviceName;
      knownDeviceRoles[deviceId] = deviceRole;
    }
  }

  Future<void> setDeviceName(String name) async {
    await setDeviceProfile(name: name, role: deviceRole);
  }

  Future<void> setDeviceRole(String role) async {
    await setDeviceProfile(name: deviceName, role: role);
  }

  Future<void> setDeviceProfile({
    required String name,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    deviceName = name.trim();
    deviceRole = role.trim().isEmpty ? 'Volonter' : role.trim();

    await prefs.setString('mesh_device_name', deviceName);
    await prefs.setString('mesh_device_role', deviceRole);

    if (deviceId.isNotEmpty && deviceName.isNotEmpty) {
      knownDevices[deviceId] = deviceName;
      knownDeviceRoles[deviceId] = deviceRole;
      _devicesChanged();
    }
  }

  Future<void> requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    onLog?.call('Permissions zatražene');

    if (deviceId.isNotEmpty && deviceName.isNotEmpty) {
      knownDevices[deviceId] = deviceName;
      knownDeviceRoles[deviceId] = deviceRole;
    }
  }

  Future<void> startAdvertising() async {
    if (_disposed || _stopping != null || advertising || _startingAdvertising) {
      return;
    }
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    final session = _session;
    _startingAdvertising = true;
    try {
      await requestPermissions();
      if (_disposed || session != _session) return;
      final result = await Nearby().startAdvertising(
        deviceName,
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      if (_disposed || session != _session) {
        if (result) await Nearby().stopAdvertising();
        return;
      }
      advertising = result;
      _devicesChanged();
      onLog?.call(
        result ? 'Advertising pokrenut' : 'Advertising nije pokrenut',
      );
    } catch (e) {
      onLog?.call('Greška advertising: $e');
    } finally {
      _startingAdvertising = false;
    }
  }

  Future<void> startDiscovery() async {
    if (_disposed || _stopping != null || discovering || _startingDiscovery) {
      return;
    }
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    final session = _session;
    _startingDiscovery = true;
    try {
      await requestPermissions();
      if (_disposed || session != _session) return;
      final result = await Nearby().startDiscovery(
        deviceName,
        strategy,
        serviceId: serviceId,
        onEndpointFound: (String id, String name, String serviceId) {
          if (_disposed ||
              session != _session ||
              connectedDevices.containsKey(id)) {
            return;
          }
          foundDevices[id] = name;
          onLog?.call('Pronađen uređaj: $name');
          _devicesChanged();
          unawaited(connectToDevice(id));
        },
        onEndpointLost: (String? id) {
          if (!_disposed && session == _session && id != null) {
            foundDevices.remove(id);
            onLog?.call('Uređaj izgubljen: $id');
            _devicesChanged();
          }
        },
      );

      if (_disposed || session != _session) {
        if (result) await Nearby().stopDiscovery();
        return;
      }
      discovering = result;
      _devicesChanged();
      onLog?.call(result ? 'Discovery pokrenut' : 'Discovery nije pokrenut');
    } catch (e) {
      onLog?.call('Greška discovery: $e');
    } finally {
      _startingDiscovery = false;
    }
  }

  Future<void> _onConnectionInitiated(String id, ConnectionInfo info) async {
    if (_disposed || _stopping != null) return;
    _connecting.add(id);
    foundDevices[id] = info.endpointName;
    onLog?.call('Konekcija zatražena od: ${info.endpointName}');

    try {
      await Nearby().acceptConnection(
        id,
        onPayLoadRecieved: (endpointId, payload) {
          if (payload.type == PayloadType.BYTES && payload.bytes != null) {
            _handleIncomingPayload(endpointId, payload.bytes!);
          }
        },
        onPayloadTransferUpdate: (endpointId, update) {},
      );
    } catch (e) {
      _connecting.remove(id);
      onLog?.call('Konekcija nije prihvaćena: $e');
    }
  }

  void _handleIncomingPayload(String endpointId, Uint8List bytes) {
    if (_disposed ||
        _stopping != null ||
        !connectedDevices.containsKey(endpointId)) {
      return;
    }
    onLog?.call('PAYLOAD primljen od $endpointId | bytes: ${bytes.length}');

    if (bytes.length > _maxIncomingBytes) {
      onLog?.call('Prevelik mesh payload je odbačen.');
      return;
    }

    String? rawData;

    try {
      rawData = utf8.decode(bytes, allowMalformed: false);
      final meshMessage = MeshMessage.decode(rawData);

      final endpointIdentity = endpointDeviceIds[endpointId];
      if (meshMessage.senderId == deviceId ||
          (meshMessage.hopCount == 0 &&
              endpointIdentity != null &&
              endpointIdentity != meshMessage.senderId)) {
        onLog?.call('Odbačena poruka sa neusklađenim identitetom uređaja.');
        return;
      }

      if (!_processedMessages.markIfNew(meshMessage.messageId)) {
        onLog?.call('Dupla poruka ignorisana: ${meshMessage.messageId}');
        return;
      }

      var devicesChanged = false;
      if (meshMessage.senderId.isNotEmpty &&
          meshMessage.senderName.isNotEmpty) {
        if (knownDevices[meshMessage.senderId] != meshMessage.senderName) {
          knownDevices[meshMessage.senderId] = meshMessage.senderName;
          devicesChanged = true;
        }

        if (knownDeviceRoles[meshMessage.senderId] != meshMessage.senderRole) {
          knownDeviceRoles[meshMessage.senderId] = meshMessage.senderRole;
          devicesChanged = true;
        }

        onLog?.call(
          'Poznat mesh uređaj: ${meshMessage.senderName} (${meshMessage.senderRole}) | ${_shortId(meshMessage.senderId)} | hop ${meshMessage.hopCount}',
        );

        // Samo direktna poruka sa hopCount 0 smije mijenjati endpoint mapu.
        // Ako je poruka došla preko relay-a, endpointId je zapravo posrednik.
        if (meshMessage.hopCount == 0) {
          if (endpointDeviceIds[endpointId] != meshMessage.senderId) {
            endpointDeviceIds[endpointId] = meshMessage.senderId;
            devicesChanged = true;
          }

          if (connectedDevices[endpointId] != meshMessage.senderName) {
            connectedDevices[endpointId] = meshMessage.senderName;
            devicesChanged = true;
          }
        }
      }

      if (devicesChanged) {
        _devicesChanged();
      }

      final isPrivateMessage = meshMessage.type == 'private';
      final isForMe = !isPrivateMessage || meshMessage.receiverId == deviceId;
      if (isForMe) _events.add(meshMessage);

      if (meshMessage.type == 'hello') {
        onLog?.call(
          'HELLO primljen od: ${meshMessage.senderName} | hop ${meshMessage.hopCount}',
        );

        _relayMessage(meshMessage, endpointId);
        return;
      }

      if (meshMessage.type == 'location') {
        final isMyOwnLocation = meshMessage.senderId == deviceId;

        if (!isMyOwnLocation &&
            meshMessage.latitude != null &&
            meshMessage.longitude != null) {
          onLog?.call(
            'Lokacija primljena: ${meshMessage.senderName} (${meshMessage.senderRole}) | '
            '${meshMessage.latitude}, ${meshMessage.longitude}',
          );

          onLocationReceived?.call(
            meshMessage.senderId,
            meshMessage.senderName.isEmpty
                ? _shortId(meshMessage.senderId)
                : meshMessage.senderName,
            meshMessage.senderRole.isEmpty
                ? 'Volonter'
                : meshMessage.senderRole,
            meshMessage.latitude!,
            meshMessage.longitude!,
            meshMessage.timestamp,
            meshMessage.batteryLevel,
          );
        }

        _relayMessage(meshMessage, endpointId);
        return;
      }

      final isGroupMessage = meshMessage.type == 'group';
      final isSosMessage = meshMessage.type == 'sos';
      final isSosResponse =
          meshMessage.type == 'sos_accept' ||
          meshMessage.type == 'sos_reject' ||
          meshMessage.type == 'sos_cancel';

      if (isForMe &&
          (isGroupMessage ||
              isSosMessage ||
              isSosResponse ||
              isPrivateMessage)) {
        onLog?.call('Primljena mesh poruka: ${meshMessage.messageId}');
        onMessageReceived?.call(meshMessage, endpointId);
      } else {
        onLog?.call(
          'Relay only: ${meshMessage.type} za ${_shortId(meshMessage.receiverId)} | hop ${meshMessage.hopCount}',
        );
      }

      if (!isPrivateMessage || !isForMe) {
        _relayMessage(meshMessage, endpointId);
      }
    } catch (e) {
      if (rawData != null &&
          rawData.trim().isNotEmpty &&
          !rawData.trimLeft().startsWith('{') &&
          !rawData.trimLeft().startsWith('[')) {
        final legacyMessage = MeshMessage(
          messageId: uuid.v4(),
          senderId: endpointDeviceIds[endpointId] ?? endpointId,
          senderName:
              connectedDevices[endpointId] ??
              foundDevices[endpointId] ??
              endpointId,
          receiverId: 'ALL',
          text: rawData,
          type: 'group',
          hopCount: 0,
          maxHops: 0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        onLog?.call('Primljena kompatibilna stara/string poruka.');
        _events.add(legacyMessage);
        onMessageReceived?.call(legacyMessage, endpointId);
        return;
      }

      onLog?.call('Neispravan mesh payload odbačen: $e');
    }
  }

  Future<void> _relayMessage(
    MeshMessage originalMessage,
    String receivedFromEndpointId,
  ) async {
    if (originalMessage.hopCount >= originalMessage.maxHops) {
      onLog?.call('Relay stop: max hops');
      return;
    }

    if (connectedDevices.isEmpty) {
      return;
    }

    final relayedMessage = originalMessage.copyWith(
      hopCount: originalMessage.hopCount + 1,
    );

    try {
      await _sendToConnectedPeers(
        relayedMessage,
        excludeEndpointId: receivedFromEndpointId,
        logLabel: 'Relay ${relayedMessage.hopCount}/${relayedMessage.maxHops}',
      );
    } catch (e) {
      onLog?.call('Relay nije predat: $e');
    }
  }

  void _onConnectionResult(String id, Status status) {
    if (_disposed || _stopping != null) return;
    _connecting.remove(id);
    onLog?.call('Rezultat konekcije $id: $status');

    if (status == Status.CONNECTED) {
      final name = foundDevices[id] ?? connectedDevices[id] ?? id;

      connectedDevices[id] = name;
      foundDevices.remove(id);

      _devicesChanged();
      unawaited(sendHello(id));
    }
  }

  void _onDisconnected(String id) {
    if (_disposed || _stopping != null) return;
    _connecting.remove(id);
    connectedDevices.remove(id);
    endpointDeviceIds.remove(id);
    onLog?.call('Prekinuta konekcija: $id');
    _devicesChanged();
  }

  Future<MeshSendResult?> sendSosResponse({
    required String sosId,
    required String responseType, // sos_accept ili sos_reject
    String reason = '',
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return null;
    }

    if (sosId.trim().isEmpty ||
        (responseType != 'sos_accept' && responseType != 'sos_reject')) {
      onLog?.call('Neispravan SOS odgovor nije poslat.');
      return null;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja za SOS odgovor');
      return null;
    }

    final text = responseType == 'sos_accept'
        ? '$deviceName prihvatio SOS'
        : '$deviceName odbio SOS${reason.isNotEmpty ? ' - $reason' : ''}';

    final meshMessage = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: 'ALL',
      text: text,
      type: responseType,
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      sosId: sosId,
      sosReason: reason,
    );

    _processedMessages.markIfNew(meshMessage.messageId);
    final result = await _sendToConnectedPeers(
      meshMessage,
      logLabel: 'SOS odgovor $responseType',
    );

    return result.submitted ? result : null;
  }

  Future<MeshSendResult?> sendSosMessage({
    double? latitude,
    double? longitude,
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return null;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja za SOS');
      return null;
    }

    final sosId = uuid.v4();

    final hasLocation = latitude != null && longitude != null;
    final locationText = hasLocation
        ? 'Lokacija: $latitude, $longitude\n'
              'Google Maps: https://maps.google.com/?q=$latitude,$longitude'
        : 'Lokacija trenutno nije dostupna.';
    final sosText =
        '🆘 SOS od $deviceName\n'
        'Vrijeme: ${DateTime.now().toLocal()}\n'
        '$locationText';

    final meshMessage = MeshMessage(
      messageId: sosId,
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: 'ALL',
      text: sosText,
      type: 'sos',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      latitude: latitude,
      longitude: longitude,
      sosId: sosId,
    );

    _processedMessages.markIfNew(meshMessage.messageId);
    final result = await _sendToConnectedPeers(meshMessage, logLabel: 'SOS');

    if (!result.submitted) {
      onLog?.call('SOS nije predat nijednoj direktnoj vezi.');
      return null;
    }

    onLog?.call(
      'SOS poslat: $sosId | ${result.submittedCount}/${result.attemptedCount}',
    );
    return result;
  }

  Future<MeshSendResult?> sendSosCancel({required String sosId}) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return null;
    }

    if (sosId.trim().isEmpty) {
      return null;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja za gašenje SOS-a');
      return null;
    }

    final meshMessage = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: 'ALL',
      text: 'Pošiljalac je završio SOS.',
      type: 'sos_cancel',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      sosId: sosId,
    );

    _processedMessages.markIfNew(meshMessage.messageId);
    final result = await _sendToConnectedPeers(
      meshMessage,
      logLabel: 'SOS cancel',
    );

    if (!result.submitted) {
      return null;
    }

    onLog?.call('SOS cancel poslat: $sosId');
    return result;
  }

  Future<MeshSendResult?> sendPrivateMessage({
    required String text,
    required String receiverDeviceId,
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return null;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja');
      return null;
    }

    final meshMessage = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: receiverDeviceId,
      text: text,
      type: 'private',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _processedMessages.markIfNew(meshMessage.messageId);
    return _sendToConnectedPeers(meshMessage, logLabel: 'Privatna poruka');
  }

  Future<MeshSendResult?> sendMessage(String text) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return null;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja');
      return null;
    }

    final meshMessage = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: 'ALL',
      text: text,
      type: 'group',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _processedMessages.markIfNew(meshMessage.messageId);
    return _sendToConnectedPeers(meshMessage, logLabel: 'Grupna poruka');
  }

  Future<void> sendLocationUpdate({
    required double latitude,
    required double longitude,
    required int batteryLevel,
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja za slanje lokacije');
      return;
    }

    final meshMessage = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: 'ALL',
      text: 'LOCATION_UPDATE',
      type: 'location',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      latitude: latitude,
      longitude: longitude,
      batteryLevel: batteryLevel >= 0 && batteryLevel <= 100
          ? batteryLevel
          : null,
    );

    _processedMessages.markIfNew(meshMessage.messageId);
    await _sendToConnectedPeers(
      meshMessage,
      logLabel: 'Lokacija $latitude, $longitude',
    );
  }

  Future<MeshSendResult?> sendCommand(Map<String, dynamic> data) async {
    if (deviceName.isEmpty || connectedDevices.isEmpty) {
      return null;
    }
    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }
    final message = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      senderRole: deviceRole,
      receiverId: 'ALL',
      text: jsonEncode(data),
      type: 'command',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _processedMessages.markIfNew(message.messageId);
    return _sendToConnectedPeers(message, logLabel: 'Operativna poruka');
  }

  Future<void> disconnect(String endpointId) async {
    await Nearby().disconnectFromEndpoint(endpointId);
    _onDisconnected(endpointId);
  }

  Future<void> stopAll() =>
      _stopping ??= _stopTransport().whenComplete(() => _stopping = null);

  Future<void> _stopTransport() async {
    _session++;
    try {
      await Future.wait([
        if (advertising || _startingAdvertising) Nearby().stopAdvertising(),
        if (discovering || _startingDiscovery) Nearby().stopDiscovery(),
        if (connectedDevices.isNotEmpty || _connecting.isNotEmpty)
          Nearby().stopAllEndpoints(),
      ]);
    } finally {
      advertising = false;
      discovering = false;
      _connecting.clear();
      foundDevices.clear();
      connectedDevices.clear();
      endpointDeviceIds.clear();
      _devicesChanged();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    onLog = null;
    unawaited(_events.close());
    unawaited(
      stopAll().catchError((Object error) {
        debugPrint('Nearby shutdown failed: $error');
      }),
    );
    super.dispose();
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/mesh_message.dart';
import 'processed_message_cache.dart';

typedef MeshMessageReceivedCallback =
    void Function(MeshMessage message, String receivedFromEndpointId);

class MeshSendResult {
  const MeshSendResult({
    required this.messageId,
    required this.attemptedCount,
    required this.deliveredCount,
  });

  final String messageId;
  final int attemptedCount;
  final int deliveredCount;

  int get failedCount => attemptedCount - deliveredCount;
  bool get delivered => deliveredCount > 0;
}

class NearbyService {
  final uuid = const Uuid();
  final ProcessedMessageCache _processedMessages = ProcessedMessageCache();

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = 'bsl.mesh.test';
  static const int _maxIncomingBytes = 64 * 1024;

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

  Future<MeshSendResult> _sendToConnectedPeers(
    MeshMessage message, {
    String? excludeEndpointId,
    required String logLabel,
  }) async {
    final endpointIds = connectedDevices.keys
        .where((endpointId) => endpointId != excludeEndpointId)
        .toList(growable: false);
    final payload = Uint8List.fromList(utf8.encode(message.encode()));
    var deliveredCount = 0;

    for (final endpointId in endpointIds) {
      try {
        await Nearby().sendBytesPayload(endpointId, payload);
        deliveredCount++;
        onLog?.call(
          '$logLabel -> ${connectedDevices[endpointId] ?? endpointId}',
        );
      } catch (e) {
        onLog?.call('$logLabel nije poslat ka $endpointId: $e');
      }
    }

    return MeshSendResult(
      messageId: message.messageId,
      attemptedCount: endpointIds.length,
      deliveredCount: deliveredCount,
    );
  }

  Future<void> connectToDevice(String endpointId) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
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
      await Nearby().sendBytesPayload(
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

  Future<void> loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('mesh_device_id') ?? '';

    if (deviceId.isEmpty) {
      deviceId = uuid.v4();
      await prefs.setString('mesh_device_id', deviceId);
      onLog?.call('Novi Device ID kreiran');
    } else {
      onLog?.call('Device ID učitan');
    }

    if (deviceName.isNotEmpty && deviceId.isNotEmpty) {
      knownDevices[deviceId] = deviceName;
      knownDeviceRoles[deviceId] = deviceRole;
    }
  }

  Future<bool> hasInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();

    return !connectivityResult.contains(ConnectivityResult.none);
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
      onDevicesChanged?.call();
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
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    await requestPermissions();

    try {
      final result = await Nearby().startAdvertising(
        deviceName,
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      onLog?.call(
        result ? 'Advertising pokrenut' : 'Advertising nije pokrenut',
      );
    } catch (e) {
      onLog?.call('Greška advertising: $e');
    }
  }

  Future<void> startDiscovery() async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    await requestPermissions();

    try {
      final result = await Nearby().startDiscovery(
        deviceName,
        strategy,
        serviceId: serviceId,
        onEndpointFound: (String id, String name, String serviceId) {
          foundDevices[id] = name;
          onLog?.call('Pronađen uređaj: $name');
          onDevicesChanged?.call();
        },
        onEndpointLost: (String? id) {
          if (id != null) {
            foundDevices.remove(id);
            onLog?.call('Uređaj izgubljen: $id');
            onDevicesChanged?.call();
          }
        },
      );

      onLog?.call(result ? 'Discovery pokrenut' : 'Discovery nije pokrenut');
    } catch (e) {
      onLog?.call('Greška discovery: $e');
    }
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    onLog?.call('Konekcija zatražena od: ${info.endpointName}');

    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _handleIncomingPayload(endpointId, payload.bytes!);
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {},
    );
  }

  void _handleIncomingPayload(String endpointId, Uint8List bytes) {
    onLog?.call('PAYLOAD primljen od $endpointId | bytes: ${bytes.length}');

    if (bytes.length > _maxIncomingBytes) {
      onLog?.call('Prevelik mesh payload je odbačen.');
      return;
    }

    String? rawData;

    try {
      rawData = utf8.decode(bytes, allowMalformed: false);
      final meshMessage = MeshMessage.decode(rawData);

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

        if (knownDeviceRoles[meshMessage.senderId] !=
            meshMessage.senderRole) {
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
        onDevicesChanged?.call();
      }

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
      final isPrivateMessage = meshMessage.type == 'private';
      final isSosMessage = meshMessage.type == 'sos';
      final isSosResponse =
          meshMessage.type == 'sos_accept' ||
          meshMessage.type == 'sos_reject' ||
          meshMessage.type == 'sos_cancel';

      final isForMe =
          isGroupMessage ||
          isSosMessage ||
          isSosResponse ||
          (isPrivateMessage && meshMessage.receiverId == deviceId);

      if (isForMe) {
        onLog?.call('Primljena mesh poruka: ${meshMessage.messageId}');
        onMessageReceived?.call(meshMessage, endpointId);
      } else {
        onLog?.call(
          'Relay only: ${meshMessage.type} za ${_shortId(meshMessage.receiverId)} | hop ${meshMessage.hopCount}',
        );
      }

      _relayMessage(meshMessage, endpointId);
    } catch (e) {
      if (rawData != null &&
          rawData.trim().isNotEmpty &&
          !rawData.trimLeft().startsWith('{')) {
        final legacyMessage = MeshMessage(
          messageId: uuid.v4(),
          senderId: endpointDeviceIds[endpointId] ?? endpointId,
          senderName: connectedDevices[endpointId] ??
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

    if (connectedDevices.isEmpty) return;

    final relayedMessage = originalMessage.copyWith(
      hopCount: originalMessage.hopCount + 1,
    );

    await _sendToConnectedPeers(
      relayedMessage,
      excludeEndpointId: receivedFromEndpointId,
      logLabel:
          'Relay ${relayedMessage.hopCount}/${relayedMessage.maxHops}',
    );
  }

  void _onConnectionResult(String id, Status status) {
    onLog?.call('Rezultat konekcije $id: $status');

    if (status == Status.CONNECTED) {
      final name = foundDevices[id] ?? connectedDevices[id] ?? id;

      connectedDevices[id] = name;
      foundDevices.remove(id);

      onDevicesChanged?.call();
      sendHello(id);
    }
  }

  void _onDisconnected(String id) {
    connectedDevices.remove(id);
    endpointDeviceIds.remove(id);
    onLog?.call('Prekinuta konekcija: $id');
    onDevicesChanged?.call();
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

    return result.delivered ? result : null;
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
    final result = await _sendToConnectedPeers(
      meshMessage,
      logLabel: 'SOS',
    );

    if (!result.delivered) {
      onLog?.call('SOS nije isporučen nijednom direktnom uređaju.');
      return null;
    }

    onLog?.call(
      'SOS poslat: $sosId | ${result.deliveredCount}/${result.attemptedCount}',
    );
    return result;
  }

  Future<MeshSendResult?> sendSosCancel({required String sosId}) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return null;
    }

    if (sosId.trim().isEmpty) return null;

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
      text: 'Pomoć pružena ugroženoj osobi.',
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

    if (!result.delivered) return null;

    onLog?.call('SOS cancel poslat: $sosId');
    return result;
  }

  Future<void> sendPrivateMessage({
    required String text,
    required String receiverDeviceId,
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja');
      return;
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
    await _sendToConnectedPeers(meshMessage, logLabel: 'Privatna poruka');

    onLog?.call(
      'Privatna poruka poslata za receiverId: $receiverDeviceId | ${meshMessage.messageId}',
    );
  }

  Future<void> sendMessage(String text) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja');
      return;
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
    await _sendToConnectedPeers(meshMessage, logLabel: 'Grupna poruka');

    onLog?.call('Mesh poruka poslata: ${meshMessage.messageId}');
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
      batteryLevel: batteryLevel,
    );

    _processedMessages.markIfNew(meshMessage.messageId);
    await _sendToConnectedPeers(
      meshMessage,
      logLabel: 'Lokacija $latitude, $longitude',
    );
  }

  Future<void> stopAll() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();

    foundDevices.clear();
    connectedDevices.clear();
    endpointDeviceIds.clear();

    onLog?.call('Sve zaustavljeno');
    onDevicesChanged?.call();
  }

  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
  }
}

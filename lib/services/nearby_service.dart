import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/mesh_message.dart';

class NearbyService {
  final uuid = const Uuid();
  final Set<String> processedMessages = {};

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = 'bsl.mesh.test';

  String deviceName = '';
  String deviceId = '';

  final Map<String, String> foundDevices = {};
  final Map<String, String> connectedDevices = {};
  final Map<String, String> knownDevices = {};
  final Map<String, String> endpointDeviceIds = {};

  Function(String log)? onLog;

  Function(
    String message,
    String endpointId,
    String senderName,
    String type,
  )? onMessageReceived;

  Function()? onDevicesChanged;

  NearbyService();

  String _shortId(String value) {
    return value.length >= 8 ? value.substring(0, 8) : value;
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
      receiverId: 'ALL',
      text: '',
      type: 'hello',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await Nearby().sendBytesPayload(
      endpointId,
      Uint8List.fromList(utf8.encode(hello.encode())),
    );

    onLog?.call('HELLO poslat -> $endpointId');
  }

  Future<String?> loadDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    deviceName = prefs.getString('mesh_device_name') ?? '';
    return deviceName.isEmpty ? null : deviceName;
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
    }
  }

  Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    deviceName = name.trim();

    await prefs.setString('mesh_device_name', deviceName);

    if (deviceId.isNotEmpty && deviceName.isNotEmpty) {
      knownDevices[deviceId] = deviceName;
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

      onLog?.call(result ? 'Advertising pokrenut' : 'Advertising nije pokrenut');
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
    final rawData = utf8.decode(bytes);

    try {
      final meshMessage = MeshMessage.decode(rawData);

      if (processedMessages.contains(meshMessage.messageId)) {
        onLog?.call('Dupla poruka ignorisana: ${meshMessage.messageId}');
        return;
      }

      processedMessages.add(meshMessage.messageId);

      if (meshMessage.senderId.isNotEmpty && meshMessage.senderName.isNotEmpty) {
        knownDevices[meshMessage.senderId] = meshMessage.senderName;

        onLog?.call(
          'Poznat mesh uređaj: ${meshMessage.senderName} | ${_shortId(meshMessage.senderId)} | hop ${meshMessage.hopCount}',
        );

        // Samo direktna poruka sa hopCount 0 smije mijenjati endpoint mapu.
        // Ako je poruka došla preko relay-a, endpointId je zapravo posrednik.
        if (meshMessage.hopCount == 0) {
          endpointDeviceIds[endpointId] = meshMessage.senderId;
          connectedDevices[endpointId] = meshMessage.senderName;
        }

        onDevicesChanged?.call();
      }

      if (meshMessage.type == 'hello') {
        onLog?.call(
          'HELLO primljen od: ${meshMessage.senderName} | hop ${meshMessage.hopCount}',
        );

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

        if (meshMessage.senderName.isNotEmpty && meshMessage.hopCount == 0) {
          connectedDevices[endpointId] = meshMessage.senderName;
          onDevicesChanged?.call();
        }

        onMessageReceived?.call(
          meshMessage.text,
          endpointId,
          meshMessage.senderName.isEmpty ? endpointId : meshMessage.senderName,
          meshMessage.type,
        );
      } else {
        onLog?.call(
          'Relay only: ${meshMessage.type} za ${_shortId(meshMessage.receiverId)} | hop ${meshMessage.hopCount}',
        );
      }

      _relayMessage(meshMessage, endpointId);
    } catch (e) {
      onLog?.call('Primljena stara/string poruka: $rawData');

      onMessageReceived?.call(
        rawData,
        endpointId,
        endpointId,
        'group',
      );
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

    final relayedMessage = MeshMessage(
      messageId: originalMessage.messageId,
      senderId: originalMessage.senderId,
      senderName: originalMessage.senderName,
      receiverId: originalMessage.receiverId,
      text: originalMessage.text,
      type: originalMessage.type,
      hopCount: originalMessage.hopCount + 1,
      maxHops: originalMessage.maxHops,
      timestamp: originalMessage.timestamp,
      latitude: originalMessage.latitude,
      longitude: originalMessage.longitude,
      sosId: originalMessage.sosId,
      sosReason: originalMessage.sosReason,
    );

    final encodedMessage = relayedMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      if (endpointId == receivedFromEndpointId) continue;

      await Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(encodedMessage)),
      );

      onLog?.call(
        'Relay -> $endpointId | hop ${relayedMessage.hopCount}/${relayedMessage.maxHops}',
      );
    }
  }

  void _onConnectionResult(String id, Status status) {
    onLog?.call('Rezultat konekcije $id: $status');

    if (status == Status.CONNECTED) {
      final name = foundDevices[id] ?? connectedDevices[id] ?? id;

      connectedDevices.removeWhere((key, value) => value == name);
      connectedDevices[id] = name;
      foundDevices.remove(id);

      onDevicesChanged?.call();
      sendHello(id);
    }
  }

  void _onDisconnected(String id) {
    connectedDevices.remove(id);
    onLog?.call('Prekinuta konekcija: $id');
    onDevicesChanged?.call();
  }

  Future<void> sendSosResponse({
    required String sosId,
    required String responseType, // sos_accept ili sos_reject
    String reason = '',
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja za SOS odgovor');
      return;
    }

    final text = responseType == 'sos_accept'
        ? '$deviceName prihvatio SOS'
        : '$deviceName odbio SOS${reason.isNotEmpty ? ' - $reason' : ''}';

    final meshMessage = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      receiverId: 'ALL',
      text: text,
      type: responseType,
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      sosId: sosId,
      sosReason: reason,
    );

    processedMessages.add(meshMessage.messageId);
    final encodedMessage = meshMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      try {
        await Nearby().sendBytesPayload(
          endpointId,
          Uint8List.fromList(utf8.encode(encodedMessage)),
        );

        onLog?.call(
          'SOS odgovor poslat: $responseType -> ${connectedDevices[endpointId]}',
        );
      } catch (e) {
        onLog?.call('Greška SOS odgovora ka $endpointId: $e');
      }
    }
  }

  Future<void> sendSosMessage({
    required double latitude,
    required double longitude,
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja za SOS');
      return;
    }

    final sosId = uuid.v4();

    final sosText =
        '🆘 SOS od $deviceName\n'
        'Vrijeme: ${DateTime.now().toLocal()}\n'
        'Lokacija: $latitude, $longitude\n'
        'Google Maps: https://maps.google.com/?q=$latitude,$longitude';

    final meshMessage = MeshMessage(
      messageId: sosId,
      senderId: deviceId,
      senderName: deviceName,
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

    processedMessages.add(meshMessage.messageId);
    final encodedMessage = meshMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      try {
        onLog?.call('SOS slanje ka: ${connectedDevices[endpointId]} | $endpointId');

        await Nearby().sendBytesPayload(
          endpointId,
          Uint8List.fromList(utf8.encode(encodedMessage)),
        );

        onLog?.call('SOS payload poslat ka: ${connectedDevices[endpointId]}');
      } catch (e) {
        onLog?.call('Greška SOS slanja ka $endpointId: $e');
      }
    }

    onLog?.call('SOS poslat: $sosId');
  }

  Future<void> sendSosCancel({
    required String sosId,
  }) async {
    if (deviceName.isEmpty) {
      onLog?.call('Prvo unesi ime uređaja.');
      return;
    }

    if (deviceId.isEmpty) {
      await loadOrCreateDeviceId();
    }

    if (connectedDevices.isEmpty) {
      onLog?.call('Nema povezanih uređaja za gašenje SOS-a');
      return;
    }

    final meshMessage = MeshMessage(
      messageId: uuid.v4(),
      senderId: deviceId,
      senderName: deviceName,
      receiverId: 'ALL',
      text: 'Pomoć pružena ugroženoj osobi.',
      type: 'sos_cancel',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      sosId: sosId,
    );

    processedMessages.add(meshMessage.messageId);
    final encodedMessage = meshMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      try {
        await Nearby().sendBytesPayload(
          endpointId,
          Uint8List.fromList(utf8.encode(encodedMessage)),
        );

        onLog?.call('SOS ugašen poslato ka: ${connectedDevices[endpointId]}');
      } catch (e) {
        onLog?.call('Greška slanja SOS cancel ka $endpointId: $e');
      }
    }

    onLog?.call('SOS cancel poslat: $sosId');
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
      receiverId: receiverDeviceId,
      text: text,
      type: 'private',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    processedMessages.add(meshMessage.messageId);
    final encodedMessage = meshMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      await Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(encodedMessage)),
      );
    }

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
      receiverId: 'ALL',
      text: text,
      type: 'group',
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    processedMessages.add(meshMessage.messageId);
    final encodedMessage = meshMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      await Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(encodedMessage)),
      );
    }

    onLog?.call('Mesh poruka poslata: ${meshMessage.messageId}');
  }

  Future<void> stopAll() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();

    foundDevices.clear();
    connectedDevices.clear();

    onLog?.call('Sve zaustavljeno');
    onDevicesChanged?.call();
  }

  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
  }
}

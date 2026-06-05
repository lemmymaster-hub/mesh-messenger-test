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
  Function(String log)? onLog;

  Function(
    String message,
    String endpointId,
    String senderName,
  )? onMessageReceived;

  Function()? onDevicesChanged;

  NearbyService();

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

      await prefs.setString(
        'mesh_device_id',
        deviceId,
      );

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
    if (deviceId.isNotEmpty) {
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

          Nearby().requestConnection(
            deviceName,
            id,
            onConnectionInitiated: _onConnectionInitiated,
            onConnectionResult: _onConnectionResult,
            onDisconnected: _onDisconnected,
          );
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
    final rawData = String.fromCharCodes(bytes);

    try {
      final meshMessage = MeshMessage.decode(rawData);

      if (processedMessages.contains(meshMessage.messageId)) {
        onLog?.call('Dupla poruka ignorisana: ${meshMessage.messageId}');
        return;
      }

      processedMessages.add(meshMessage.messageId);
if (meshMessage.senderId.isNotEmpty &&
    meshMessage.senderName.isNotEmpty) {
  knownDevices[meshMessage.senderId] = meshMessage.senderName;
  onDevicesChanged?.call();
}
      final isForMe =
          meshMessage.receiverId == 'ALL' || meshMessage.receiverId == deviceId;

      if (isForMe) {
        onLog?.call(
          'Primljena mesh poruka: ${meshMessage.messageId}',
        );
if (meshMessage.senderName.isNotEmpty) {
  connectedDevices[endpointId] = meshMessage.senderName;
  onDevicesChanged?.call();
}
        onMessageReceived?.call(
          meshMessage.text,
          endpointId,
          meshMessage.senderName.isEmpty ? endpointId : meshMessage.senderName,
        );
      } else {
        onLog?.call(
          'Relay only: ${meshMessage.messageId}',
        );
      }

      _relayMessage(
        meshMessage,
        endpointId,
      );
    } catch (e) {
      onLog?.call('Primljena stara/string poruka: $rawData');

      onMessageReceived?.call(
        rawData,
        endpointId,
        endpointId,
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
      hopCount: originalMessage.hopCount + 1,
      maxHops: originalMessage.maxHops,
      timestamp: originalMessage.timestamp,
    );

    final encodedMessage = relayedMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      if (endpointId == receivedFromEndpointId) continue;

      await Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(encodedMessage.codeUnits),
      );

      onLog?.call(
        'Relay -> $endpointId | hop ${relayedMessage.hopCount}/${relayedMessage.maxHops}',
      );
    }
  }

  void _onConnectionResult(String id, Status status) {
    onLog?.call('Rezultat konekcije $id: $status');

    if (status == Status.CONNECTED) {
      connectedDevices[id] = foundDevices[id] ?? id;
      onDevicesChanged?.call();
    }
  }

  void _onDisconnected(String id) {
    connectedDevices.remove(id);
    onLog?.call('Prekinuta konekcija: $id');
    onDevicesChanged?.call();
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
      hopCount: 0,
      maxHops: 5,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    processedMessages.add(meshMessage.messageId);

    final encodedMessage = meshMessage.encode();

    for (final endpointId in connectedDevices.keys) {
      await Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(encodedMessage.codeUnits),
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
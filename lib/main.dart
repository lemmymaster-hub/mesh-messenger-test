import 'dart:math';
import 'screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';

void main() {
  runApp(const MeshMessengerApp());
}

class MeshMessengerApp extends StatelessWidget {
  const MeshMessengerApp({super.key});

 @override
Widget build(BuildContext context) {
  return MaterialApp(
    title: 'Mesh Messenger Test',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const ChatScreen(),
  );
}
}

class MeshHomeScreen extends StatefulWidget {
  const MeshHomeScreen({super.key});

  @override
  State<MeshHomeScreen> createState() => _MeshHomeScreenState();
}

class _MeshHomeScreenState extends State<MeshHomeScreen> {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = 'bsl.mesh.test';

  late final String deviceName;

  bool advertising = false;
  bool discovering = false;

  final List<String> logs = [];
  final Map<String, String> foundDevices = {};
  final Map<String, String> connectedDevices = {};

  @override
  void initState() {
    super.initState();
    deviceName = 'BSL-${Random().nextInt(9999)}';
    addLog('Uređaj: $deviceName');
  }

  void addLog(String text) {
    setState(() {
      logs.insert(0, '${DateTime.now().toString().substring(11, 19)}  $text');
    });
  }

  Future<void> requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    addLog('Permissions zatražene');
  }

  Future<void> startAdvertising() async {
    await requestPermissions();

    try {
      bool result = await Nearby().startAdvertising(
        deviceName,
        strategy,
        onConnectionInitiated: (String id, ConnectionInfo info) {
          addLog('Konekcija zatražena od: ${info.endpointName}');
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              if (payload.type == PayloadType.BYTES) {
                final message = String.fromCharCodes(payload.bytes!);
                addLog('Primljena poruka od $endpointId: $message');
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {},
          );
        },
        onConnectionResult: (String id, Status status) {
          addLog('Rezultat konekcije $id: $status');

          if (status == Status.CONNECTED) {
            setState(() {
              connectedDevices[id] = foundDevices[id] ?? id;
            });
          }
        },
        onDisconnected: (String id) {
          addLog('Prekinuta konekcija: $id');
          setState(() {
            connectedDevices.remove(id);
          });
        },
        serviceId: serviceId,
      );

      setState(() {
        advertising = result;
      });

      addLog(result ? 'Advertising pokrenut' : 'Advertising nije pokrenut');
    } catch (e) {
      addLog('Greška advertising: $e');
    }
  }

  Future<void> startDiscovery() async {
    await requestPermissions();

    try {
      bool result = await Nearby().startDiscovery(
        deviceName,
        strategy,
        onEndpointFound: (String id, String name, String serviceId) {
          addLog('Pronađen uređaj: $name');
          setState(() {
            foundDevices[id] = name;
          });

          Nearby().requestConnection(
            deviceName,
            id,
            onConnectionInitiated: (String id, ConnectionInfo info) {
              addLog('Prihvatam konekciju sa: ${info.endpointName}');
              Nearby().acceptConnection(
                id,
                onPayLoadRecieved: (endpointId, payload) {
                  if (payload.type == PayloadType.BYTES) {
                    final message = String.fromCharCodes(payload.bytes!);
                    addLog('Primljena poruka od $endpointId: $message');
                  }
                },
                onPayloadTransferUpdate: (endpointId, update) {},
              );
            },
            onConnectionResult: (String id, Status status) {
              addLog('Rezultat konekcije $id: $status');

              if (status == Status.CONNECTED) {
                setState(() {
                  connectedDevices[id] = foundDevices[id] ?? id;
                });
              }
            },
            onDisconnected: (String id) {
              addLog('Diskonektovan: $id');
              setState(() {
                connectedDevices.remove(id);
              });
            },
          );
        },
        onEndpointLost: (String? id) {
          addLog('Uređaj izgubljen: $id');
          if (id != null) {
            setState(() {
              foundDevices.remove(id);
            });
          }
        },
        serviceId: serviceId,
      );

      setState(() {
        discovering = result;
      });

      addLog(result ? 'Discovery pokrenut' : 'Discovery nije pokrenut');
    } catch (e) {
      addLog('Greška discovery: $e');
    }
  }

  Future<void> stopAll() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();

    setState(() {
      advertising = false;
      discovering = false;
      foundDevices.clear();
      connectedDevices.clear();
    });

    addLog('Sve zaustavljeno');
  }

  Future<void> sendTestMessage() async {
    if (connectedDevices.isEmpty) {
      addLog('Nema povezanih uređaja');
      return;
    }

    for (final endpointId in connectedDevices.keys) {
      final message = 'Pozdrav sa $deviceName';
      await Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(message.codeUnits),
      );
      addLog('Poslata poruka ka $endpointId');
    }
  }

  @override
  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foundList = foundDevices.entries.toList();
    final connectedList = connectedDevices.entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Messenger Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                title: Text(deviceName),
                subtitle: Text(
                  'Advertising: ${advertising ? "ON" : "OFF"} | Discovery: ${discovering ? "ON" : "OFF"}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: startAdvertising,
                    child: const Text('Start Advertising'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: startDiscovery,
                    child: const Text('Start Discovery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: sendTestMessage,
                    child: const Text('Pošalji test'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: stopAll,
                    child: const Text('Stop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Pronađeni uređaji: ${foundList.length}'),
            ),
            ...foundList.map(
              (e) => ListTile(
                dense: true,
                leading: const Icon(Icons.bluetooth_searching),
                title: Text(e.value),
                subtitle: Text(e.key),
              ),
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Povezani uređaji: ${connectedList.length}'),
            ),
            ...connectedList.map(
              (e) => ListTile(
                dense: true,
                leading: const Icon(Icons.bluetooth_connected),
                title: Text(e.value),
                subtitle: Text(e.key),
              ),
            ),
            const Divider(),
            const Align(alignment: Alignment.centerLeft, child: Text('Log:')),
            Expanded(
              child: ListView.builder(
                reverse: false,
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  return Text(
                    logs[index],
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

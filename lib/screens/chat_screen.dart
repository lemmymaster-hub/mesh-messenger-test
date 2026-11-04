import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'dart:async';

import '../models/chat_message.dart';
import '../modules/command_center/services/operations_store.dart';
import '../services/nearby_service.dart';

import 'package:audioplayers/audioplayers.dart';

import 'map/mesh_map_screen.dart';

import 'package:battery_plus/battery_plus.dart';

import '../modules/command_center/screens/command_center_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final NearbyService nearbyService;
  late final OperationsStore _operations;
  final ValueNotifier<int> _meshLive = ValueNotifier(0);
  void _changed() {
    _operations.syncIncidents(meshSosLocations);
    _meshLive.value++;
  }

  final Battery _battery = Battery();
  late final AnimationController _sosPulseController;
  late final Animation<double> _sosPulseAnimation;
  final AudioPlayer _sosAudioPlayer = AudioPlayer();
  final List<ChatMessage> _messages = [];
  final List<String> _logs = [];
  final Map<String, Map<String, dynamic>> meshUserLocations = {};
  final Map<String, Map<String, dynamic>> meshSosLocations = {};
  bool showNameEditor = false;
  String selectedRole = 'Volonter';

  final List<String> availableRoles = [
    'Komandant',
    'Operater',
    'Vatrogasac',
    'Policija',
    'GSS',
    'CK',
    'Volonter',
  ];

  String? selectedPrivateDeviceId;
  String? selectedPrivateDeviceName;
  bool sosActive = false;
  bool incomingSosActive = false;
  bool _sosModalDismissed = false;
  bool sosAlarmActive = false;
  bool _changingSos = false;
  bool _respondingToSos = false;
  Position? _latestPosition;
  int _alarmGeneration = 0;
  Future<void> _alarmAudio = Future.value();
  Timer? sosAlarmRepeatTimer;
  Timer? sosAlarmStopTimer;
  Timer? locationBroadcastTimer;
  String incomingSosSender = '';
  String incomingSosMessage = '';
  String? incomingSosId;
  bool _locationBroadcastInProgress = false;

  int _batteryLevel = -1;
  int sosSentCount = 0;
  int sosAcceptedCount = 0;
  int sosPendingCount = 0;
  int sosRejectedCount = 0;

  String? activeSosId;
  String? pinnedSosStatus;
  String? pinnedSosTitle;
  String? pinnedSosMessage;
  String? pinnedSosSender;
  String? pinnedSosTime;
  void _showConnectedDeviceOptions(String endpointId, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A23),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.message, color: Colors.greenAccent),
                title: Text(
                  'Pošalji privatnu poruku: $name',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  final id = nearbyService.endpointDeviceIds[endpointId];
                  if (id == null) {
                    _sosFeedback(
                      'Identitet uređaja još nije poznat. Sačekaj razmjenu profila.',
                    );
                    return;
                  }
                  setState(() {
                    selectedPrivateDeviceName = name;
                    selectedPrivateDeviceId = id;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.redAccent),
                title: Text(
                  'Diskonektuj se od: $name',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await nearbyService.disconnect(endpointId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadBatteryLevel();
    _sosPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _sosPulseAnimation = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _sosPulseController, curve: Curves.easeInOut),
    );
    nearbyService = NearbyService();
    _operations = OperationsStore(nearbyService);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final savedName = await nearbyService.loadDeviceName();
        final role = await nearbyService.loadDeviceRole();
        await nearbyService.loadOrCreateDeviceId();
        await _operations.ready;
        if (!mounted) return;

        setState(() {
          if (availableRoles.contains(role)) selectedRole = role;
          for (final entry in _operations.incidents.entries) {
            final incident = entry.value;
            if (incident['status'] == 'resolved') continue;
            meshSosLocations[entry.key] = Map.of(incident);
            if (incident['senderId'] == nearbyService.deviceId &&
                ((incident['time'] as int?) ?? 0) >=
                    ((meshSosLocations[activeSosId]?['time'] as int?) ?? 0)) {
              activeSosId = entry.key;
            }
          }
          sosActive = activeSosId != null;
          if (sosActive) {
            sosSentCount =
                meshSosLocations[activeSosId]?['submittedCount'] as int? ?? 0;
            _updateSosResponseCounts();
            _setPinnedSosCard(
              status: sosAcceptedCount > 0 ? 'accepted' : 'active',
              title: sosAcceptedCount > 0
                  ? '🚑 POMOĆ NA PUTU'
                  : '🆘 AKTIVAN SOS',
              message:
                  meshSosLocations[activeSosId]?['message']?.toString() ?? '',
              sender: nearbyService.deviceName,
            );
            _sosPulseController.repeat(reverse: true);
          }
          showNameEditor = savedName == null;
          _addSystemMessage(
            savedName == null
                ? 'Otvori profil i unesi ime uređaja.'
                : 'Uređaj: ${nearbyService.deviceName} ($selectedRole)',
          );
        });
        if (_selectNextIncomingSos()) _startIncomingSosAlarm();
        if (savedName != null) await _startMesh();
      } catch (error) {
        if (mounted) {
          setState(() => _addSystemMessage('Pokretanje nije uspjelo: $error'));
        }
      }
    });

    nearbyService.onLog = (log) {
      if (!mounted) {
        return;
      }
      setState(() {
        _logs.insert(0, log);
        if (_logs.length > 500) {
          _logs.removeRange(500, _logs.length);
        }
      });
    };

    nearbyService.onLocationReceived =
        (
          deviceId,
          deviceName,
          deviceRole,
          latitude,
          longitude,
          timestamp,
          batteryLevel,
        ) {
          if (!mounted) {
            return;
          }

          if (((meshUserLocations[deviceId]?['time'] as num?)?.toInt() ?? 0) >
              timestamp) {
            return;
          }
          setState(() {
            meshUserLocations[deviceId] = {
              'deviceId': deviceId,
              'deviceName': deviceName,
              'role': deviceRole,
              'lat': latitude,
              'lng': longitude,
              'time': timestamp,
              'battery': batteryLevel ?? -1,
            };

            _changed();
            _logs.insert(
              0,
              '📍 Lokacija primljena od $deviceName | $latitude, $longitude',
            );
          });
        };

    nearbyService.onMessageReceived = (meshMessage, endpointId) {
      if (!mounted) {
        return;
      }

      final message = meshMessage.text;
      final type = meshMessage.type;
      final fallbackSenderName = meshMessage.senderId.length >= 8
          ? meshMessage.senderId.substring(0, 8)
          : meshMessage.senderId;
      final senderName = meshMessage.senderName.isEmpty
          ? fallbackSenderName
          : meshMessage.senderName;
      final incidentId =
          meshMessage.sosId ?? (type == 'sos' ? meshMessage.messageId : null);
      final incident = _operations.incidents[incidentId];
      var refreshAlarm = false;
      setState(() {
        switch (type) {
          case 'sos':
            if (incident != null &&
                incident['status'] == 'active' &&
                !meshSosLocations.containsKey(incidentId)) {
              meshSosLocations[incidentId!] = Map.of(incident);
              _addSosPublicLog('🆘 $senderName aktivirao SOS.');
              refreshAlarm = !incomingSosActive;
            }
          case 'sos_cancel':
            if (incident?['status'] == 'resolved' &&
                meshSosLocations.remove(incidentId) != null) {
              _addSosPublicLog('✅ $senderName završio SOS.');
              if (incomingSosId == incidentId) {
                refreshAlarm = true;
              }
            }
          case 'sos_accept':
          case 'sos_reject':
            if (activeSosId != null &&
                activeSosId == incidentId &&
                (incident?['responseTimes'] as Map?)?[meshMessage.senderId] ==
                    meshMessage.timestamp) {
              _updateSosResponseCounts();
              if (sosAcceptedCount > 0) {
                _setPinnedSosCard(
                  status: 'accepted',
                  title: '🚑 POMOĆ NA PUTU',
                  message: '$sosAcceptedCount odgovor(a) o prihvatanju SOS-a.',
                  sender: nearbyService.deviceName,
                );
              } else {
                _setPinnedSosCard(
                  status: 'active',
                  title: '🆘 AKTIVAN SOS',
                  message: 'Čeka se prihvatanje SOS-a.',
                  sender: nearbyService.deviceName,
                );
              }
              _addSosPublicLog(message);
            }
          case 'private':
            if (selectedPrivateDeviceId != meshMessage.senderId) {
              _addSystemMessage('Nova direktna poruka od $senderName.');
            }
          case 'group':
            _messages.add(
              ChatMessage(
                text: message,
                isMe: false,
                time: DateTime.now(),
                senderName: senderName,
              ),
            );
        }
      });
      if (refreshAlarm) {
        if (_selectNextIncomingSos()) {
          _startIncomingSosAlarm();
        } else if (!incomingSosActive) {
          _stopIncomingSosAlarm();
        }
      }
      _changed();
      _scrollToBottom();
    };

    nearbyService.onDevicesChanged = () {
      if (!mounted) {
        return;
      }

      _syncLocationBroadcastWithConnections();
      _changed();
      setState(() {});
    };
  }

  void _addSystemMessage(String text) {
    _messages.add(
      ChatMessage(
        text: text,
        isMe: false,
        time: DateTime.now(),
        senderName: 'Sistem',
      ),
    );
  }

  Future<void> _loadBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;

      if (!mounted) {
        return;
      }

      setState(() {
        _batteryLevel = level;
        _meshLive.value++;
      });
    } catch (_) {}
  }

  void _addSosPublicLog(String text) {
    _messages.add(
      ChatMessage(
        text: text,
        isMe: false,
        time: DateTime.now(),
        senderName: '🆘 SOS status',
      ),
    );
  }

  void _setPinnedSosCard({
    required String status,
    required String title,
    required String message,
    required String sender,
  }) {
    pinnedSosStatus = status;
    pinnedSosTitle = title;
    pinnedSosMessage = message;
    pinnedSosSender = sender;
    pinnedSosTime = _formatTime(DateTime.now());
  }

  void _updateSosResponseCounts() {
    final incident = _operations.incidents[activeSosId];
    final responses = incident?['responses'] as Map? ?? {};
    sosAcceptedCount = responses.values
        .where((value) => value == 'sos_accept')
        .length;
    sosRejectedCount = responses.values
        .where((value) => value == 'sos_reject')
        .length;
    final directPeers = incident?['submittedPeerIds'] as List? ?? [];
    sosPendingCount = directPeers
        .where((id) => !responses.containsKey(id))
        .length;
  }

  bool _selectNextIncomingSos() {
    final current = _operations.incidents[incomingSosId];
    bool needsResponse(Map<String, dynamic>? incident) =>
        incident != null &&
        incident['status'] == 'active' &&
        incident['senderId'] != nearbyService.deviceId &&
        (incident['responses'] as Map?)?[nearbyService.deviceId] == null;
    if (incomingSosActive && needsResponse(current)) return false;

    for (final entry in _operations.incidents.entries) {
      if (!needsResponse(entry.value)) continue;
      setState(() {
        incomingSosId = entry.key;
        incomingSosSender =
            entry.value['sender']?.toString() ?? 'Nepoznat uređaj';
        incomingSosMessage = entry.value['message']?.toString() ?? '';
        incomingSosActive = true;
        _sosModalDismissed = false;
      });
      return true;
    }
    setState(() {
      incomingSosId = null;
      incomingSosActive = false;
    });
    return false;
  }

  void _advanceIncomingSos(String id) {
    if (!mounted || incomingSosId != id) return;
    if (_selectNextIncomingSos()) {
      _startIncomingSosAlarm();
    } else if (!incomingSosActive) {
      _stopIncomingSosAlarm();
    }
  }

  void _startIncomingSosAlarm() {
    sosAlarmRepeatTimer?.cancel();
    _playIncomingSosAlarmCycle();
    sosAlarmRepeatTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _playIncomingSosAlarmCycle(),
    );
  }

  void _queueAlarmAudio(Future<void> Function() action) {
    _alarmAudio = _alarmAudio.then((_) => action()).catchError((Object error) {
      if (mounted) _sosFeedback('Zvuk SOS alarma nije dostupan: $error');
    });
  }

  void _playIncomingSosAlarmCycle() {
    if (!mounted || !incomingSosActive) return;
    final generation = ++_alarmGeneration;
    sosAlarmStopTimer?.cancel();
    setState(() => sosAlarmActive = true);
    _sosPulseController.repeat(reverse: true);
    _queueAlarmAudio(() async {
      if (!mounted || generation != _alarmGeneration) return;
      await _sosAudioPlayer.stop();
      await _sosAudioPlayer.setReleaseMode(ReleaseMode.loop);
      if (!mounted || generation != _alarmGeneration) return;
      await _sosAudioPlayer.play(AssetSource('sounds/sos_siren.mp3'));
    });
    unawaited(HapticFeedback.heavyImpact().catchError((Object _) {}));
    sosAlarmStopTimer = Timer(const Duration(seconds: 30), _silenceIncomingSos);
  }

  void _silenceIncomingSos() {
    _alarmGeneration++;
    sosAlarmStopTimer?.cancel();
    if (mounted) {
      setState(() => sosAlarmActive = false);
      if (!sosActive) {
        _sosPulseController.stop();
        _sosPulseController.reset();
      }
    }
    _queueAlarmAudio(_sosAudioPlayer.stop);
  }

  void _stopIncomingSosAlarm() {
    sosAlarmRepeatTimer?.cancel();
    _silenceIncomingSos();
  }

  Future<void> _startMesh() async {
    if (!mounted) return;
    await nearbyService.startAdvertising();
    if (mounted) await nearbyService.startDiscovery();
  }

  Future<void> _saveDeviceName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    try {
      await nearbyService.setDeviceProfile(name: name, role: selectedRole);
      await nearbyService.loadOrCreateDeviceId();
      if (!mounted) return;
      setState(() {
        showNameEditor = false;
        _addSystemMessage('Ime uređaja: $name | Uloga: $selectedRole');
      });
      await _startMesh();
    } catch (error) {
      if (mounted) _sosFeedback('Profil nije sačuvan: $error');
    }
  }

  void _sosFeedback(String text) {
    if (!mounted) return;
    setState(() => _addSystemMessage(text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<Position?> _sosPosition() async {
    bool recent(Position? position) =>
        position != null &&
        DateTime.now().difference(position.timestamp).abs() <=
            const Duration(minutes: 2);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      if (recent(_latestPosition)) return _latestPosition;
      final cached = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 1),
        onTimeout: () => null,
      );
      if (recent(cached)) return cached;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _activateSos() async {
    if (_changingSos || sosActive) return;
    if (nearbyService.connectedDevices.isEmpty) {
      _sosFeedback('SOS nije poslat. Nema direktno povezanih mesh uređaja.');
      return;
    }
    _changingSos = true;
    try {
      final position = await _sosPosition();
      if (!mounted) return;
      final directIds = Map.of(nearbyService.endpointDeviceIds);
      final result = await nearbyService.sendSosMessage(
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      if (!mounted) return;
      if (result == null) {
        _sosFeedback(
          'SOS nije predat mesh vezi. Provjeri veze i pokušaj ponovo.',
        );
        return;
      }

      final location = position == null
          ? 'Lokacija nije dostupna'
          : 'Lokacija: ${position.latitude}, ${position.longitude}';
      setState(() {
        sosActive = true;
        sosSentCount = result.submittedCount;
        activeSosId = result.messageId;
        meshSosLocations[result.messageId] = {
          'lat': position?.latitude,
          'lng': position?.longitude,
          'time': DateTime.now().millisecondsSinceEpoch,
          'message': 'Lokalno aktiviran SOS\n$location',
          'sender': nearbyService.deviceName,
          'senderId': nearbyService.deviceId,
          'sosId': result.messageId,
          'status': 'active',
          'submittedCount': result.submittedCount,
          'submittedPeerIds': result.submittedEndpointIds
              .map((endpoint) => directIds[endpoint])
              .whereType<String>()
              .toSet()
              .toList(),
        };
        _changed();
        _updateSosResponseCounts();
        _setPinnedSosCard(
          status: 'active',
          title: '🆘 AKTIVAN SOS',
          message: 'Predato mesh vezi • prijem nije potvrđen\n$location',
          sender: nearbyService.deviceName,
        );
      });
      _sosPulseController.repeat(reverse: true);
      _sosFeedback('SOS predat mesh vezi • prijem nije potvrđen. $location');
    } catch (error) {
      _sosFeedback('Slanje SOS-a nije završeno: $error');
    } finally {
      _changingSos = false;
    }
  }

  Future<void> _cancelSos() async {
    final id = activeSosId;
    if (id == null || _changingSos) return;
    _changingSos = true;
    try {
      final result = await nearbyService.sendSosCancel(sosId: id);
      if (!mounted) return;
      if (result == null) {
        _sosFeedback('Završetak SOS-a nije predat. SOS ostaje aktivan.');
        return;
      }
      await _operations.resolveLocal(id);
      if (!mounted) return;
      setState(() {
        sosActive = false;
        activeSosId = null;
        meshSosLocations.remove(id);
        sosSentCount = 0;
        _updateSosResponseCounts();
        _setPinnedSosCard(
          status: 'finished',
          title: '✅ SOS ZAVRŠEN',
          message: 'Završetak predat mesh vezi • prijem nije potvrđen.',
          sender: nearbyService.deviceName,
        );
      });
      if (!sosAlarmActive) {
        _sosPulseController.stop();
        _sosPulseController.reset();
      }
      _changed();
      _sosFeedback('Završetak SOS-a predat mesh vezi • prijem nije potvrđen.');
    } catch (error) {
      _sosFeedback('Završetak SOS-a nije uspio: $error');
    } finally {
      _changingSos = false;
    }
  }

  bool _sendingChat = false;
  Future<void> _sendMessage() async {
    if (_sendingChat) {
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    final privateMode = selectedPrivateDeviceName != null;
    final receiverId = selectedPrivateDeviceId;
    if (privateMode && receiverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Identitet primaoca još nije poznat. Sačekaj HELLO razmjenu.',
          ),
        ),
      );
      return;
    }
    _sendingChat = true;
    try {
      final result = privateMode
          ? await nearbyService.sendPrivateMessage(
              text: text,
              receiverDeviceId: receiverId!,
            )
          : await nearbyService.sendMessage(text);
      if (!mounted) {
        return;
      }
      if (result == null || !result.submitted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Poruka nije poslata. Provjeri mesh veze.'),
          ),
        );
        return;
      }
      setState(() {
        if (!privateMode) {
          _messages.add(
            ChatMessage(
              text: text,
              isMe: true,
              time: DateTime.now(),
              senderName: 'Ja',
            ),
          );
        }
        _logs.insert(
          0,
          'Poruka predata direktnim vezama: ${result.submittedCount}/${result.attemptedCount}; prijem nije potvrđen.',
        );
      });
      await _operations.recordOutgoing(text, privateMode ? receiverId : null);
      if (!mounted) {
        return;
      }
      if (_controller.text.trim() == text) _controller.clear();
      setState(() {});
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Poruka nije poslata: $e')));
      }
    } finally {
      _sendingChat = false;
    }
  }

  void _syncLocationBroadcastWithConnections() {
    if (nearbyService.connectedDevices.isEmpty) {
      locationBroadcastTimer?.cancel();
      locationBroadcastTimer = null;
      return;
    }

    _startLocationBroadcast();
  }

  void _startLocationBroadcast() {
    if (locationBroadcastTimer?.isActive ?? false) {
      return;
    }

    unawaited(_broadcastMyLocation());

    locationBroadcastTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_broadcastMyLocation()),
    );
  }

  Future<void> _broadcastMyLocation() async {
    if (nearbyService.connectedDevices.isEmpty ||
        _locationBroadcastInProgress) {
      return;
    }

    _locationBroadcastInProgress = true;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      _latestPosition = position;
      await _loadBatteryLevel();
      if (!mounted) return;

      await nearbyService.sendLocationUpdate(
        latitude: position.latitude,
        longitude: position.longitude,
        batteryLevel: _batteryLevel,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        meshUserLocations[nearbyService.deviceId] = {
          'deviceId': nearbyService.deviceId,
          'deviceName': nearbyService.deviceName,
          'role': selectedRole,
          'lat': position.latitude,
          'lng': position.longitude,
          'time': DateTime.now().millisecondsSinceEpoch,
          'battery': _batteryLevel,
          'isLocal': true,
        };
        _changed();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _logs.insert(0, 'Greška slanja lokacije: $e');
      });
    } finally {
      _locationBroadcastInProgress = false;
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) {
        return;
      }
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _sosButton() {
    final shouldPulse = sosActive || sosAlarmActive;

    final button = GestureDetector(
      onTap: sosActive ? _cancelSos : _activateSos,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF5A5A), Color(0xFFD90000), Color(0xFF7A0000)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 18,
              offset: const Offset(5, 7),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(-3, -3),
            ),
            if (shouldPulse)
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: 0.95),
                blurRadius: 35,
                spreadRadius: 8,
              ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 2,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF7777), Color(0xFFE00000), Color(0xFF9B0000)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: Text(
              sosActive ? 'STOP' : 'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    offset: Offset(1, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!shouldPulse) {
      return button;
    }

    return AnimatedBuilder(
      animation: _sosPulseAnimation,
      builder: (context, child) {
        return Transform.scale(scale: _sosPulseAnimation.value, child: child);
      },
      child: button,
    );
  }

  Future<bool> _respondToIncomingSos({
    required String responseType,
    String reason = '',
  }) async {
    final id = incomingSosId;
    if (id == null || _respondingToSos) return false;
    _respondingToSos = true;
    try {
      final result = await nearbyService.sendSosResponse(
        sosId: id,
        responseType: responseType,
        reason: reason,
      );
      if (!mounted) return false;
      if (result == null) {
        _sosFeedback(
          'SOS odgovor nije predat. Provjeri mesh veze i pokušaj ponovo.',
        );
        return false;
      }

      await _operations.recordSosResponse(id, responseType);
      if (!mounted) return false;
      _advanceIncomingSos(id);
      _sosFeedback('SOS odgovor predat mesh vezi • prijem nije potvrđen.');
      return true;
    } catch (error) {
      _sosFeedback('SOS odgovor nije predat: $error');
      return false;
    } finally {
      _respondingToSos = false;
    }
  }

  Future<void> _showRejectSosDialog() async {
    final id = incomingSosId;
    if (id == null) return;

    String selectedReason = 'Nisam u mogućnosti da pomognem';
    String customReason = '';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151A23),
              title: const Text(
                'Odbij SOS',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: selectedReason,
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedReason = value);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        value: 'Nisam u mogućnosti da pomognem',
                        activeColor: Colors.redAccent,
                        title: const Text(
                          'Nisam u mogućnosti da pomognem',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'Mislim da je lažni SOS',
                        activeColor: Colors.redAccent,
                        title: const Text(
                          'Mislim da je lažni SOS',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'Drugi razlog',
                        activeColor: Colors.redAccent,
                        title: const Text(
                          'Drugi razlog',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      if (selectedReason == 'Drugi razlog')
                        TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Unesi razlog...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                          onChanged: (value) {
                            customReason = value.trim();
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Nazad'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final reason = selectedReason == 'Drugi razlog'
                        ? customReason
                        : selectedReason;

                    if (reason.isEmpty) {
                      return;
                    }

                    Navigator.of(dialogContext).pop(reason);
                  },
                  child: const Text('Potvrdi'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || result.isEmpty) {
      return;
    }

    if (incomingSosId != id) return;
    await _respondToIncomingSos(responseType: 'sos_reject', reason: result);
  }

  Widget _pinnedSosCard() {
    if (pinnedSosStatus == null || pinnedSosStatus == 'active') {
      return const SizedBox.shrink();
    }

    Color borderColor = Colors.redAccent;
    Color backgroundColor = const Color(0xFF2A0505);

    if (pinnedSosStatus == 'accepted') {
      borderColor = Colors.orangeAccent;
      backgroundColor = const Color(0xFF2A1A05);
    } else if (pinnedSosStatus == 'finished') {
      borderColor = Colors.greenAccent;
      backgroundColor = const Color(0xFF052A12);
    } else if (pinnedSosStatus == 'expired') {
      borderColor = Colors.amberAccent;
      backgroundColor = const Color(0xFF2A2205);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pinnedSosTitle ?? '',
            style: TextStyle(
              color: borderColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (pinnedSosSender != null)
            Text(
              'Pošiljalac: $pinnedSosSender',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          if (pinnedSosTime != null)
            Text(
              'Vrijeme: $pinnedSosTime',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          const SizedBox(height: 6),
          Text(
            pinnedSosMessage ?? '',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _sosModal() {
    if (!incomingSosActive || _sosModalDismissed) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2A0505),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🚨 HITAN SOS POZIV 🚨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  incomingSosSender,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      incomingSosMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await _respondToIncomingSos(
                            responseType: 'sos_accept',
                          );
                        },
                        child: const Text('PRIHVATI'),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: _showRejectSosDialog,
                        child: const Text('ODBIJ'),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() => _sosModalDismissed = true),
                  child: const Text('Odgovori kasnije'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _incomingSosPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0505),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🆘 SOS - $incomingSosSender',
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            incomingSosMessage,
            maxLines: selectedPrivateDeviceName != null ? 3 : 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (selectedPrivateDeviceName == null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () async {
                        await _respondToIncomingSos(responseType: 'sos_accept');
                      },
                      child: const Text(
                        'PRIHVATI',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: _showRejectSosDialog,
                      child: const Text(
                        'ODBIJ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sosStatusPanel() {
    return Container(
      height: 70,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Predato na $sosSentCount direktnih veza',
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Prihvatilo $sosAcceptedCount | Odbilo $sosRejectedCount',
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Čeka direktni odgovor: $sosPendingCount',
            style: const TextStyle(
              color: Colors.amberAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkStatusBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF151A23),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, size: 16, color: Colors.white70),
          const SizedBox(width: 4),

          Text(
            nearbyService.deviceName.isEmpty
                ? 'Nije podešeno'
                : '${nearbyService.deviceName} ($selectedRole)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),

          const Spacer(),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${nearbyService.connectedDevices.length} uređ.',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '📡 MESH',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactDeviceStatusPanel() {
    final directDevices = nearbyService.connectedDevices.entries.toList();

    final foundDevices = nearbyService.foundDevices.entries
        .where(
          (entry) => !nearbyService.connectedDevices.containsKey(entry.key),
        )
        .toList();
    final directIds = nearbyService.endpointDeviceIds.values.toSet();
    final indirectDevices = nearbyService.knownDevices.entries
        .where(
          (entry) =>
              entry.key != nearbyService.deviceId &&
              !directIds.contains(entry.key),
        )
        .toList();

    final hasAnyDevice =
        directDevices.isNotEmpty ||
        foundDevices.isNotEmpty ||
        indirectDevices.isNotEmpty;

    return Container(
      height: 82,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: hasAnyDevice
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...directDevices.map(
                    (entry) => _miniDeviceCard(
                      name: entry.value,
                      color: Colors.greenAccent,
                      icon: Icons.smartphone,
                      onTap: () =>
                          _showConnectedDeviceOptions(entry.key, entry.value),
                    ),
                  ),
                  ...foundDevices.map(
                    (entry) => _miniDeviceCard(
                      name: entry.value,
                      color: Colors.amberAccent,
                      icon: Icons.smartphone,
                      onTap: () async {
                        await nearbyService.connectToDevice(entry.key);
                      },
                    ),
                  ),
                  ...indirectDevices.map(
                    (entry) => _miniDeviceCard(
                      name: entry.value,
                      color: Colors.lightBlueAccent,
                      icon: Icons.smartphone,
                      onTap: () {
                        setState(() {
                          selectedPrivateDeviceId = entry.key;
                          selectedPrivateDeviceName = entry.value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            )
          : const Center(
              child: Text(
                'Nema uređaja u blizini',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }

  Widget _miniDeviceCard({
    required String name,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.65)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatArea() {
    return Expanded(
      child: Column(
        children: [
          _pinnedSosCard(),

          if (incomingSosActive) _incomingSosPanel(),

          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];

                return Align(
                  alignment: msg.isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isMe
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(msg.isMe ? 16 : 0),
                        bottomRight: Radius.circular(msg.isMe ? 0 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: msg.isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (msg.senderName != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              msg.senderName!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Text(
                          msg.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(msg.time),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _privateChatPanel({bool fill = false}) {
    if (selectedPrivateDeviceName == null) {
      return const SizedBox.shrink();
    }

    final id = selectedPrivateDeviceId;
    final messages = id == null
        ? const <Map<String, dynamic>>[]
        : _operations.conversation(id);
    return Container(
      height: fill
          ? null
          : MediaQuery.of(context).viewInsets.bottom > 0
          ? 120
          : 220,
      width: double.infinity,
      color: const Color(0xFF0B1220),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: Colors.blue.withValues(alpha: 0.15),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Privatni chat: $selectedPrivateDeviceName',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.blueAccent),
                  onPressed: () {
                    setState(() {
                      selectedPrivateDeviceName = null;
                      selectedPrivateDeviceId = null;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isMe = message['senderId'] == nearbyService.deviceId;

                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.all(9),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message['text']?.toString() ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
        color: const Color(0xFF151A23),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: selectedPrivateDeviceName == null
                      ? 'Unesi mesh poruku...'
                      : 'Privatna poruka za $selectedPrivateDeviceName...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0E1117),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFF2563EB),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    locationBroadcastTimer?.cancel();
    sosAlarmRepeatTimer?.cancel();
    sosAlarmStopTimer?.cancel();
    _controller.dispose();
    _nameController.dispose();
    _scrollController.dispose();
    _sosPulseController.dispose();
    _alarmGeneration++;
    _queueAlarmAudio(_sosAudioPlayer.dispose);
    _operations.dispose();
    _meshLive.dispose();
    nearbyService.dispose();
    super.dispose();
  }

  Future<void> _openCommandCenter() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) { return; }
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommandCenterScreen(
            meshUserLocations: meshUserLocations,
            meshSosLocations: meshSosLocations,
            batteryLevel: () => _batteryLevel,
            transport: nearbyService,
            operations: _operations,
            live: _meshLive,
            onSosResponded: _advanceIncomingSos,
            onSos: _activateSos,
            onCancelSos: _cancelSos,
            onOfflineMaps: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MeshMapScreen(
                  meshUserLocations: meshUserLocations,
                  meshSosLocations: meshSosLocations,
                  live: _meshLive,
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _editPhoneProfile() async {
    _nameController.text = nearbyService.deviceName;
    var role = selectedRole;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Profil uređaja',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Ime uređaja'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Uloga'),
                  items: [
                    for (final value in availableRoles)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      update(() => role = value);
                    }
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (_nameController.text.trim().isEmpty) {
                      return;
                    }
                    setState(() => selectedRole = role);
                    await _saveDeviceName();
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                  child: const Text('Sačuvaj profil'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _phoneDevices() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const ListTile(
          title: Text(
            'Uređaji',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        for (final entry in nearbyService.connectedDevices.entries)
          ListTile(
            leading: const Icon(Icons.link, color: Colors.greenAccent),
            title: Text(entry.value),
            subtitle: const Text('Direktna veza'),
            onTap: () {
              Navigator.pop(context);
              _showConnectedDeviceOptions(entry.key, entry.value);
            },
          ),
        for (final entry in nearbyService.foundDevices.entries)
          ListTile(
            leading: const Icon(Icons.bluetooth_searching),
            title: Text(entry.value),
            trailing: TextButton(
              onPressed: () {
                Navigator.pop(context);
                nearbyService.connectToDevice(entry.key);
              },
              child: const Text('Poveži'),
            ),
          ),
        if (nearbyService.connectedDevices.isEmpty &&
            nearbyService.foundDevices.isEmpty)
          const ListTile(
            title: Text('Nema otkrivenih uređaja'),
            subtitle: Text('Pokreni povezivanje kroz meni gore desno.'),
          ),
      ],
    ),
  );

  Widget _phoneChatMenu() => PopupMenuButton<String>(
    tooltip: 'Opcije chata',
    onSelected: (value) async {
      if (value == 'profile') {
        await _editPhoneProfile();
      }
      if (value == 'connect') {
        await _startMesh();
      }
      if (value == 'map' && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeshMapScreen(
              meshUserLocations: meshUserLocations,
              meshSosLocations: meshSosLocations,
              live: _meshLive,
            ),
          ),
        );
      }
      if (value == 'logs' && mounted) {
        showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Dijagnostika mreže',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              for (final log in _logs.take(100))
                ListTile(
                  title: Text(log, style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
        );
      }
      if (value == 'sos') {
        if (sosActive) {
          await _cancelSos();
        } else {
          await _activateSos();
        }
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'profile', child: Text('Profil uređaja')),
      const PopupMenuItem(value: 'connect', child: Text('Pokreni povezivanje')),
      const PopupMenuItem(value: 'map', child: Text('Offline mapa')),
      PopupMenuItem(
        value: 'sos',
        child: Text(sosActive ? 'Završi moj SOS' : 'Pošalji SOS'),
      ),
      const PopupMenuItem(value: 'logs', child: Text('Dijagnostika mreže')),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final phone =
        screen.width < 700 || (screen.width < 1100 && screen.height < 500);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final connectedCount = nearbyService.connectedDevices.length;
    final deviceName = nearbyService.deviceName.isEmpty
        ? 'Nije podešeno'
        : nearbyService.deviceName;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0E1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151A23),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NRN Mesh Chat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            Text(
              '$deviceName • $selectedRole | Povezano: $connectedCount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          if (phone) ...[
            IconButton(
              tooltip: 'Komandni centar',
              onPressed: _openCommandCenter,
              icon: const Icon(
                Icons.dashboard_outlined,
                color: Colors.lightBlueAccent,
              ),
            ),
            _phoneChatMenu(),
          ] else ...[
            IconButton(
              tooltip: 'Promijeni ime',
              onPressed: () {
                setState(() {
                  _nameController.text = nearbyService.deviceName;
                  showNameEditor = !showNameEditor;
                });
              },
              icon: const Icon(Icons.edit, color: Colors.white),
            ),
            IconButton(
              tooltip: 'Auto connect',
              onPressed: _startMesh,
              icon: const Icon(Icons.hub, color: Colors.white),
            ),

            IconButton(
              tooltip: 'Mapa',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MeshMapScreen(
                      meshUserLocations: meshUserLocations,
                      meshSosLocations: meshSosLocations,
                      live: _meshLive,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map, color: Colors.white),
            ),
            IconButton(
              tooltip: 'Command Center',
              onPressed: _openCommandCenter,
              icon: const Icon(Icons.dashboard, color: Colors.lightBlueAccent),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (phone && showNameEditor)
                TextButton.icon(
                  onPressed: _editPhoneProfile,
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Postavi profil uređaja'),
                ),
              if (showNameEditor && !phone)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFF151A23),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Unesi ime uređaja...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0E1117),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        dropdownColor: const Color(0xFF151A23),
                        iconEnabledColor: Colors.white70,
                        decoration: InputDecoration(
                          labelText: 'Uloga u akciji',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF0E1117),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        items: availableRoles.map((role) {
                          return DropdownMenuItem<String>(
                            value: role,
                            child: Text(role),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            selectedRole = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveDeviceName,
                          child: const Text('SAČUVAJ'),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!phone) _networkStatusBar(),
              if (phone && !keyboard)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    _sosButton(),
                    const SizedBox(width: 18),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sosActive ? 'SOS JE AKTIVAN' : 'HITNI SOS POZIV',
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        const Text('Pritisni crveno dugme za slanje poziva mesh uređajima.', style: TextStyle(fontSize: 12)),
                        TextButton.icon(onPressed: _phoneDevices,
                          icon: const Icon(Icons.people_outline),
                          label: Text('Uređaji ($connectedCount)')),
                      ],
                    )),
                  ]),
                ),
              if (!phone)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _sosButton(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: sosActive
                            ? _sosStatusPanel()
                            : _compactDeviceStatusPanel(),
                      ),
                    ],
                  ),
                ),

              if (phone && selectedPrivateDeviceName != null) ...[
                if (incomingSosActive && _sosModalDismissed)
                  TextButton.icon(
                    onPressed: () => setState(() => _sosModalDismissed = false),
                    icon: const Icon(Icons.sos, color: Colors.redAccent),
                    label: const Text('Otvori SOS poziv'),
                  ),
                Expanded(child: _privateChatPanel(fill: true)),
              ]
              else
                _chatArea(),

              if (_logs.isNotEmpty && !phone)
                ExpansionTile(
                  collapsedBackgroundColor: const Color(0xFF151A23),
                  backgroundColor: const Color(0xFF151A23),
                  title: const Text(
                    'Mesh log',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  children: _logs.take(6).map((log) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        log,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                        ),
                      ),
                    );
                  }).toList(),
                ),

              if (!phone) _privateChatPanel(),
              _inputBar(),
            ],
          ),
          _sosModal(),
        ],
      ),
    );
  }
}

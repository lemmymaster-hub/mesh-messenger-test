import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/nearby_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'map/mesh_map_screen.dart';
import 'package:battery_plus/battery_plus.dart';

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
  final Battery _battery = Battery();
  late final AnimationController _sosPulseController;
  late final Animation<double> _sosPulseAnimation;
  final AudioPlayer _sosAudioPlayer = AudioPlayer();
  final List<ChatMessage> _messages = [];
  final List<String> _logs = [];
  final List<ChatMessage> _privateMessages = [];
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
  String? selectedPrivateEndpointId;
  bool showSosModal = false;
  bool sosActive = false;
  bool incomingSosActive = false;
  bool sosAlarmActive = false;
  bool internetAvailable = false;
  Timer? sosAlarmRepeatTimer;
  Timer? sosAlarmStopTimer;
  Timer? locationBroadcastTimer;
  String incomingSosSender = '';
  String incomingSosMessage = '';
  String? incomingSosId;

  int _batteryLevel = 0;
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
                  setState(() {
                    selectedPrivateEndpointId = endpointId;
                    selectedPrivateDeviceName = name;
                    selectedPrivateDeviceId =
                        nearbyService.endpointDeviceIds[endpointId];
                    _privateMessages.clear();
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.redAccent),
                title: Text(
                  'Diskonektuj se od: $name',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final savedName = await nearbyService.loadDeviceName();
      await nearbyService.loadOrCreateDeviceId();
      await _loadSelectedRole();
      internetAvailable = await nearbyService.hasInternetConnection();
      if (!mounted) return;

      if (savedName == null) {
        _addSystemMessage('Klikni ✏️ gore desno i unesi ime uređaja.');
        _addSystemMessage('ID: ${nearbyService.deviceId.substring(0, 8)}');
        _addSystemMessage('Mesh chat spreman.');
        showNameEditor = true;
      } else {
        _addSystemMessage(
          'Uređaj: ${nearbyService.deviceName} ($selectedRole)',
        );
        _addSystemMessage('ID: ${nearbyService.deviceId.substring(0, 8)}');
        _addSystemMessage('Mesh chat spreman.');

        await nearbyService.startAdvertising();
        await Future.delayed(const Duration(seconds: 1));
        await nearbyService.startDiscovery();
        _startLocationBroadcast();
      }

      setState(() {});
    });

    nearbyService.onLog = (log) {
      if (!mounted) return;
      setState(() {
        _logs.insert(0, log);
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
          if (!mounted) return;

          setState(() {
            meshUserLocations[deviceName] = {
              'role': deviceRole,
              'lat': latitude,
              'lng': longitude,
              'time': timestamp,
              'battery': batteryLevel ?? 0,
            };

            _logs.insert(
              0,
              '📍 Lokacija primljena od $deviceName | $latitude, $longitude',
            );
          });
        };

    nearbyService.onMessageReceived = (message, endpointId, senderName, type) {
      if (!mounted) return;

      final shouldStartSosAlarm = type == 'sos';

      setState(() {
        if (type == 'sos') {
          incomingSosActive = true;
          showSosModal = true;
          incomingSosSender = senderName;
          incomingSosMessage = message;
          incomingSosId = DateTime.now().millisecondsSinceEpoch.toString();
          final latMatch = RegExp(r'Lokacija: ([\d\.-]+), ([\d\.-]+)').firstMatch(message);

if (latMatch != null) {
  final lat = double.tryParse(latMatch.group(1) ?? '');
  final lng = double.tryParse(latMatch.group(2) ?? '');

  if (lat != null && lng != null) {
    meshSosLocations[senderName] = {
      'lat': lat,
      'lng': lng,
      'time': DateTime.now().millisecondsSinceEpoch,
      'message': message,
      'sender': senderName,
      'status': 'active',
    };
  }
}
          _setPinnedSosCard(
            status: 'active',
            title: '🆘 AKTIVAN SOS',
            message: message,
            sender: senderName,
          );
          _addSosPublicLog(
            '🆘 $senderName aktivirao SOS u ${_formatTime(DateTime.now())}',
          );
        } else if (type == 'sos_accept') {
          if (sosAcceptedCount < sosSentCount) {
            sosAcceptedCount++;
          }

          if (sosPendingCount > 0) {
            sosPendingCount--;
          }
          _setPinnedSosCard(
            status: 'accepted',
            title: '🚑 POMOĆ NA PUTU',
            message: '$senderName prihvatio SOS.',
            sender: senderName,
          );
          _addSosPublicLog(
            '✅ $senderName prihvatio SOS u ${_formatTime(DateTime.now())}',
          );
        } else if (type == 'sos_cancel') {
          _stopIncomingSosAlarm();

          incomingSosActive = false;
          sosActive = false;
          sosAlarmActive = false;
          activeSosId = null;
          _setPinnedSosCard(
            status: 'finished',
            title: '✅ SOS ZAVRŠEN',
            message: message,
            sender: senderName,
          );
          _addSosPublicLog(
            '✅ SOS ZAVRŠEN\n$message u ${_formatTime(DateTime.now())}',
          );
        } else if (type == 'sos_reject') {
          if (sosRejectedCount < sosSentCount) {
            sosRejectedCount++;
          }

          if (sosPendingCount > 0) {
            sosPendingCount--;
          }

          _addSosPublicLog('❌ $message u ${_formatTime(DateTime.now())}');
        } else if (type == 'private') {
          _privateMessages.add(
            ChatMessage(
              text: message,
              isMe: false,
              time: DateTime.now(),
              senderName: senderName,
            ),
          );

          selectedPrivateEndpointId = endpointId;
          selectedPrivateDeviceName = senderName;
          selectedPrivateDeviceId = nearbyService.endpointDeviceIds[endpointId];
        } else {
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

      if (shouldStartSosAlarm) {
        _startIncomingSosAlarm();
      }

      _scrollToBottom();
    };

    nearbyService.onDevicesChanged = () {
      if (!mounted) return;

      if (nearbyService.connectedDevices.isNotEmpty) {
        _startLocationBroadcast();
      }

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

      if (!mounted) return;

      setState(() {
        _batteryLevel = level;
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

  Future<void> _startIncomingSosAlarm() async {
    sosAlarmRepeatTimer?.cancel();
    sosAlarmStopTimer?.cancel();

    setState(() {
      sosAlarmActive = true;
    });
    _sosPulseController.repeat(reverse: true);
    await _sosAudioPlayer.setReleaseMode(ReleaseMode.loop);
    await _sosAudioPlayer.play(AssetSource('sounds/sos_siren.mp3'));
    _addSosPublicLog('🚨 SOS alarm aktiviran - čeka se reakcija korisnika');

    sosAlarmStopTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;

      setState(() {
        sosAlarmActive = false;
      });
    });

    sosAlarmRepeatTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      if (!mounted || !incomingSosActive) {
        timer.cancel();
        return;
      }

      setState(() {
        sosAlarmActive = true;
      });

      _addSosPublicLog('🚨 SOS alarm ponovljen - korisnik još nije reagovao');

      sosAlarmStopTimer?.cancel();
      sosAlarmStopTimer = Timer(const Duration(seconds: 30), () {
        if (!mounted) return;

        setState(() {
          sosAlarmActive = false;
        });
      });
    });
  }

  void _stopIncomingSosAlarm() {
    sosAlarmRepeatTimer?.cancel();
    sosAlarmStopTimer?.cancel();

    sosAlarmRepeatTimer = null;
    sosAlarmStopTimer = null;

    if (!mounted) return;

    setState(() {
      sosAlarmActive = false;
    });
    _sosPulseController.stop();
    _sosPulseController.reset();
    _sosAudioPlayer.stop();
  }

  Future<void> _loadSelectedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRole = prefs.getString('mesh_device_role');

    if (savedRole != null && availableRoles.contains(savedRole)) {
      selectedRole = savedRole;
    }

    try {
      (nearbyService as dynamic).deviceRole = selectedRole;
    } catch (_) {}
  }

  Future<void> _saveSelectedRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mesh_device_role', role);

    try {
      final dynamic service = nearbyService;
      await service.setDeviceRole(role);
    } catch (_) {
      try {
        (nearbyService as dynamic).deviceRole = role;
      } catch (_) {}
    }
  }

  Future<void> _saveDeviceName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    await nearbyService.setDeviceName(name);
    await _saveSelectedRole(selectedRole);

    if (!mounted) return;

    setState(() {
      showNameEditor = false;
      _addSystemMessage(
        'Ime uređaja: ${nearbyService.deviceName} | Uloga: $selectedRole',
      );
      _addSystemMessage('Uloga: ${nearbyService.deviceRole}');
      _addSystemMessage('ID: ${nearbyService.deviceId.substring(0, 8)}');
    });
  }

  Future<void> _activateSos() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _addSystemMessage('GPS dozvola nije odobrena. SOS nije poslat.');
        setState(() {});
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final connectedCount = nearbyService.connectedDevices.length;

      setState(() {
        sosActive = true;
        sosSentCount = connectedCount;
        sosAcceptedCount = 0;
        sosRejectedCount = 0;
        sosPendingCount = connectedCount;
        activeSosId = DateTime.now().millisecondsSinceEpoch.toString();
        _setPinnedSosCard(
          status: 'active',
          title: '🆘 AKTIVAN SOS',
          message:
              'SOS POSLAT\n'
              'Lokacija: ${position.latitude}, ${position.longitude}',
          sender: nearbyService.deviceName,
        );
        _messages.insert(
          0,
          ChatMessage(
            text:
                '🆘 SOS POSLAT\n'
                'Lokacija: ${position.latitude}, ${position.longitude}\n'
                'Vrijeme: ${DateTime.now().toLocal()}',
            isMe: true,
            time: DateTime.now(),
            senderName: 'JA',
          ),
        );
      });
      _sosPulseController.repeat(reverse: true);
      await nearbyService.sendSosMessage(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      _addSystemMessage('Greška pri slanju SOS: $e');
      setState(() {});
    }
  }

  Future<void> _cancelSos() async {
    if (activeSosId == null) return;

    await nearbyService.sendSosCancel(sosId: activeSosId!);

    _stopIncomingSosAlarm();

    if (!mounted) return;

    setState(() {
      sosActive = false;
      sosAlarmActive = false;
      activeSosId = null;

      sosSentCount = 0;
      sosAcceptedCount = 0;
      sosRejectedCount = 0;
      sosPendingCount = 0;
      _addSosPublicLog(
        '✅ SOS ZAVRŠEN\nPomoć pružena ugroženoj osobi. ${_formatTime(DateTime.now())}',
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final isPrivateMode = selectedPrivateDeviceName != null;

    setState(() {
      if (isPrivateMode) {
        _privateMessages.add(
          ChatMessage(
            text: text,
            isMe: true,
            time: DateTime.now(),
            senderName: 'Ja',
          ),
        );
      } else {
        _messages.add(
          ChatMessage(
            text: text,
            isMe: true,
            time: DateTime.now(),
            senderName: 'Ja',
          ),
        );
      }
    });

    _controller.clear();
    _scrollToBottom();

    if (isPrivateMode && selectedPrivateDeviceId != null) {
      await nearbyService.sendPrivateMessage(
        text: text,
        receiverDeviceId: selectedPrivateDeviceId!,
      );
    } else {
      await nearbyService.sendMessage(text);
    }
  }

  void _startLocationBroadcast() {
    locationBroadcastTimer?.cancel();

    _broadcastMyLocation();

    locationBroadcastTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _broadcastMyLocation(),
    );
  }

  Future<void> _broadcastMyLocation() async {
    if (nearbyService.connectedDevices.isEmpty) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await _loadBatteryLevel();

      await nearbyService.sendLocationUpdate(
        latitude: position.latitude,
        longitude: position.longitude,
        batteryLevel: _batteryLevel,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _logs.insert(0, 'Greška slanja lokacije: $e');
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;

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

  Future<void> _showRejectSosDialog() async {
    if (incomingSosId == null) return;

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'Nisam u mogućnosti da pomognem',
                      groupValue: selectedReason,
                      activeColor: Colors.redAccent,
                      title: const Text(
                        'Nisam u mogućnosti da pomognem',
                        style: TextStyle(color: Colors.white),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedReason = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      value: 'Mislim da je lažni SOS',
                      groupValue: selectedReason,
                      activeColor: Colors.redAccent,
                      title: const Text(
                        'Mislim da je lažni SOS',
                        style: TextStyle(color: Colors.white),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedReason = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      value: 'Drugi razlog',
                      groupValue: selectedReason,
                      activeColor: Colors.redAccent,
                      title: const Text(
                        'Drugi razlog',
                        style: TextStyle(color: Colors.white),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedReason = value!;
                        });
                      },
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

                    if (reason.isEmpty) return;

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

    if (result == null || result.isEmpty) return;

    await nearbyService.sendSosResponse(
      sosId: incomingSosId!,
      responseType: 'sos_reject',
      reason: result,
    );

    if (!mounted) return;
    _stopIncomingSosAlarm();
    setState(() {
      incomingSosActive = false;

      _messages.add(
        ChatMessage(
          text:
              '${nearbyService.deviceName} odbio SOS - $result '
              '${_formatTime(DateTime.now())}',
          isMe: true,
          time: DateTime.now(),
          senderName: 'SOS odgovor',
        ),
      );
    });
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
    if (!showSosModal) {
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

                Text(
                  incomingSosMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (incomingSosId == null) return;

                          await nearbyService.sendSosResponse(
                            sosId: incomingSosId!,
                            responseType: 'sos_accept',
                          );

                          _stopIncomingSosAlarm();

                          if (!mounted) return;

                          setState(() {
                            showSosModal = false;
                            incomingSosActive = false;
                          });
                        },
                        child: const Text('PRIHVATI'),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            showSosModal = false;
                          });

                          _showRejectSosDialog();
                        },
                        child: const Text('ODBIJ'),
                      ),
                    ),
                  ],
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
                        if (incomingSosId == null) return;

                        await nearbyService.sendSosResponse(
                          sosId: incomingSosId!,
                          responseType: 'sos_accept',
                        );
                        _stopIncomingSosAlarm();
                        setState(() {
                          incomingSosActive = false;

                          _messages.add(
                            ChatMessage(
                              text:
                                  '${nearbyService.deviceName} prihvatio SOS '
                                  '${_formatTime(DateTime.now())}',
                              isMe: true,
                              time: DateTime.now(),
                              senderName: 'SOS odgovor',
                            ),
                          );
                        });
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
            'SOS poslan na $sosSentCount korisnika',
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
            'Čeka odgovor $sosPendingCount/$sosSentCount',
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
              color: internetAvailable
                  ? Colors.blue.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              internetAvailable ? '🌐 ONLINE' : '📡 MESH',
              style: TextStyle(
                color: internetAvailable
                    ? Colors.lightBlueAccent
                    : Colors.orangeAccent,
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
    final seenNames = <String>{};

    final directDevices = nearbyService.connectedDevices.entries.toList();

    final foundDevices = nearbyService.foundDevices.entries.where((entry) {
      final isConnectedById = nearbyService.connectedDevices.containsKey(
        entry.key,
      );
      final isConnectedByName = nearbyService.connectedDevices.values.contains(
        entry.value,
      );
      final isDuplicateName = seenNames.contains(entry.value);

      if (!isConnectedById && !isConnectedByName && !isDuplicateName) {
        seenNames.add(entry.value);
        return true;
      }

      return false;
    }).toList();

    final indirectDevices = nearbyService.knownDevices.entries.where((entry) {
      final isMe = entry.key == nearbyService.deviceId;
      final isDirect = nearbyService.connectedDevices.values.contains(
        entry.value,
      );
      return !isMe && !isDirect;
    }).toList();

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
                          selectedPrivateEndpointId = null;
                          selectedPrivateDeviceId = entry.key;
                          selectedPrivateDeviceName = entry.value;
                          _privateMessages.clear();
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

  Widget _privateChatPanel() {
    if (selectedPrivateDeviceName == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: MediaQuery.of(context).viewInsets.bottom > 0 ? 120 : 220,
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
                      selectedPrivateEndpointId = null;
                      _privateMessages.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _privateMessages.length,
              itemBuilder: (context, index) {
                final msg = _privateMessages[index];

                return Align(
                  alignment: msg.isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.all(9),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isMe
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg.text,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      color: const Color(0xFF151A23),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: incomingSosActive
                    ? 'Prvo reaguj na SOS poruku...'
                    : selectedPrivateDeviceName == null
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
              onSubmitted: (_) {
                if (!incomingSosActive) {
                  _sendMessage();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF2563EB),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: incomingSosActive ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _scrollController.dispose();
    _sosPulseController.dispose();
    _sosAudioPlayer.dispose();
    locationBroadcastTimer?.cancel();
    nearbyService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              'BSL Mesh Chat',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            Text(
              '$deviceName • $selectedRole | Povezano: $connectedCount',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
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
            onPressed: () async {
              await nearbyService.startAdvertising();
              await Future.delayed(const Duration(seconds: 1));
              await nearbyService.startDiscovery();
            },
            icon: const Icon(Icons.hub, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Start advertising',
            onPressed: nearbyService.startAdvertising,
            icon: const Icon(Icons.wifi_tethering, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Start discovery',
            onPressed: nearbyService.startDiscovery,
            icon: const Icon(Icons.search, color: Colors.white),
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
    ),
  ),
);
            },
            icon: const Icon(Icons.map, color: Colors.white),
          ),

          IconButton(
            tooltip: 'Stop',
            onPressed: nearbyService.stopAll,
            icon: const Icon(Icons.stop_circle, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (showNameEditor)
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
                          if (value == null) return;

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
              _networkStatusBar(),
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

              _chatArea(),

              if (_logs.isNotEmpty)
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

              _privateChatPanel(),
              _inputBar(),
            ],
          ),
          _sosModal(),
        ],
      ),
    );
  }
}

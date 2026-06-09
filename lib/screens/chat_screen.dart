import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/chat_message.dart';
import '../services/nearby_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final NearbyService nearbyService;

  final List<ChatMessage> _messages = [];
  final List<String> _logs = [];
  final List<ChatMessage> _privateMessages = [];

  bool showNameEditor = false;

  String? selectedPrivateDeviceId;
  String? selectedPrivateDeviceName;
  String? selectedPrivateEndpointId;

  bool sosActive = false;
  bool incomingSosActive = false;

  String incomingSosSender = '';
  String incomingSosMessage = '';
  String? incomingSosId;

  int sosSentCount = 0;
  int sosAcceptedCount = 0;
  int sosPendingCount = 0;
  int sosRejectedCount = 0;

  String? activeSosId;

  Widget _deviceChip(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        name,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

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
    nearbyService = NearbyService();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final savedName = await nearbyService.loadDeviceName();
      await nearbyService.loadOrCreateDeviceId();

      if (!mounted) return;

      if (savedName == null) {
        _addSystemMessage('Klikni ✏️ gore desno i unesi ime uređaja.');
        _addSystemMessage('ID: ${nearbyService.deviceId.substring(0, 8)}');
        _addSystemMessage('Mesh chat spreman.');
        showNameEditor = true;
      } else {
        _addSystemMessage('Uređaj: ${nearbyService.deviceName}');
        _addSystemMessage('ID: ${nearbyService.deviceId.substring(0, 8)}');
        _addSystemMessage('Mesh chat spreman.');

        await nearbyService.startAdvertising();
        await Future.delayed(const Duration(seconds: 1));
        await nearbyService.startDiscovery();
      }

      setState(() {});
    });

    nearbyService.onLog = (log) {
      if (!mounted) return;
      setState(() {
        _logs.insert(0, log);
      });
    };

    nearbyService.onMessageReceived =
        (message, endpointId, senderName, type) {
      if (!mounted) return;

      setState(() {
        if (type == 'sos') {
          incomingSosActive = true;
          incomingSosSender = senderName;
          incomingSosMessage = message;
          incomingSosId = DateTime.now().millisecondsSinceEpoch.toString();
          } else if (type == 'sos_accept') {
  if (sosAcceptedCount < sosSentCount) {
    sosAcceptedCount++;
  }

  if (sosPendingCount > 0) {
    sosPendingCount--;
  }

  _messages.add(
    ChatMessage(
      text: '$senderName prihvatio SOS ${_formatTime(DateTime.now())}',
      isMe: false,
      time: DateTime.now(),
      senderName: 'SOS odgovor',
    ),
  );
} else if (type == 'sos_reject') {
    if (sosRejectedCount < sosSentCount) {
    sosRejectedCount++;
  }
  if (sosPendingCount > 0) {
    sosPendingCount--;
  }

  _messages.add(
    ChatMessage(
      text: message,
      isMe: false,
      time: DateTime.now(),
      senderName: 'SOS odgovor',
    ),
  );
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
          selectedPrivateDeviceId =
              nearbyService.endpointDeviceIds[endpointId];
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

      _scrollToBottom();
    };

    nearbyService.onDevicesChanged = () {
      if (!mounted) return;
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

  Future<void> _saveDeviceName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    await nearbyService.setDeviceName(name);

    if (!mounted) return;

    setState(() {
      showNameEditor = false;
      _addSystemMessage('Ime uređaja: ${nearbyService.deviceName}');
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

      await nearbyService.sendSosMessage(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      _addSystemMessage('Greška pri slanju SOS: $e');
      setState(() {});
    }
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
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 1.0,
        end: sosActive ? 1.10 : 1.0,
      ),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      onEnd: () {
        if (sosActive && mounted) {
          setState(() {});
        }
      },
      child: GestureDetector(
        onTap: _activateSos,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF5A5A),
                Color(0xFFD90000),
                Color(0xFF7A0000),
              ],
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
              if (sosActive)
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
                colors: [
                  Color(0xFFFF7777),
                  Color(0xFFE00000),
                  Color(0xFF9B0000),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
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
      ),
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

  Widget _devicePanel() {
    if (nearbyService.connectedDevices.isEmpty &&
        nearbyService.foundDevices.isEmpty &&
        nearbyService.knownDevices.isEmpty) {
      return const SizedBox.shrink();
    }

    final seenNames = <String>{};
    final notConnectedDevices =
        nearbyService.foundDevices.entries.where((entry) {
      final isConnectedById =
          nearbyService.connectedDevices.containsKey(entry.key);
      final isConnectedByName =
          nearbyService.connectedDevices.values.contains(entry.value);
      final isDuplicateName = seenNames.contains(entry.value);

      if (!isConnectedById && !isConnectedByName && !isDuplicateName) {
        seenNames.add(entry.value);
        return true;
      }

      return false;
    }).toList();

    final indirectDevices = nearbyService.knownDevices.entries.where((entry) {
      final isMe = entry.key == nearbyService.deviceId;
      final isDirect =
          nearbyService.connectedDevices.values.contains(entry.value);
      return !isMe && !isDirect;
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF111827),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nearbyService.connectedDevices.isNotEmpty) ...[
            const Text(
              'Direktno povezani:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: nearbyService.connectedDevices.entries.map((entry) {
                return GestureDetector(
                  onTap: () {
                    _showConnectedDeviceOptions(entry.key, entry.value);
                  },
                  child: _deviceChip(entry.value, Colors.greenAccent),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],

          if (notConnectedDevices.isNotEmpty) ...[
            const Text(
              'Pronađeni, nisu povezani:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: notConnectedDevices.map((entry) {
                return GestureDetector(
                  onTap: () async {
                    await nearbyService.connectToDevice(entry.key);
                  },
                  child: _deviceChip(entry.value, Colors.amberAccent),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],

          if (indirectDevices.isNotEmpty) ...[
            const Text(
              'Poznati preko mesh mreže:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: indirectDevices.map((entry) {
                return _deviceChip(entry.value, Colors.blueAccent);
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chatArea() {
    return Expanded(
      child: Column(
        children: [
          if (incomingSosActive) _incomingSosPanel(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];

                return Align(
                  alignment:
                      msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
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
                  alignment:
                      msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
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
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _scrollController.dispose();
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
              '$deviceName | Povezano: $connectedCount',
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
            tooltip: 'Stop',
            onPressed: nearbyService.stopAll,
            icon: const Icon(Icons.stop_circle, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          if (showNameEditor)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF151A23),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
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
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveDeviceName,
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                _sosButton(),
                const SizedBox(width: 10),
                if (sosActive) Expanded(child: _sosStatusPanel()),
              ],
            ),
          ),

          if (connectedCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.withValues(alpha: 0.15),
              child: const Text(
                'Nema povezanih uređaja. Klikni Auto Connect na oba telefona.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.green.withValues(alpha: 0.15),
              child: Text(
                'Povezano uređaja: $connectedCount',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ),

          _devicePanel(),
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
    );
  }
}

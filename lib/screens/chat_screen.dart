import 'package:flutter/material.dart';

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

  bool showNameEditor = false;

  Widget _deviceChip(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
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
      }

      setState(() {});
    });

    nearbyService.onLog = (log) {
      if (!mounted) return;
      setState(() {
        _logs.insert(0, log);
      });
    };

    nearbyService.onMessageReceived = (message, endpointId, senderName) {
      if (!mounted) return;

      setState(() {
        _messages.add(
          ChatMessage(
            text: message,
            isMe: false,
            time: DateTime.now(),
            senderName: senderName,
          ),
        );
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isMe: true,
          time: DateTime.now(),
          senderName: 'Ja',
        ),
      );
    });

    _controller.clear();
    _scrollToBottom();

    await nearbyService.sendMessage(text);
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
    final deviceName =
        nearbyService.deviceName.isEmpty ? 'Nije podešeno' : nearbyService.deviceName;

    return Scaffold(
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
                color: Colors.white.withOpacity(0.65),
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
                          color: Colors.white.withOpacity(0.5),
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
          if (connectedCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.withOpacity(0.15),
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
              color: Colors.green.withOpacity(0.15),
              child: Text(
                'Povezano uređaja: $connectedCount',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ),
          if (nearbyService.connectedDevices.isNotEmpty ||
              nearbyService.knownDevices.isNotEmpty)
            Container(
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
                      children:
                          nearbyService.connectedDevices.entries.map((entry) {
                        return _deviceChip(entry.value, Colors.greenAccent);
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Builder(
                    builder: (context) {
                      final indirectDevices =
                          nearbyService.knownDevices.entries.where((entry) {
                        final isMe = entry.key == nearbyService.deviceId;
                        final isDirect = nearbyService.connectedDevices.values
                            .contains(entry.value);

                        return !isMe && !isDirect;
                      }).toList();

                      if (indirectDevices.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                              return _deviceChip(
                                entry.value,
                                Colors.amberAccent,
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
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
                                color: Colors.white.withOpacity(0.65),
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
                            color: Colors.white.withOpacity(0.65),
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
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            color: const Color(0xFF151A23),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Unesi mesh poruku...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
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
        ],
      ),
    );
  }
}
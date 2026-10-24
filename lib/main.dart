import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';

void main() => runApp(const MeshMessengerApp());

class MeshMessengerApp extends StatelessWidget {
  const MeshMessengerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NRN Mesh',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1687FF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF070D14),
      useMaterial3: true,
    ),
    home: const ChatScreen(),
  );
}

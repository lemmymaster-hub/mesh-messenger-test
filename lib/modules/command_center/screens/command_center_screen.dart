import 'package:flutter/material.dart';
import '../widgets/command_center_map_panel.dart';

class CommandCenterScreen extends StatelessWidget {
  final Map<String, Map<String, dynamic>> meshUserLocations;
  final Map<String, Map<String, dynamic>> meshSosLocations;

  const CommandCenterScreen({
    super.key,
    required this.meshUserLocations,
    required this.meshSosLocations,
  });

  Widget _statusCard(
    String title,
    String value,
    Color color,
    String iconAsset,
  ) {
    return Expanded(
      child: Container(
        height: 62,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Image.asset(
                  iconAsset,
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topStatusBar() {
    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Row(
        children: [
          _statusCard(
            'Korisnici',
            meshUserLocations.length.toString(),
            Colors.greenAccent,
            'assets/icons/korisnici.png',
          ),
          _statusCard(
            'SOS',
            meshSosLocations.length.toString(),
            Colors.redAccent,
            'assets/icons/sos.png',
          ),
          _statusCard(
            'Timovi',
            '6',
            Colors.blueAccent,
            'assets/icons/timovi.png',
          ),
          _statusCard(
            'Repetitori',
            '2',
            Colors.orangeAccent,
            'assets/icons/repetitori.png',
          ),
        ],
      ),
    );
  }

  Widget _panel(String title, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Center(
        child: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _sosCenterPanel() {
    final sosCount = meshSosLocations.length;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.emergency, color: Colors.redAccent, size: 18),
              SizedBox(width: 6),
              Text(
                'SOS CENTAR',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Aktivni SOS: $sosCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: sosCount == 0
                ? const Center(
                    child: Text(
                      'Nema aktivnih SOS događaja',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    children: meshSosLocations.entries.map((entry) {
                      final sos = entry.value;
                      final sender =
                          sos['senderName']?.toString() ?? 'Nepoznat korisnik';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                sender,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mapPanel() {
    return CommandCenterMapPanel(
      meshUserLocations: meshUserLocations,
      meshSosLocations: meshSosLocations,
    );
  }

  Widget _wideLayout() {
    return Column(
      children: [
        _topStatusBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 170,
                  child: _panel(
                    'LIJEVI MENI',
                    Colors.lightBlueAccent,
                    Icons.dashboard,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      Expanded(flex: 7, child: _mapPanel()),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Expanded(
                              child: _panel(
                                'TIMOVI',
                                Colors.greenAccent,
                                Icons.groups,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _panel(
                                'DISPATCH CENTAR',
                                Colors.blueAccent,
                                Icons.local_hospital,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _panel(
                                'KOMUNIKACIJE',
                                Colors.cyanAccent,
                                Icons.chat,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Expanded(child: _sosCenterPanel()),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _panel(
                          'FOTO ZID',
                          Colors.orangeAccent,
                          Icons.photo_library,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _panel('MREŽA', Colors.greenAccent, Icons.hub),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileLayout() {
    return Column(
      children: [
        _topStatusBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                Expanded(flex: 6, child: _mapPanel()),
                const SizedBox(height: 10),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: _panel(
                          'TIMOVI',
                          Colors.greenAccent,
                          Icons.groups,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _panel(
                          'DISPATCH CENTAR',
                          Colors.blueAccent,
                          Icons.local_hospital,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFF06111F),
      body: SafeArea(child: isWide ? _wideLayout() : _mobileLayout()),
    );
  }
}

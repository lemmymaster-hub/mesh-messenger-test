import 'package:flutter/material.dart';

class DispatchPanel extends StatelessWidget {
  final bool isCreatingTeam;
  final String pendingTeamName;
  final int selectedMembersCount;
  final VoidCallback onStartTeamCreation;
  final VoidCallback onCancelTeamCreation;

  const DispatchPanel({
    super.key,
    this.isCreatingTeam = false,
    this.pendingTeamName = '',
    this.selectedMembersCount = 0,
    required this.onStartTeamCreation,
    required this.onCancelTeamCreation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_hospital, color: Colors.blueAccent, size: 18),
              SizedBox(width: 6),
              Text(
                'DISPATCH CENTAR',
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (!isCreatingTeam)
            SizedBox(
              width: double.infinity,
              height: 34,
              child: ElevatedButton.icon(
                onPressed: onStartTeamCreation,
                icon: const Icon(Icons.group_add, size: 16),
                label: const Text(
                  'Formiraj tim',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            )
          else ...[
            Text(
              pendingTeamName.isEmpty ? 'Novi tim' : pendingTeamName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Odabrani članovi: $selectedMembersCount',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton.icon(
                onPressed: onCancelTeamCreation,
                icon: const Icon(Icons.close, size: 15),
                label: const Text(
                  'Otkaži formiranje',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Expanded(
            child: Center(
              child: Text(
                'Nema aktivnih zadataka',
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
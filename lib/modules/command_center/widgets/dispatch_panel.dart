import 'package:flutter/material.dart';

class DispatchPanel extends StatelessWidget {
  final bool isCreatingTeam;
  final String pendingTeamName;
  final List<String> selectedMembers;
  final String pendingTeamTask;
  final ValueChanged<String> onTeamTaskChanged;
  final Color pendingTeamColor;
  final ValueChanged<Color> onTeamColorChanged;
  final VoidCallback onStartTeamCreation;
  final VoidCallback onCancelTeamCreation;
  final VoidCallback onConfirmTeamCreation;

  const DispatchPanel({
    super.key,
    this.isCreatingTeam = false,
    this.pendingTeamName = '',
    this.selectedMembers = const [],
    this.pendingTeamTask = '',
    this.pendingTeamColor = Colors.blueAccent,
    required this.onTeamTaskChanged,
    required this.onTeamColorChanged,
    required this.onStartTeamCreation,
    required this.onCancelTeamCreation,
    required this.onConfirmTeamCreation,
  });

  Widget _colorDot(Color color) {
    final isSelected = pendingTeamColor == color;

    return GestureDetector(
      onTap: () => onTeamColorChanged(color),
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isSelected ? 0.70 : 0.25),
              blurRadius: isSelected ? 10 : 4,
              spreadRadius: isSelected ? 2 : 0,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedMembersCount = selectedMembers.length;

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

            Expanded(
              child: selectedMembers.isEmpty
                  ? const Center(
                      child: Text(
                        'Klikni korisnike na mapi\nda ih dodaš u tim',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: selectedMembers.length,
                      itemBuilder: (context, index) {
                        final memberName = selectedMembers[index];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.greenAccent,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  memberName,
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
                      },
                    ),
            ),

            const SizedBox(height: 8),

            TextField(
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Zadatak tima...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.20),
                contentPadding: const EdgeInsets.all(8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.blueAccent.withValues(alpha: 0.25),
                  ),
                ),
              ),
              onChanged: onTeamTaskChanged,
            ),

            const SizedBox(height: 8),

            const Text(
              'Boja tima',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                _colorDot(Colors.blueAccent),
                _colorDot(Colors.greenAccent),
                _colorDot(Colors.orangeAccent),
                _colorDot(Colors.purpleAccent),
                _colorDot(Colors.redAccent),
              ],
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

          if (!isCreatingTeam) ...[
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
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';

class TeamsPanel extends StatelessWidget {
  final Map<String, Map<String, dynamic>> meshUserLocations;

  const TeamsPanel({
    super.key,
    required this.meshUserLocations,
  });

  String _normalizeRole(dynamic role) {
    final value = role?.toString().trim().toLowerCase() ?? '';

    if (value.contains('vatrogas')) return 'Vatrogasci';
    if (value.contains('polic')) return 'Policija';
    if (value.contains('gss')) return 'GSS';
    if (value.contains('crveni') || value.contains('ck')) return 'Crveni krst';
    if (value.contains('volonter')) return 'Volonteri';
    if (value.contains('komand')) return 'Komandanti';
    if (value.contains('operater')) return 'Operateri';

    return 'Ostali';
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'Vatrogasci':
        return Icons.local_fire_department;
      case 'Policija':
        return Icons.local_police;
      case 'GSS':
        return Icons.terrain;
      case 'Crveni krst':
        return Icons.medical_services;
      case 'Volonteri':
        return Icons.volunteer_activism;
      case 'Komandanti':
        return Icons.star;
      case 'Operateri':
        return Icons.support_agent;
      default:
        return Icons.groups;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'Vatrogasci':
        return Colors.redAccent;
      case 'Policija':
        return Colors.blueAccent;
      case 'GSS':
        return Colors.orangeAccent;
      case 'Crveni krst':
        return Colors.white;
      case 'Volonteri':
        return Colors.greenAccent;
      case 'Komandanti':
        return Colors.amberAccent;
      case 'Operateri':
        return Colors.cyanAccent;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, int>{};

    for (final user in meshUserLocations.values) {
      final role = _normalizeRole(user['role']);
      grouped[role] = (grouped[role] ?? 0) + 1;
    }

    final orderedRoles = [
      'Vatrogasci',
      'Policija',
      'GSS',
      'Crveni krst',
      'Volonteri',
      'Komandanti',
      'Operateri',
      'Ostali',
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups, color: Colors.greenAccent, size: 18),
              SizedBox(width: 6),
              Text(
                'TIMOVI',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: grouped.isEmpty
                ? const Center(
                    child: Text(
                      'Nema aktivnih timova',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    children: orderedRoles
                        .where((role) => grouped.containsKey(role))
                        .map((role) {
                      final count = grouped[role] ?? 0;
                      final color = _roleColor(role);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: color.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(_roleIcon(role), color: color, size: 16),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                role,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              count.toString(),
                              style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
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
}
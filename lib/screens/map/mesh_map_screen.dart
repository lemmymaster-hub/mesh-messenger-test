import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MeshMapScreen extends StatefulWidget {
  const MeshMapScreen({super.key});

  @override
  State<MeshMapScreen> createState() => _MeshMapScreenState();
}

class _MeshMapScreenState extends State<MeshMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng _mapCenter = const LatLng(43.8167, 18.35);
  double _currentZoom = 12;
  bool _isDownloadingMap = false;
  String? _offlineAreaName;
  List<Map<String, dynamic>> _offlineAreas = [];

  @override
  void initState() {
    super.initState();
    _loadOfflineAreas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOfflineAreas() async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList('offline_map_areas_v2') ?? [];

    if (!mounted) return;

    setState(() {
      _offlineAreas = savedList
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();
    });
  }

  Future<void> _saveOfflineAreas() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      'offline_map_areas_v2',
      _offlineAreas.map((item) => jsonEncode(item)).toList(),
    );
  }

  Future<void> _deleteOfflineArea(Map<String, dynamic> area) async {
    final areaName = area['name']?.toString() ?? 'Offline mapa';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151A23),
          title: const Text(
            'Obrisati offline mapu?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            areaName,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Otkaži'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Obriši'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _offlineAreas.removeWhere((item) => item['name'] == areaName);

      if (_offlineAreaName == areaName) {
        _offlineAreaName = null;
      }
    });

    await _saveOfflineAreas();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Offline mapa obrisana: $areaName'),
      ),
    );
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return;
    }

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'json',
          'limit': '1',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'BSL Mesh Lite / mesh_messenger_test',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Greška servera: ${response.statusCode}');
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;

      if (data.isEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mjesto nije pronađeno: $query'),
          ),
        );
        return;
      }

      final firstResult = data.first as Map<String, dynamic>;
      final lat = double.parse(firstResult['lat'] as String);
      final lon = double.parse(firstResult['lon'] as String);
      final newCenter = LatLng(lat, lon);

      setState(() {
        _mapCenter = newCenter;
        _currentZoom = 13;
      });

      _mapController.move(newCenter, 13);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mapa premještena na: $query'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Greška pretrage: $e'),
        ),
      );
    }
  }

  Future<void> _downloadCurrentArea() async {
    if (_isDownloadingMap) return;

    final defaultName = _searchController.text.trim().isEmpty
        ? 'Područje ${_mapCenter.latitude.toStringAsFixed(4)}, ${_mapCenter.longitude.toStringAsFixed(4)}'
        : _searchController.text.trim();

    final nameController = TextEditingController(text: defaultName);

    final areaName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151A23),
          title: const Text(
            'Naziv offline mape',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: nameController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'npr. Jahorina - Ogorjelica',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Otkaži'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.of(dialogContext).pop(name);
              },
              child: const Text('Sačuvaj'),
            ),
          ],
        );
      },
    );

    if (areaName == null || areaName.isEmpty) {
      return;
    }

    setState(() {
      _isDownloadingMap = true;
      _offlineAreaName = areaName;
    });

    await Future.delayed(const Duration(seconds: 2));

    final offlineMap = {
      'name': areaName,
      'lat': _mapCenter.latitude,
      'lng': _mapCenter.longitude,
      'zoom': _currentZoom,
      'createdAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      _offlineAreas.removeWhere((item) => item['name'] == areaName);
      _offlineAreas.add(offlineMap);
      _isDownloadingMap = false;
    });

    await _saveOfflineAreas();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mapa sačuvana za offline: $areaName'),
      ),
    );
  }

  void _openOfflineArea(Map<String, dynamic> area) {
    final lat = (area['lat'] as num?)?.toDouble();
    final lng = (area['lng'] as num?)?.toDouble();
    final zoom = (area['zoom'] as num?)?.toDouble() ?? 13;
    final areaName = area['name']?.toString() ?? 'Offline mapa';

    if (lat == null || lng == null) return;

    final newCenter = LatLng(lat, lng);

    setState(() {
      _mapCenter = newCenter;
      _currentZoom = zoom;
      _offlineAreaName = areaName;
    });

    _mapController.move(newCenter, zoom);
  }

  Widget _offlineAreaChips() {
    if (_offlineAreas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _offlineAreas.map((area) {
            final areaName = area['name']?.toString() ?? 'Offline mapa';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1117),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _openOfflineArea(area),
                    child: Text(
                      areaName,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _deleteOfflineArea(area),
                    child: const Icon(
                      Icons.delete,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151A23),
        title: const Text(
          'BSL Mesh Map',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF151A23),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Pretraži mjesto...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.white70,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.arrow_forward,
                        color: Colors.white70,
                      ),
                      onPressed: _searchPlace,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0E1117),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _searchPlace(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Centar: ${_mapCenter.latitude.toStringAsFixed(5)}, '
                  '${_mapCenter.longitude.toStringAsFixed(5)} | Zoom: ${_currentZoom.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                if (_offlineAreaName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '💾 Offline mapa: $_offlineAreaName',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                _offlineAreaChips(),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _currentZoom,
                onPositionChanged: (position, hasGesture) {
                  setState(() {
                    _mapCenter = position.center;
                    _currentZoom = position.zoom;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.mesh_messenger_test',
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _downloadCurrentArea,
        icon: _isDownloadingMap
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.download),
        label: Text(_isDownloadingMap ? 'Preuzimanje...' : 'Skini mapu'),
      ),
    );
  }
}

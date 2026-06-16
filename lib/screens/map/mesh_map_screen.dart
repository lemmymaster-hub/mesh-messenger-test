import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class MeshMapScreen extends StatefulWidget {
  final Map<String, Map<String, dynamic>> meshUserLocations;
  final Map<String, Map<String, dynamic>> meshSosLocations;

  const MeshMapScreen({
    super.key,
    required this.meshUserLocations,
    required this.meshSosLocations,
  });

  @override
  State<MeshMapScreen> createState() => _MeshMapScreenState();
}

class _MeshMapScreenState extends State<MeshMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng _mapCenter = const LatLng(43.8167, 18.35);
  double _currentZoom = 12;
  LatLng? _myLocation;
  bool _isDownloadingMap = false;
  String? _offlineAreaName;
  List<Map<String, dynamic>> _offlineAreas = [];
  String _selectedRoleFilter = 'Svi';

  final List<String> _roleFilters = [
    'Svi',
    'Komandant',
    'Operater',
    'Vatrogasac',
    'Policija',
    'GSS',
    'CK',
    'Hitna',
    'Volonter',
  ];

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  bool _isValidLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  bool _isValidLatLngObject(LatLng? point) {
    if (point == null) return false;
    return _isValidLatLng(point.latitude, point.longitude);
  }

  double _safeZoom(double zoom) {
    if (!zoom.isFinite) return 12;
    if (zoom < 3) return 3;
    if (zoom > 19) return 19;
    return zoom;
  }

  void _safeMoveMap(LatLng point, double zoom) {
    if (!_isValidLatLngObject(point)) return;
    final safeZoom = _safeZoom(zoom);

    setState(() {
      _mapCenter = point;
      _currentZoom = safeZoom;
    });

    _mapController.move(point, safeZoom);
  }

  String _centerText() {
    if (!_isValidLatLngObject(_mapCenter)) {
      return 'Centar: Nepoznat | Zoom: ${_currentZoom.toStringAsFixed(1)}';
    }

    return 'Centar: ${_mapCenter.latitude.toStringAsFixed(5)}, '
        '${_mapCenter.longitude.toStringAsFixed(5)} | '
        'Zoom: ${_currentZoom.toStringAsFixed(1)}';
  }

  String _roleMarker(String role) {
    switch (role) {
      case 'Komandant':
        return 'assets/markers/komadant.png';

      case 'Komandni centar':
        return 'assets/markers/komandni_centar.png';

      case 'Vatrogasac':
        return 'assets/markers/vatrogasci.png';

      case 'Policija':
        return 'assets/markers/policija.png';

      case 'GSS':
        return 'assets/markers/gss.png';

      case 'CK':
        return 'assets/markers/crveni_krst.png';

      case 'Hitna':
        return 'assets/markers/hitna.png';

      case 'Volonter':
      default:
        return 'assets/markers/volonteri.png';
    }
  }

  void _showMeshUserInfo({
    required String name,
    required String role,
    required double lat,
    required double lng,
    required int timestamp,
    required int battery,
  }) {
    final lastSeen = timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;

    final String lastSeenText;

    if (lastSeen == null) {
      lastSeenText = 'Nepoznato';
    } else {
      final now = DateTime.now();
      final diff = now.difference(lastSeen);

      if (diff.inSeconds < 60) {
        lastSeenText = 'prije ${diff.inSeconds} sekundi';
      } else if (diff.inMinutes < 60) {
        lastSeenText = 'prije ${diff.inMinutes} minuta';
      } else {
        lastSeenText = 'prije ${diff.inHours} sati';
      }
    }

    final Color batteryColor = battery <= 0
        ? Colors.white54
        : battery < 20
        ? Colors.redAccent
        : battery < 50
        ? Colors.orangeAccent
        : Colors.greenAccent;

    final String batteryText = battery > 0
        ? '🔋 Baterija: $battery%'
        : '🔋 Baterija: Nepoznato';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151A23),
          title: Text(name, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Uloga: $role',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                'Koordinate: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                batteryText,
                style: TextStyle(
                  color: batteryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Zadnji put viđen: $lastSeenText',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Zatvori'),
            ),
          ],
        );
      },
    );
  }

  void _showSosInfo(MapEntry<String, Map<String, dynamic>> entry) {
    final sender = entry.value['sender']?.toString() ?? entry.key;
    final message = entry.value['message']?.toString() ?? '';
    final status = entry.value['status']?.toString() ?? 'active';
    final timeRaw = _toDouble(entry.value['time'])?.toInt() ?? 0;
    final lat = _toDouble(entry.value['lat']);
    final lng = _toDouble(entry.value['lng']);

    String timeText = 'Nepoznato';

    if (timeRaw > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(timeRaw);
      timeText =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF151A23),
        title: const Text(
          '🆘 AKTIVAN SOS',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pošiljalac: $sender',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Status: $status',
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 6),
            if (_isValidLatLng(lat, lng))
              Text(
                'Lokacija: ${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 6),
            Text(
              'Vrijeme: $timeText',
              style: const TextStyle(color: Colors.white70),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(message, style: const TextStyle(color: Colors.white70)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMyLocation() async {
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!_isValidLatLng(position.latitude, position.longitude)) return;

      final myPosition = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() {
        _myLocation = myPosition;
      });

      _safeMoveMap(myPosition, 15);
    } catch (_) {
      // Ako GPS nije dostupan, ostaje fallback Sarajevo/Istočno Sarajevo.
    }
  }

  @override
  void initState() {
    super.initState();

    _loadOfflineAreas();
    _loadMyLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOfflineAreas() async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList('offline_map_areas_v2') ?? [];

    final loadedAreas = <Map<String, dynamic>>[];

    for (final item in savedList) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        final lat = _toDouble(decoded['lat']);
        final lng = _toDouble(decoded['lng']);

        if (_isValidLatLng(lat, lng)) {
          loadedAreas.add(decoded);
        }
      } catch (_) {
        // Preskoči neispravan zapis.
      }
    }

    if (!mounted) return;

    setState(() {
      _offlineAreas = loadedAreas;
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Offline mapa obrisana: $areaName')));
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return;
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
      });

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'BSL Mesh Lite / mesh_messenger_test'},
      );

      if (response.statusCode != 200) {
        throw Exception('Greška servera: ${response.statusCode}');
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;

      if (data.isEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mjesto nije pronađeno: $query')),
        );
        return;
      }

      final firstResult = data.first as Map<String, dynamic>;
      final lat = _toDouble(firstResult['lat']);
      final lon = _toDouble(firstResult['lon']);

      if (!_isValidLatLng(lat, lon)) {
        throw Exception('Pretraga je vratila neispravne koordinate');
      }

      final newCenter = LatLng(lat!, lon!);
      _safeMoveMap(newCenter, 13);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Mapa premještena na: $query')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pretrage: $e')));
    }
  }

  Future<void> _downloadCurrentArea() async {
    if (_isDownloadingMap) return;

    if (!_isValidLatLngObject(_mapCenter)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Centar mape nije validan. Pomjeri mapu i pokušaj opet.',
          ),
        ),
      );
      return;
    }

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
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
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

    nameController.dispose();

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
      'zoom': _safeZoom(_currentZoom),
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
      SnackBar(content: Text('Mapa sačuvana za offline: $areaName')),
    );
  }

  void _openOfflineArea(Map<String, dynamic> area) {
    final lat = _toDouble(area['lat']);
    final lng = _toDouble(area['lng']);
    final zoom = _safeZoom(_toDouble(area['zoom']) ?? 13);
    final areaName = area['name']?.toString() ?? 'Offline mapa';

    if (!_isValidLatLng(lat, lng)) return;

    final newCenter = LatLng(lat!, lng!);

    setState(() {
      _offlineAreaName = areaName;
    });

    _safeMoveMap(newCenter, zoom);
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

  List<Marker> _myLocationMarkers() {
    if (!_isValidLatLngObject(_myLocation)) return [];

    return [
      Marker(
        point: _myLocation!,
        width: 60,
        height: 60,
        child: const Icon(
          Icons.my_location,
          color: Colors.blueAccent,
          size: 36,
        ),
      ),
    ];
  }

  List<Marker> _meshUserMarkers() {
    return widget.meshUserLocations.entries
        .where((entry) {
          final role = (entry.value['role'] ?? 'Volonter').toString();

          if (_selectedRoleFilter == 'Svi') {
            return true;
          }

          return role == _selectedRoleFilter;
        })
        .map((entry) {
          final lat = _toDouble(entry.value['lat']);
          final lng = _toDouble(entry.value['lng']);

          if (!_isValidLatLng(lat, lng)) return null;

          final role = (entry.value['role'] ?? 'Volonter').toString();
          final timestamp = _toDouble(entry.value['time'])?.toInt() ?? 0;
          final battery = _toDouble(entry.value['battery'])?.toInt() ?? 0;

          return Marker(
            point: LatLng(lat!, lng!),
            width: 90,
            height: 70,
            child: GestureDetector(
              onTap: () {
                _showMeshUserInfo(
                  name: entry.key,
                  role: role,
                  lat: lat,
                  lng: lng,
                  timestamp: timestamp,
                  battery: battery,
                );
              },
              child: Column(
                children: [
                  Image.asset(_roleMarker(role), width: 42, height: 42),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.key,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  List<Marker> _sosMarkers() {
    return widget.meshSosLocations.entries
        .map((entry) {
          final lat = _toDouble(entry.value['lat']);
          final lng = _toDouble(entry.value['lng']);

          if (!_isValidLatLng(lat, lng)) return null;

          return Marker(
            point: LatLng(lat!, lng!),
            width: 76,
            height: 76,
            child: GestureDetector(
              onTap: () => _showSosInfo(entry),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.18),
                  border: Border.all(color: Colors.redAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.55),
                      blurRadius: 16,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.emergency, color: Colors.red, size: 42),
                ),
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final myLocationMarkers = _myLocationMarkers();
    final userMarkers = _meshUserMarkers();
    final sosMarkers = _sosMarkers();

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
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
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
                  _centerText(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _roleFilters.map((role) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(role),
                          selected: _selectedRoleFilter == role,
                          onSelected: (_) {
                            setState(() {
                              _selectedRoleFilter = role;
                            });
                          },
                        ),
                      );
                    }).toList(),
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
                initialCenter: _isValidLatLngObject(_mapCenter)
                    ? _mapCenter
                    : const LatLng(43.8167, 18.35),
                initialZoom: _safeZoom(_currentZoom),
                onPositionChanged: (position, hasGesture) {
                  final center = position.center;
                  final zoom = _safeZoom(position.zoom);

                  if (_isValidLatLngObject(center)) {
                    setState(() {
                      _mapCenter = center;
                      _currentZoom = zoom;
                    });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.mesh_messenger_test',
                ),
                if (myLocationMarkers.isNotEmpty)
                  MarkerLayer(markers: myLocationMarkers),
                if (userMarkers.isNotEmpty) MarkerLayer(markers: userMarkers),
                if (sosMarkers.isNotEmpty) MarkerLayer(markers: sosMarkers),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'my_location',
            backgroundColor: Colors.blueAccent,
            onPressed: () {
              if (!_isValidLatLngObject(_myLocation)) return;
              _safeMoveMap(_myLocation!, 15);
            },
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'download_map',
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
        ],
      ),
    );
  }
}

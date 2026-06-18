import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/offline_map_service.dart';

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
  final OfflineMapService _offlineMapService = OfflineMapService();
  String _searchQuery = '';

  LatLng _mapCenter = const LatLng(43.8167, 18.35);
  double _currentZoom = 12;
  LatLng? _myLocation;
  bool _isDownloadingMap = false;
  String? _offlineAreaName;
  String _offlineCacheSize = '0 MB';
  String? _offlineTileRootPath;
  int _offlineDownloadCurrent = 0;
  int _offlineDownloadTotal = 0;
  List<Map<String, dynamic>> _offlineAreas = [];
  String _selectedRoleFilter = 'Svi';
  Map<String, dynamic>? _selectedMapUser;
  String? _selectedMapUserName;

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
  static const Color _bslBg = Color(0xFF081120);
  static const Color _bslPanel = Color(0xFF101826);
  static const Color _bslPanel2 = Color(0xFF182335);
  static const Color _bslCyan = Color(0xFF1E88FF);
  static const Color _bslGreen = Color(0xFF2EE66B);
  static const Color _bslRed = Color(0xFFFF4D57);
  static const Color _bslTextMuted = Color(0xFF9AA4B2);
  int get _meshNodeCount => widget.meshUserLocations.length;

  int get _activeSosCount => widget.meshSosLocations.length;

  bool get _offlineReady => _offlineAreas.isNotEmpty;

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

  Widget _selectedUserMapPopup() {
    final user = _selectedMapUser;
    final name = _selectedMapUserName;

    if (user == null || name == null) {
      return const SizedBox.shrink();
    }

    final role = user['role']?.toString() ?? 'Korisnik';
  final lat = _toDouble(user['lat']);
  final lng = _toDouble(user['lng']);
  final battery = _toDouble(user['battery'])?.toInt() ?? 0;
  final timestamp = _toDouble(user['timestamp'])?.toInt() ?? 0;

  String lastSeenText = 'Nepoznato';

  if (timestamp > 0) {
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = DateTime.now().difference(lastSeen);

    if (diff.inSeconds < 60) {
      lastSeenText = 'prije ${diff.inSeconds} sec';
    } else if (diff.inMinutes < 60) {
      lastSeenText = 'prije ${diff.inMinutes} min';
    } else {
      lastSeenText = 'prije ${diff.inHours} h';
    }
  }

  final roleUpper = role.toUpperCase();

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _bslPanel.withValues(alpha: 0.60),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: _bslCyan.withValues(alpha: 0.35),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: _bslCyan.withValues(alpha: 0.18),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Row(
      children: [
        Image.asset(
          _roleMarker(role),
          width: 42,
          height: 42,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$roleUpper $name',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 1,
                color: _bslCyan.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 6),
              Text(
                battery > 0 ? '🔋 $battery%' : '🔋 Nepoznato',
                style: const TextStyle(
                  color: _bslGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _isValidLatLng(lat, lng)
                    ? '📍 ${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
                    : '📍 Lokacija nepoznata',
                style: const TextStyle(
                  color: _bslTextMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '🕒 $lastSeenText',
                style: const TextStyle(
                  color: _bslTextMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              _selectedMapUser = null;
              _selectedMapUserName = null;
            });
          },
          icon: const Icon(
            Icons.close,
            color: Colors.white70,
            size: 20,
          ),
        ),
      ],
    ),
  );
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        _mapController.move(point, safeZoom);
      } catch (_) {
        // MapController možda još nije spreman; ignoriši sigurno.
      }
    });
  }

  String _centerText() {
    if (!_isValidLatLngObject(_mapCenter)) {
      return 'Centar: Nepoznat | Zoom: ${_currentZoom.toStringAsFixed(1)}';
    }

    return 'Centar: ${_mapCenter.latitude.toStringAsFixed(5)}, '
        '${_mapCenter.longitude.toStringAsFixed(5)} | '
        'Zoom: ${_currentZoom.toStringAsFixed(1)}';
  }

  Widget _statusBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 10,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
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

    _loadOfflineTileRootPath();
    _loadOfflineCacheSize();
    _loadOfflineAreas();
    _loadMyLocation();
  }

  Future<void> _loadOfflineTileRootPath() async {
    final root = await _offlineMapService.offlineTileRoot();

    if (!mounted) return;

    setState(() {
      _offlineTileRootPath = root.path;
    });
  }

  Future<void> _loadOfflineCacheSize() async {
    final bytes = await _offlineMapService.offlineCacheSizeBytes();

    if (!mounted) return;

    final mb = bytes / (1024 * 1024);

    setState(() {
      _offlineCacheSize = '${mb.toStringAsFixed(1)} MB';
    });
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
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
    await _loadOfflineCacheSize();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Offline mapa obrisana: $areaName')));
  }

  Future<void> _searchPlace() async {
    final query = _searchQuery.trim();

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
    print('BSL DOWNLOAD MAP START');
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

    final currentSearchText = _searchQuery.trim();

    final defaultName = currentSearchText.isEmpty
        ? 'Područje ${_mapCenter.latitude.toStringAsFixed(4)}, ${_mapCenter.longitude.toStringAsFixed(4)}'
        : currentSearchText;

    String areaNameDraft = defaultName;

    final areaName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151A23),
          title: const Text(
            'Naziv offline mape',
            style: TextStyle(color: Colors.white),
          ),
          content: TextFormField(
            initialValue: defaultName,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'npr. Jahorina - Ogorjelica',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
            onChanged: (value) {
              areaNameDraft = value;
            },
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
                final name = areaNameDraft.trim();
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
      _offlineDownloadCurrent = 0;
      _offlineDownloadTotal = 0;
    });
    print('BSL CALLING DOWNLOAD AREA');

    final currentZoom = _safeZoom(_currentZoom).round();
    final nextZoom = (currentZoom + 1).clamp(1, 18);

    final result = await _offlineMapService.downloadArea(
      onProgress: (current, total) {
        if (!mounted) return;

        setState(() {
          _offlineDownloadCurrent = current;
          _offlineDownloadTotal = total;
        });
      },
      centerLat: _mapCenter.latitude,
      centerLng: _mapCenter.longitude,
      zoomLevels: [currentZoom, nextZoom],
      radius: 5,
    );

    print('BSL DOWNLOAD AREA FINISHED: ${result.downloaded}/${result.total}');

    final offlineMap = {
      'name': areaName,
      'lat': _mapCenter.latitude,
      'lng': _mapCenter.longitude,
      'zoom': _safeZoom(_currentZoom),
      'tileCache': true,
      'downloadedTiles': result.downloaded,
      'totalTiles': result.total,
      'createdAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      _offlineAreas.removeWhere((item) => item['name'] == areaName);
      _offlineAreas.add(offlineMap);
      _isDownloadingMap = false;
    });

    await _saveOfflineAreas();
    await _loadOfflineCacheSize();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Offline mapa sačuvana: $areaName (${result.downloaded}/${result.total} tileova)',
        ),
      ),
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

          final safeLat = lat!;
          final safeLng = lng!;
          final role = (entry.value['role'] ?? 'Volonter').toString();
          final timestamp = _toDouble(entry.value['time'])?.toInt() ?? 0;
          final battery = _toDouble(entry.value['battery'])?.toInt() ?? 0;

          return Marker(
            point: LatLng(safeLat, safeLng),
            width: 90,
            height: 70,
            child: GestureDetector(
              onTap: () {
                _safeMoveMap(LatLng(safeLat, safeLng), 17);

                setState(() {
                  _selectedMapUserName = entry.key;
                  _selectedMapUser = {
                    'role': role,
                    'lat': safeLat,
                    'lng': safeLng,
                    'timestamp': timestamp,
                    'battery': battery,
                  };
                });
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

          final safeLat = lat!;
          final safeLng = lng!;

          return Marker(
            point: LatLng(safeLat, safeLng),
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
      backgroundColor: _bslBg,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            color: _bslPanel,
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'BSL Mesh',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: TextField(
                            key: const ValueKey('mesh_map_search_field'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Pretraži...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 13,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.white70,
                                size: 19,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: _searchPlace,
                                padding: EdgeInsets.zero,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0E1117),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 0,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _bslCyan.withValues(alpha: 0.12),
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _bslCyan.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              _searchQuery = value;
                            },
                            onSubmitted: (value) {
                              _searchQuery = value.trim();
                              _searchPlace();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_bslPanel2, _bslPanel],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _bslCyan.withValues(alpha: 0.22),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _bslCyan.withValues(alpha: 0.10),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _bslGreen,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _bslGreen.withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'BSL FIELD OPERATIONS',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'MAP',
                            style: TextStyle(
                              color: _bslTextMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _statusBadge(
                              label: 'MESH ($_meshNodeCount)',
                              icon: Icons.hub,
                              color: _bslCyan,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statusBadge(
                              label: _offlineReady ? 'OFFLINE' : 'NO MAP',
                              icon: Icons.map,
                              color: _offlineReady
                                  ? _bslGreen
                                  : Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statusBadge(
                              label: _activeSosCount == 0
                                  ? 'SOS READY'
                                  : 'SOS ($_activeSosCount)',
                              icon: Icons.emergency,
                              color: _bslRed,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _centerText(),
                        style: const TextStyle(
                          color: _bslTextMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '💾 Cache: $_offlineCacheSize',
                              style: const TextStyle(
                                color: _bslGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _offlineAreaName == null
                                  ? '🗺️ Sektor: nije odabran'
                                  : '🗺️ $_offlineAreaName',
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: _bslCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _roleFilters.map((role) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
  label: Text(
    role,
    style: TextStyle(
      color: _selectedRoleFilter == role ? Colors.white : _bslTextMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  ),
  selected: _selectedRoleFilter == role,
  selectedColor: _bslCyan.withValues(alpha: 0.22),
  backgroundColor: _bslBg,
  side: BorderSide(
    color: _selectedRoleFilter == role
        ? _bslCyan.withValues(alpha: 0.65)
        : _bslTextMuted.withValues(alpha: 0.18),
  ),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
  ),
  visualDensity: VisualDensity.compact,
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  child: Stack(
    children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _isValidLatLngObject(_mapCenter)
              ? _mapCenter
              : const LatLng(43.8167, 18.35),
          initialZoom: _safeZoom(_currentZoom),
          onPositionChanged: (position, hasGesture) {
            if (!hasGesture) return;

            final center = position.center;
            final zoom = _safeZoom(position.zoom);

            if (!_isValidLatLngObject(center)) return;

            final latDiff = (_mapCenter.latitude - center.latitude).abs();
            final lngDiff = (_mapCenter.longitude - center.longitude).abs();
            final zoomDiff = (_currentZoom - zoom).abs();

            if (latDiff < 0.00001 &&
                lngDiff < 0.00001 &&
                zoomDiff < 0.05) {
              return;
            }

            setState(() {
              _mapCenter = center;
              _currentZoom = zoom;
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.mesh_messenger_test',
            tileProvider: _offlineTileRootPath == null
                ? NetworkTileProvider()
                : BslOfflineTileProvider(_offlineTileRootPath!),
          ),
          if (myLocationMarkers.isNotEmpty)
            MarkerLayer(markers: myLocationMarkers),
          if (userMarkers.isNotEmpty) MarkerLayer(markers: userMarkers),
          if (sosMarkers.isNotEmpty) MarkerLayer(markers: sosMarkers),
        ],
      ),

      Positioned(
        top: 14,
        right: 14,
        child: Column(
          children: [
            FloatingActionButton.small(
              heroTag: 'download_map',
              backgroundColor: _bslPanel.withValues(alpha: 0.88),
              onPressed: _downloadCurrentArea,
              child: _isDownloadingMap
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download, color: Colors.white),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'my_location',
              backgroundColor: _bslCyan.withValues(alpha: 0.90),
              onPressed: () {
                if (!_isValidLatLngObject(_myLocation)) return;
                _safeMoveMap(_myLocation!, 15);
              },
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ],
        ),
      ),

      if (_isDownloadingMap && _offlineDownloadTotal > 0)
        Positioned(
          top: 110,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _bslCyan.withValues(alpha: 0.4)),
            ),
            child: Text(
              '⬇️ $_offlineDownloadCurrent/$_offlineDownloadTotal',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

      if (_selectedMapUser != null && _selectedMapUserName != null)
        Positioned(
          left: 14,
          right: 14,
          bottom: 20,
          child: _selectedUserMapPopup(),
        ),
    ],
  ),
),
        ],
      ),
    );
  }
}

class BslOfflineTileProvider extends TileProvider {
  final String rootPath;

  BslOfflineTileProvider(this.rootPath);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final z = coordinates.z.round();
    final x = coordinates.x.round();
    final y = coordinates.y.round();

    final file = File('$rootPath/$z/$x/$y.png');

    if (file.existsSync()) {
      return FileImage(file);
    }

    return NetworkImage('https://tile.openstreetmap.org/$z/$x/$y.png');
  }
}

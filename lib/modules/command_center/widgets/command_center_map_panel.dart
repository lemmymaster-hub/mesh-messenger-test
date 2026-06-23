import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';


class CommandCenterMapPanel extends StatefulWidget {
  final Map<String, Map<String, dynamic>> meshUserLocations;
  final Map<String, Map<String, dynamic>> meshSosLocations;
final bool isCreatingTeam;
final Set<String> selectedTeamMembers;
final ValueChanged<String> onUserMarkerTap;
  const CommandCenterMapPanel({
    super.key,
    required this.meshUserLocations,
    required this.meshSosLocations,
    this.isCreatingTeam = false,
this.selectedTeamMembers = const {},
required this.onUserMarkerTap,
  });

  @override
  State<CommandCenterMapPanel> createState() => _CommandCenterMapPanelState();
}

class _CommandCenterMapPanelState extends State<CommandCenterMapPanel> {
  final MapController _mapController = MapController();

  String? _offlineTileRootPath;

  LatLng _mapCenter = const LatLng(43.8167, 18.35);
  double _currentZoom = 12;

  @override
  void initState() {
    super.initState();
    _loadOfflineTileRootPath();
  }

  Future<void> _loadOfflineTileRootPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}/offline_tiles');

    if (!mounted) return;

    setState(() {
      _offlineTileRootPath = root.path;
    });
  }

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

  double _safeZoom(double zoom) {
    if (!zoom.isFinite) return 12;
    if (zoom < 3) return 3;
    if (zoom > 19) return 19;
    return zoom;
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

  void _showUserInfo({
    required String name,
    required String role,
    required double lat,
    required double lng,
    required int battery,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF151A23),
        title: Text(name, style: const TextStyle(color: Colors.white)),
        content: Text(
          'Uloga: $role\n'
          'Koordinate: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}\n'
          'Baterija: ${battery > 0 ? '$battery%' : 'Nepoznato'}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  void _showSosInfo(MapEntry<String, Map<String, dynamic>> entry) {
    final sender = entry.value['sender']?.toString() ?? entry.key;
    final message = entry.value['message']?.toString() ?? '';
    final lat = _toDouble(entry.value['lat']);
    final lng = _toDouble(entry.value['lng']);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF151A23),
        title: const Text(
          '🆘 AKTIVAN SOS',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Text(
          'Pošiljalac: $sender\n'
          '${_isValidLatLng(lat, lng) ? 'Lokacija: ${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}\n' : ''}'
          '$message',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  List<Marker> _meshUserMarkers() {
    return widget.meshUserLocations.entries
        .map((entry) {
          final lat = _toDouble(entry.value['lat']);
          final lng = _toDouble(entry.value['lng']);

          if (!_isValidLatLng(lat, lng)) return null;

          final role = (entry.value['role'] ?? 'Volonter').toString();
          final battery = _toDouble(entry.value['battery'])?.toInt() ?? 0;
          final isSelectedForTeam = widget.selectedTeamMembers.contains(entry.key);

          return Marker(
            point: LatLng(lat!, lng!),
            width: 90,
            height: 70,
            child: GestureDetector(
              onTap: () {
  if (widget.isCreatingTeam) {
    widget.onUserMarkerTap(entry.key);
    return;
  }

  _showUserInfo(
    name: entry.key,
    role: role,
    lat: lat,
    lng: lng,
    battery: battery,
  );
},
              child: Column(
                children: [
                  Container(
  padding: const EdgeInsets.all(3),
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    border: isSelectedForTeam
        ? Border.all(color: Colors.blueAccent, width: 3)
        : null,
    boxShadow: isSelectedForTeam
        ? [
            BoxShadow(
              color: Colors.blueAccent.withValues(alpha: 0.65),
              blurRadius: 14,
              spreadRadius: 3,
            ),
          ]
        : [],
  ),
  child: Image.asset(_roleMarker(role), width: 42, height: 42),
),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
    final userMarkers = _meshUserMarkers();
    final sosMarkers = _sosMarkers();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: _currentZoom,
              onPositionChanged: (position, hasGesture) {
                if (!hasGesture) return;

                final center = position.center;
                final zoom = _safeZoom(position.zoom);

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
                    : CommandCenterOfflineTileProvider(_offlineTileRootPath!),
              ),
              if (userMarkers.isNotEmpty) MarkerLayer(markers: userMarkers),
              if (sosMarkers.isNotEmpty) MarkerLayer(markers: sosMarkers),
            ],
          ),

          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF081120).withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.blueAccent.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'SITUACIJSKA MAPA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'OFFLINE READY',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CommandCenterOfflineTileProvider extends TileProvider {
  final String rootPath;

  CommandCenterOfflineTileProvider(this.rootPath);

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

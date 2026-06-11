import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF0E1117),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
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
        onPressed: () {},
        icon: const Icon(Icons.download),
        label: const Text('Skini mapu'),
      ),
    );
  }
}
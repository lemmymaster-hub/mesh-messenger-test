import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

LatLng? meshPoint(Map<String, dynamic> data) {
  final lat = double.tryParse('${data['lat']}');
  final lng = double.tryParse('${data['lng']}');
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat.abs() > 90 ||
      lng.abs() > 180) {
    return null;
  }
  return LatLng(lat, lng);
}

class CommandCenterMapPanel extends StatefulWidget {
  const CommandCenterMapPanel({
    super.key,
    required this.meshUserLocations,
    required this.meshSosLocations,
    required this.onUserMarkerTap,
    this.teamColorsByMember = const {},
    this.focus,
    this.resources = const [],
    this.compact = false,
  });
  final Map<String, Map<String, dynamic>> meshUserLocations;
  final Map<String, Map<String, dynamic>> meshSosLocations;
  final ValueChanged<String> onUserMarkerTap;
  final Map<String, Color> teamColorsByMember;
  final ValueNotifier<LatLng?>? focus;
  final List<Map<String, dynamic>> resources;
  final bool compact;
  @override
  State<CommandCenterMapPanel> createState() => _CommandCenterMapPanelState();
}

class _CommandCenterMapPanelState extends State<CommandCenterMapPanel> {
  final _controller = MapController();
  final _search = TextEditingController();
  String? _root;
  bool _ready = false;
  bool _satellite = true;
  bool _users = true, _sos = true, _resources = true, _terrain = false;
  @override
  void initState() {
    super.initState();
    widget.focus?.addListener(_focus);
    getApplicationDocumentsDirectory()
        .then((dir) {
          if (mounted) {
            setState(() => _root = '${dir.path}/offline_tiles');
          }
        })
        .catchError((Object _) {});
  }

  void _focus() {
    final point = widget.focus?.value;
    if (_ready && point != null) {
      _controller.move(point, 15);
    }
  }

  void _fit() {
    if (!_ready) {
      return;
    }
    final points = [
      ...widget.meshUserLocations.values,
      ...widget.meshSosLocations.values,
    ].map(meshPoint).whereType<LatLng>().toList();
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      _controller.move(points.first, 14);
      return;
    }
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(60),
        maxZoom: 16,
      ),
    );
  }

  Future<void> _locate() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        throw StateError('Dozvoli pristup lokaciji u postavkama telefona.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted && _ready) {
        _controller.move(LatLng(position.latitude, position.longitude), 15);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lokacija nije dostupna: $e')));
      }
    }
  }

  void _find() {
    final query = _search.text.trim().toLowerCase();
    final coords = query.split(',');
    LatLng? point;
    if (coords.length == 2) {
      point = meshPoint({'lat': coords[0], 'lng': coords[1]});
    }
    for (final e in widget.meshUserLocations.entries) {
      if (query.isNotEmpty &&
          '${e.value['deviceName'] ?? e.key}'.toLowerCase().contains(query)) {
        point ??= meshPoint(e.value);
        break;
      }
    }
    if (point != null && _ready) {
      _controller.move(point, 15);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unesi ime poznatog korisnika ili koordinate: lat, lng',
          ),
        ),
      );
    }
  }

  void _zoom(int delta) {
    if (_ready) {
      _controller.move(
        _controller.camera.center,
        (_controller.camera.zoom + delta).clamp(3, 19),
      );
    }
  }

  Widget _optionsMenu() => PopupMenuButton<String>(
    tooltip: widget.compact ? 'Opcije mape' : 'Slojevi',
    icon: const Icon(Icons.layers_outlined),
    onSelected: (value) {
      if (value == 'zoom_in') {
        _zoom(1);
        return;
      }
      if (value == 'zoom_out') {
        _zoom(-1);
        return;
      }
      if (value == 'locate') {
        _locate();
        return;
      }
      if (value == 'fit') {
        _fit();
        return;
      }
      if (value == 'legend') {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Oznake i mapa'),
            content: const Text(
              'Sive oznake prikazuju pozicije starije od 2 minute. OSM koristi postojeće lokalne pločice. Satelitska i topografska podloga zahtijevaju internet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Zatvori'),
              ),
            ],
          ),
        );
        return;
      }
      setState(() {
        if (value == 'users') {
          _users = !_users;
        }
        if (value == 'sos') {
          _sos = !_sos;
        }
        if (value == 'resources') {
          _resources = !_resources;
        }
        if (value == 'terrain') {
          _terrain = !_terrain;
          _satellite = false;
        }
        if (value == 'satellite') {
          _satellite = !_satellite;
          _terrain = false;
        }
      });
    },
    itemBuilder: (_) => [
      if (widget.compact) ...[
        const PopupMenuItem(value: 'locate', child: Text('Moja lokacija')),
        const PopupMenuItem(value: 'fit', child: Text('Prikaži sve oznake')),
        const PopupMenuItem(value: 'zoom_in', child: Text('Uvećaj mapu')),
        const PopupMenuItem(value: 'zoom_out', child: Text('Umanji mapu')),
        const PopupMenuDivider(),
      ],
      CheckedPopupMenuItem(
        value: 'users',
        checked: _users,
        child: const Text('Korisnici'),
      ),
      CheckedPopupMenuItem(
        value: 'sos',
        checked: _sos,
        child: const Text('SOS'),
      ),
      CheckedPopupMenuItem(
        value: 'resources',
        checked: _resources,
        child: const Text('Resursi • ručni unos'),
      ),
      CheckedPopupMenuItem(
        value: 'satellite',
        checked: _satellite,
        child: const Text('Satelitska mapa • internet'),
      ),
      CheckedPopupMenuItem(
        value: 'terrain',
        checked: _terrain,
        child: const Text('Topografska mapa • internet'),
      ),
      const PopupMenuItem(
        value: 'legend',
        child: Text('Oznake i offline podloga'),
      ),
    ],
  );

  Widget _marker(
    String label,
    IconData icon,
    Color color,
    VoidCallback tap, {
    bool stale = false,
  }) => InkWell(
    onTap: tap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF08121D),
            border: Border.all(color: stale ? Colors.grey : color, width: 2),
          ),
          child: Icon(icon, color: stale ? Colors.grey : color, size: 22),
        ),
        Container(
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
      ],
    ),
  );
  void _details(String title, Map<String, dynamic> data) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        '${data['message'] ?? data['type'] ?? ''}\n${data['lat'] ?? '—'}, ${data['lng'] ?? '—'}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Zatvori'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    if (_users) {
      for (final e in widget.meshUserLocations.entries) {
        final p = meshPoint(e.value);
        if (p == null) {
          continue;
        }
        final time = (e.value['time'] as num?)?.toInt() ?? 0;
        markers.add(
          Marker(
            point: p,
            width: 110,
            height: 74,
            child: _marker(
              '${e.value['deviceName'] ?? e.key}',
              Icons.person,
              widget.teamColorsByMember[e.key] ?? Colors.blueAccent,
              () => widget.onUserMarkerTap(e.key),
              stale: DateTime.now().millisecondsSinceEpoch - time > 120000,
            ),
          ),
        );
      }
    }
    if (_sos) {
      for (final e in widget.meshSosLocations.entries) {
        final p = meshPoint(e.value);
        if (p == null) {
          continue;
        }
        markers.add(
          Marker(
            point: p,
            width: 110,
            height: 74,
            child: _marker(
              '${e.value['sender'] ?? 'SOS'}',
              Icons.sos,
              Colors.redAccent,
              () => _details('SOS', e.value),
            ),
          ),
        );
      }
    }
    if (_resources) {
      for (final resource in widget.resources) {
        final p = meshPoint(resource);
        if (p == null) {
          continue;
        }
        markers.add(
          Marker(
            point: p,
            width: 110,
            height: 74,
            child: _marker(
              '${resource['name']}',
              resource['type'] == 'Repetitor'
                  ? Icons.cell_tower
                  : resource['type'] == 'Dron'
                  ? Icons.flight
                  : Icons.local_shipping,
              Colors.amber,
              () => _details('Ručno evidentiran resurs', resource),
            ),
          ),
        );
      }
    }
    return LayoutBuilder(
      builder: (context, bounds) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                backgroundColor: const Color(0xFF10212C),
                initialCenter: const LatLng(43.85, 18.38),
                initialZoom: 11,
                onMapReady: () {
                  _ready = true;
                  _fit();
                  _focus();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _satellite
                      ? 'https://services.arcgisonline.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : _terrain
                      ? 'https://tile.opentopomap.org/{z}/{x}/{y}.png'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  errorTileCallback: (tile, error, stackTrace) {
                    // Prefer the reference imagery, but retain offline basemap access.
                    if (_satellite) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _satellite) {
                          setState(() => _satellite = false);
                        }
                      });
                    }
                  },
                  maxNativeZoom: _terrain ? 17 : 19,
                  userAgentPackageName: 'ba.noria.nrnmesh',
                  tileProvider: _satellite || _terrain || _root == null
                      ? NetworkTileProvider()
                      : CommandCenterOfflineTileProvider(_root!),
                ),
                MarkerLayer(markers: markers),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      _satellite
                          ? 'Source: Esri, Vantor, Earthstar Geographics, GIS User Community'
                          : _terrain
                          ? '© OpenStreetMap • SRTM • OpenTopoMap (CC-BY-SA)'
                          : '© OpenStreetMap contributors',
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 65,
              child: Material(
                color: const Color(0xEE0B1622),
                borderRadius: BorderRadius.circular(6),
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) => _find(),
                  style: TextStyle(fontSize: widget.compact ? 15 : 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.compact
                        ? 'Korisnik ili GPS'
                        : 'Korisnik ili lat, lng',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: IconButton(
                      tooltip: 'Pretraži mapu',
                      onPressed: _find,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: const Color(0xEE0B1622),
                child: widget.compact
                    ? _optionsMenu()
                    : Column(
                        children: [
                          IconButton(
                            tooltip: 'Uvećaj',
                            onPressed: () {
                              if (_ready) {
                                _controller.move(
                                  _controller.camera.center,
                                  (_controller.camera.zoom + 1).clamp(3, 19),
                                );
                              }
                            },
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            tooltip: 'Umanji',
                            onPressed: () {
                              if (_ready) {
                                _controller.move(
                                  _controller.camera.center,
                                  (_controller.camera.zoom - 1).clamp(3, 19),
                                );
                              }
                            },
                            icon: const Icon(Icons.remove),
                          ),
                          IconButton(
                            tooltip: 'Moja lokacija',
                            onPressed: _locate,
                            icon: const Icon(Icons.my_location),
                          ),
                          IconButton(
                            tooltip: 'Prikaži sve',
                            onPressed: _fit,
                            icon: const Icon(Icons.center_focus_strong),
                          ),
                          _optionsMenu(),
                        ],
                      ),
              ),
            ),
            if (widget.compact && bounds.maxHeight > 180)
              Positioned(
                bottom: 42,
                right: 10,
                child: Material(
                  color: const Color(0xEE0B1622),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Moja lokacija',
                    onPressed: _locate,
                    icon: const Icon(Icons.my_location),
                  ),
                ),
              ),
            if (!widget.compact)
              const Positioned(
                bottom: 30,
                left: 10,
                child: Material(
                  color: Color(0xCC0B1622),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Text(
                      'Sive pozicije: starije od 2 min\nOSM koristi postojeće lokalne pločice',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.focus?.removeListener(_focus);
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }
}

class CommandCenterOfflineTileProvider extends TileProvider {
  CommandCenterOfflineTileProvider(this.rootPath);
  final String rootPath;
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final file = File(
      '$rootPath/${coordinates.z.round()}/${coordinates.x.round()}/${coordinates.y.round()}.png',
    );
    return file.existsSync()
        ? FileImage(file)
        : NetworkImage(
            'https://tile.openstreetmap.org/${coordinates.z.round()}/${coordinates.x.round()}/${coordinates.y.round()}.png',
          );
  }
}

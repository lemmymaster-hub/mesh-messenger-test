import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class OfflineMapService {
  static const userAgent = 'NRN Mesh / ba.noria.nrnmesh';
  static const tileSourceKey = 'nrn_offline_tile_source';
  static const defaultOfflineSource = String.fromEnvironment(
    'NRN_OFFLINE_TILE_URL',
  );
  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
  static const _pngEnd = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
  static int _tempSequence = 0;

  static bool validOfflineSource(String template) {
    if (!['{z}', '{x}', '{y}'].every(template.contains)) return false;
    final uri = Uri.tryParse(_tileUrl(template, 1, 0, 0));
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.+$'), '');
    return host != 'openstreetmap.org' && !host.endsWith('.openstreetmap.org');
  }

  static String _tileUrl(String template, int z, int x, int y) => template
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  static bool _matches(List<int> bytes, List<int> marker) {
    if (bytes.length < marker.length) return false;
    for (var i = 0; i < marker.length; i++) {
      if (bytes[i] != marker[i]) return false;
    }
    return true;
  }

  Future<bool> _validTile(File file) async {
    if (!await file.exists()) return false;
    final reader = await file.open();
    try {
      final size = await reader.length();
      if (size < _pngSignature.length + _pngEnd.length ||
          !_matches(await reader.read(_pngSignature.length), _pngSignature)) {
        return false;
      }
      await reader.setPosition(size - _pngEnd.length);
      return _matches(await reader.read(_pngEnd.length), _pngEnd);
    } finally {
      await reader.close();
    }
  }

  Future<Directory> offlineTileRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}/offline_tiles');
    await root.create(recursive: true);
    return root;
  }

  Future<int> offlineCacheSizeBytes() async {
    final root = await offlineTileRoot();

    if (!await root.exists()) {
      return 0;
    }

    int total = 0;

    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }

    return total;
  }

  int lonToTileX(double lon, int zoom) {
    final safeZoom = zoom.clamp(1, 19);
    final tiles = 1 << safeZoom;
    final x = ((lon + 180.0) / 360.0 * tiles).floor();

    return x.clamp(0, tiles - 1);
  }

  int latToTileY(double lat, int zoom) {
    final safeZoom = zoom.clamp(1, 19);

    // Web Mercator ne podržava polove.
    // Ograničavamo latitude na sigurni raspon.
    final safeLat = lat.clamp(-85.05112878, 85.05112878);
    final latRad = safeLat * pi / 180.0;
    final tiles = 1 << safeZoom;

    final y = ((1.0 - (log(tan(latRad) + 1 / cos(latRad)) / pi)) /
            2.0 *
            tiles)
        .floor();

    return y.clamp(0, tiles - 1);
  }

  Future<bool> _downloadTile(
    Directory root,
    http.Client client,
    String source,
    int z,
    int x,
    int y,
  ) async {
    final file = File('${root.path}/$z/$x/$y.png');
    try {
      if (await _validTile(file)) return true;

      final request = http.Request('GET', Uri.parse(_tileUrl(source, z, x, y)))
        ..followRedirects = false
        ..headers['User-Agent'] = userAgent;
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 10));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.length < 45 ||
          !_matches(bytes, _pngSignature) ||
          !_matches(bytes.sublist(bytes.length - _pngEnd.length), _pngEnd)) {
        return false;
      }

      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.${_tempSequence++}.tmp');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      return true;
    } catch (error) {
      developer.log(
        'Pločica $z/$x/$y nije preuzeta: ${error.runtimeType}',
        name: 'NRN_OFFLINE_MAP',
      );
      return false;
    }
  }

  Future<OfflineTileDownloadResult> downloadArea({
    required double centerLat,
    required double centerLng,
    required String source,

    /// Koristi se kada skidaš samo jedan zoom nivo.
    int? zoom,

    /// Koristi se kada skidaš više zoom nivoa, npr. [13, 14].
    List<int>? zoomLevels,

    /// radius 5 znači 11x11 tileova po zoom nivou.
    int radius = 1,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!validOfflineSource(source)) {
      throw const FormatException(
        'Unesi HTTPS izvor PNG pločica koji dozvoljava offline preuzimanje.',
      );
    }
    if (!centerLat.isFinite ||
        centerLat.abs() > 90 ||
        !centerLng.isFinite ||
        centerLng.abs() > 180) {
      throw const FormatException('Neispravan centar offline područja.');
    }
    final selectedZoomLevels = <int>{
      if (zoom != null) zoom.clamp(1, 19),
      if (zoomLevels != null) ...zoomLevels.map((item) => item.clamp(1, 19)),
    }.toList()..sort();
    if (selectedZoomLevels.isEmpty) selectedZoomLevels.add(13);

    final safeRadius = radius.clamp(0, 10);
    final areas = <int, ({int x, int y, Set<(int, int)> tiles})>{};
    for (final z in selectedZoomLevels) {
      final centerX = lonToTileX(centerLng, z);
      final centerY = latToTileY(centerLat, z);
      final world = 1 << z;
      final tiles = <(int, int)>{
        for (var x = centerX - safeRadius; x <= centerX + safeRadius; x++)
          for (
            var y = max(0, centerY - safeRadius);
            y <= min(world - 1, centerY + safeRadius);
            y++
          )
            (x % world, y),
      };
      areas[z] = (x: centerX, y: centerY, tiles: tiles);
    }

    final total = areas.values.fold(0, (sum, area) => sum + area.tiles.length);
    final root = await offlineTileRoot();
    final client = http.Client();
    var processed = 0;
    var success = 0;
    final zoomResults = <OfflineZoomDownloadResult>[];
    try {
      for (final entry in areas.entries) {
        final z = entry.key;
        final area = entry.value;
        final tiles = area.tiles.toList();
        var zoomSuccess = 0;
        for (var i = 0; i < tiles.length; i += 4) {
          final batch = tiles.skip(i).take(4);
          final results = await Future.wait(
            batch.map(
              (tile) =>
                  _downloadTile(root, client, source, z, tile.$1, tile.$2),
            ),
          );
          zoomSuccess += results.where((ok) => ok).length;
          processed += results.length;
          onProgress?.call(processed, total);
        }
        success += zoomSuccess;
        zoomResults.add(
          OfflineZoomDownloadResult(
            zoom: z,
            centerX: area.x,
            centerY: area.y,
            radius: safeRadius,
            total: tiles.length,
            success: zoomSuccess,
            failed: tiles.length - zoomSuccess,
          ),
        );
      }
    } finally {
      client.close();
    }
    return OfflineTileDownloadResult(
      zoomLevels: selectedZoomLevels,
      radius: safeRadius,
      total: total,
      success: success,
      failed: total - success,
      zoomResults: zoomResults,
    );
  }
}

class OfflineZoomDownloadResult {
  final int zoom;
  final int centerX;
  final int centerY;
  final int radius;
  final int total;
  final int success;
  final int failed;

  const OfflineZoomDownloadResult({
    required this.zoom,
    required this.centerX,
    required this.centerY,
    required this.radius,
    required this.total,
    required this.success,
    required this.failed,
  });

  bool get isComplete => total > 0 && success == total;

  @override
  String toString() {
    return 'OfflineZoomDownloadResult('
        'zoom: $zoom, '
        'centerX: $centerX, '
        'centerY: $centerY, '
        'radius: $radius, '
        'total: $total, '
        'success: $success, '
        'failed: $failed'
        ')';
  }
}

class OfflineTileDownloadResult {
  final List<int> zoomLevels;
  final int radius;
  final int total;
  final int success;
  final int failed;
  final List<OfflineZoomDownloadResult> zoomResults;

  const OfflineTileDownloadResult({
    required this.zoomLevels,
    required this.radius,
    required this.total,
    required this.success,
    required this.failed,
    required this.zoomResults,
  });

  /// Alias radi kompatibilnosti sa kodom koji očekuje result.downloaded.
  int get downloaded => success;

  bool get isComplete => total > 0 && success == total;

  @override
  String toString() {
    return 'OfflineTileDownloadResult('
        'zoomLevels: $zoomLevels, '
        'radius: $radius, '
        'total: $total, '
        'success: $success, '
        'failed: $failed'
        ')';
  }
}

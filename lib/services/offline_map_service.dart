import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class OfflineMapService {
  static const String _userAgent = 'BSL Mesh Lite / mesh_messenger_test';

  Future<Directory> offlineTileRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}/offline_tiles');
    await root.create(recursive: true);
    return root;
  }

  String tileUrl(int z, int x, int y) {
    return 'https://tile.openstreetmap.org/$z/$x/$y.png';
  }

  Future<File> tileFile(int z, int x, int y) async {
    final root = await offlineTileRoot();
    final file = File('${root.path}/$z/$x/$y.png');
    await file.parent.create(recursive: true);
    return file;
  }
Future<File?> existingTileFile(int z, int x, int y) async {
  final file = await tileFile(z, x, y);

  if (await file.exists()) {
    return file;
  }

  return null;
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

  Future<bool> tileExists(int z, int x, int y) async {
    final file = await tileFile(z, x, y);
    return file.exists();
  }

  void _log(String message) {
    developer.log(message, name: 'BSL_OFFLINE_MAP');
  }

  Future<bool> downloadTile(int z, int x, int y) async {
    _log('BSL downloadTile called: z=$z x=$x y=$y');

    try {
      final safeZoom = z.clamp(1, 19);
      final maxTile = (1 << safeZoom) - 1;
      final safeX = x.clamp(0, maxTile);
      final safeY = y.clamp(0, maxTile);

      final file = await tileFile(safeZoom, safeX, safeY);

      if (await file.exists()) {
        _log('BSL OFFLINE TILE ALREADY EXISTS: ${file.path}');
        return true;
      }

      final url = tileUrl(safeZoom, safeX, safeY);
      _log('BSL TILE URL: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 10));

      _log('BSL TILE HTTP STATUS: ${response.statusCode}');

      if (response.statusCode != 200) {
        _log('BSL TILE DOWNLOAD FAILED: status=${response.statusCode}');
        return false;
      }

      if (response.bodyBytes.isEmpty) {
        _log('BSL TILE DOWNLOAD FAILED: empty body');
        return false;
      }

      await file.writeAsBytes(response.bodyBytes, flush: true);

      final size = await file.length();
      _log('BSL OFFLINE TILE SAVED: ${file.path} | $size bytes');

      return true;
    } catch (e) {
      _log('BSL TILE ERROR: $e');
      return false;
    }
  }

  Future<OfflineTileDownloadResult> downloadArea({
    required double centerLat,
    required double centerLng,

    /// Koristi se kada skidaš samo jedan zoom nivo.
    int? zoom,

    /// Koristi se kada skidaš više zoom nivoa, npr. [13, 14].
    List<int>? zoomLevels,

    /// radius 5 znači 11x11 tileova po zoom nivou.
    int radius = 1,
    void Function(int current, int total)? onProgress,
  }) async {
    final selectedZoomLevels = <int>{
      if (zoom != null) zoom.clamp(1, 19),
      if (zoomLevels != null)
        ...zoomLevels.map((item) => item.clamp(1, 19)),
    }.toList()
      ..sort();

    if (selectedZoomLevels.isEmpty) {
      selectedZoomLevels.add(13);
    }

    final safeRadius = radius.clamp(0, 10);

    int total = 0;
    int success = 0;
    int failed = 0;
    final totalExpected =
    selectedZoomLevels.length * (safeRadius * 2 + 1) * (safeRadius * 2 + 1);

int processed = 0;

    final zoomResults = <OfflineZoomDownloadResult>[];

    for (final safeZoom in selectedZoomLevels) {
      final centerX = lonToTileX(centerLng, safeZoom);
      final centerY = latToTileY(centerLat, safeZoom);

      int zoomTotal = 0;
      int zoomSuccess = 0;
      int zoomFailed = 0;

      for (int x = centerX - safeRadius; x <= centerX + safeRadius; x++) {
        for (int y = centerY - safeRadius; y <= centerY + safeRadius; y++) {
          zoomTotal++;
          total++;

          final ok = await downloadTile(safeZoom, x, y);

          if (ok) {
            zoomSuccess++;
            success++;
          } else {
            zoomFailed++;
            failed++;
          }
          processed++;
onProgress?.call(processed, totalExpected);
        }
      }

      zoomResults.add(
        OfflineZoomDownloadResult(
          zoom: safeZoom,
          centerX: centerX,
          centerY: centerY,
          radius: safeRadius,
          total: zoomTotal,
          success: zoomSuccess,
          failed: zoomFailed,
        ),
      );
    }

    final result = OfflineTileDownloadResult(
      zoomLevels: selectedZoomLevels,
      radius: safeRadius,
      total: total,
      success: success,
      failed: failed,
      zoomResults: zoomResults,
    );

    _log('BSL DOWNLOAD AREA RESULT: $result');

    return result;
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

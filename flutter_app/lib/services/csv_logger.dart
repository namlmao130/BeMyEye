/// csv_logger.dart
/// Công cụ thu thập và trích xuất dữ liệu đo đạc thực địa (CSV Logging)
/// Giúp người kiểm thử trên thiết bị thật ghi lại FPS, độ trễ và các cảnh báo để gửi về phân tích.

class CsvLogEntry {
  final String timestamp;
  final double fps;
  final int latencyPreprocessMs;
  final int latencyInferenceMs;
  final int latencyAnalysisMs;
  final int latencyTotalMs;
  final int objectCount;
  final String primaryThreat;
  final String threatDirection;
  final String threatDistance;
  final String delegate;

  CsvLogEntry({
    required this.timestamp,
    required this.fps,
    required this.latencyPreprocessMs,
    required this.latencyInferenceMs,
    required this.latencyAnalysisMs,
    required this.latencyTotalMs,
    required this.objectCount,
    required this.primaryThreat,
    required this.threatDirection,
    required this.threatDistance,
    required this.delegate,
  });

  String toCsvRow() {
    return '$timestamp,'
        '${fps.toStringAsFixed(1)},'
        '$latencyPreprocessMs,'
        '$latencyInferenceMs,'
        '$latencyAnalysisMs,'
        '$latencyTotalMs,'
        '$objectCount,'
        '"$primaryThreat",'
        '"$threatDirection",'
        '"$threatDistance",'
        '"$delegate"';
  }
}

class CsvLogger {
  static const String csvHeader =
      'timestamp,fps,latency_preprocess_ms,latency_inference_ms,latency_analysis_ms,latency_total_ms,object_count,primary_threat,threat_direction,threat_distance,delegate';

  final List<CsvLogEntry> _entries = [];
  static const int maxEntries = 5000;

  int get rowCount => _entries.length;
  List<CsvLogEntry> get entries => List.unmodifiable(_entries);

  void logFrame({
    required double fps,
    required int latencyPreprocessMs,
    required int latencyInferenceMs,
    required int latencyAnalysisMs,
    required int latencyTotalMs,
    required int objectCount,
    required String primaryThreat,
    required String threatDirection,
    required String threatDistance,
    required String delegate,
  }) {
    if (_entries.length >= maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(CsvLogEntry(
      timestamp: DateTime.now().toIso8601String(),
      fps: fps,
      latencyPreprocessMs: latencyPreprocessMs,
      latencyInferenceMs: latencyInferenceMs,
      latencyAnalysisMs: latencyAnalysisMs,
      latencyTotalMs: latencyTotalMs,
      objectCount: objectCount,
      primaryThreat: primaryThreat,
      threatDirection: threatDirection,
      threatDistance: threatDistance,
      delegate: delegate,
    ));
  }

  String exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln(csvHeader);
    for (final entry in _entries) {
      buffer.writeln(entry.toCsvRow());
    }
    return buffer.toString();
  }

  void clear() {
    _entries.clear();
  }
}

import 'dart:collection';
import 'dart:math';

import '../config/thresholds.dart';

/// csv_logger.dart
/// Công cụ thu thập và trích xuất dữ liệu đo đạc thực địa (CSV Logging)
/// Giúp người kiểm thử trên thiết bị thật ghi lại FPS, độ trễ, pin, nhiệt độ và các cảnh báo để gửi về phân tích.
///
/// Hỗ trợ chế độ Đo hiệu năng 3 phút (Benchmark Mode) với thông điệp trung thực:
/// "Cần chạy trên máy thật để có số liệu kiểm chứng, không tự khẳng định kết quả".

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
  final int batteryLevel;
  final int thermalStatus;

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
    this.batteryLevel = 100,
    this.thermalStatus = 0,
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
        '"$delegate",'
        '$batteryLevel,'
        '$thermalStatus';
  }
}

class CsvLogger {
  static const String csvHeader =
      'timestamp,fps,latency_preprocess_ms,latency_inference_ms,latency_analysis_ms,latency_total_ms,object_count,primary_threat,threat_direction,threat_distance,delegate,battery_level,thermal_status';

  final ListQueue<CsvLogEntry> _entries = ListQueue<CsvLogEntry>();
  static const int maxEntries = 5000;

  /// Cờ kiểm soát việc ghi log:
  /// - Mặc định là false (tắt hoàn toàn ở chế độ thông thường để tối ưu FPS và triệt tiêu cấp phát rác GC).
  /// - Tự động ghi khi isBenchmarkRunning == true (chế độ đo đạc).
  /// - Có thể bật isLoggingEnabled = true để phục vụ Unit Tests hoặc kiểm tra thủ công.
  bool isLoggingEnabled = false;

  // Trạng thái chế độ Benchmark đo hiệu năng 3 phút
  bool isBenchmarkRunning = false;
  int benchmarkStartTimeMs = 0;
  int benchmarkDurationSeconds = kBenchmarkDurationSeconds;
  final List<CsvLogEntry> _benchmarkEntries = [];
  void Function(String csvData)? onBenchmarkComplete;

  int get rowCount => _entries.length;
  List<CsvLogEntry> get entries => _entries.toList(growable: false);
  List<CsvLogEntry> get benchmarkEntries =>
      List.unmodifiable(_benchmarkEntries);

  int get benchmarkElapsedSeconds {
    if (!isBenchmarkRunning || benchmarkStartTimeMs == 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return ((now - benchmarkStartTimeMs) / 1000)
        .clamp(0, benchmarkDurationSeconds)
        .toInt();
  }

  int get benchmarkRemainingSeconds {
    final remaining = benchmarkDurationSeconds - benchmarkElapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  /// Bắt đầu chế độ Benchmark đo hiệu năng (mặc định 180s = 3 phút)
  void startBenchmark({
    int durationSeconds = kBenchmarkDurationSeconds,
    void Function(String csvData)? onComplete,
    int? customNowMs,
  }) {
    isBenchmarkRunning = true;
    benchmarkDurationSeconds = durationSeconds;
    benchmarkStartTimeMs = customNowMs ?? DateTime.now().millisecondsSinceEpoch;
    onBenchmarkComplete = onComplete;
    _benchmarkEntries.clear();
  }

  /// Dừng chế độ Benchmark
  void stopBenchmark() {
    isBenchmarkRunning = false;
  }

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
    int batteryLevel = 100,
    int thermalStatus = 0,
    int? customNowMs,
  }) {
    // Chỉ ghi CSV khi chạy Benchmark hoặc khi bật isLoggingEnabled (kiểm thử)
    // Tắt hoàn toàn ở chế độ thường để đạt FPS tối đa và triệt tiêu Garbage Collection churn
    if (!isBenchmarkRunning && !isLoggingEnabled) {
      return;
    }

    final entry = CsvLogEntry(
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
      batteryLevel: batteryLevel,
      thermalStatus: thermalStatus,
    );

    if (_entries.length >= maxEntries) {
      _entries.removeFirst();
    }
    _entries.add(entry);

    // Ghi nhận dữ liệu Benchmark nếu đang trong phiên đo
    if (isBenchmarkRunning) {
      _benchmarkEntries.add(entry);
      final now = customNowMs ?? DateTime.now().millisecondsSinceEpoch;
      final elapsed = (now - benchmarkStartTimeMs) / 1000.0;
      if (elapsed >= benchmarkDurationSeconds) {
        isBenchmarkRunning = false;
        final exported = exportBenchmarkCsv();
        onBenchmarkComplete?.call(exported);
      }
    }
  }

  /// Tính toán số liệu thống kê trung thực từ dữ liệu Benchmark
  Map<String, dynamic> computeBenchmarkStats([
    Iterable<CsvLogEntry>? customList,
  ]) {
    final list =
        customList ?? (isBenchmarkRunning ? _benchmarkEntries : _entries);
    if (list.isEmpty) {
      return {
        'status': 'Chưa có số liệu (Cần chạy trên máy thật)',
        'frameCount': 0,
        'avgFps': 0.0,
        'minFps': 0.0,
        'maxFps': 0.0,
        'avgPreprocessMs': 0.0,
        'avgInferenceMs': 0.0,
        'avgAnalysisMs': 0.0,
        'avgTotalMs': 0.0,
        'delegate': 'Unknown',
        'isRealDeviceData': false,
      };
    }

    double sumFps = 0.0;
    double minFps = list.first.fps;
    double maxFps = list.first.fps;

    int sumPreprocess = 0;
    int sumInference = 0;
    int sumAnalysis = 0;
    int sumTotal = 0;
    final Set<String> delegates = {};

    for (final e in list) {
      sumFps += e.fps;
      minFps = min(minFps, e.fps);
      maxFps = max(maxFps, e.fps);

      sumPreprocess += e.latencyPreprocessMs;
      sumInference += e.latencyInferenceMs;
      sumAnalysis += e.latencyAnalysisMs;
      sumTotal += e.latencyTotalMs;
      delegates.add(e.delegate);
    }

    final int count = list.length;
    return {
      'status': 'Số liệu cần được người dùng chạy kiểm chứng trên máy thật',
      'frameCount': count,
      'avgFps': sumFps / count,
      'minFps': minFps,
      'maxFps': maxFps,
      'avgPreprocessMs': sumPreprocess / count,
      'avgInferenceMs': sumInference / count,
      'avgAnalysisMs': sumAnalysis / count,
      'avgTotalMs': sumTotal / count,
      'delegate': delegates.join(', '),
      'isRealDeviceData': true,
    };
  }

  /// Xuất báo cáo Benchmark 3 phút với phần tiêu đề trung thực
  String exportBenchmarkCsv() {
    final stats = computeBenchmarkStats(_benchmarkEntries);
    final buffer = StringBuffer();
    buffer.writeln(
      '# ============================================================',
    );
    buffer.writeln('# BÁO CÁO BENCHMARK HIỆU NĂNG 3 PHÚT - BE MY EYES VN');
    buffer.writeln(
      '# ============================================================',
    );
    buffer.writeln(
      '# TRẠNG THÁI SỐ LIỆU: CẦN CHẠY TRÊN MÁY THẬT ĐỂ LẤY SỐ LIỆU KIỂM CHỨNG.',
    );
    buffer.writeln(
      '# KHÔNG TỰ KHẲNG ĐỊNH KẾT QUẢ KHI CHƯA CÓ FILE LOG ĐO ĐẠC NÀY.',
    );
    buffer.writeln('# Thời lượng đo dự kiến: $benchmarkDurationSeconds giây');
    buffer.writeln(
      '# Số khung hình ghi nhận: ${stats['frameCount']} khung hình',
    );
    buffer.writeln(
      '# FPS trung bình: ${(stats['avgFps'] as double).toStringAsFixed(1)} (Min: ${(stats['minFps'] as double).toStringAsFixed(1)}, Max: ${(stats['maxFps'] as double).toStringAsFixed(1)})',
    );
    buffer.writeln('# Độ trễ trung bình:');
    buffer.writeln(
      '#   - Tiền xử lý camera->RGB: ${(stats['avgPreprocessMs'] as double).toStringAsFixed(1)} ms',
    );
    buffer.writeln(
      '#   - Suy luận TFLite:        ${(stats['avgInferenceMs'] as double).toStringAsFixed(1)} ms',
    );
    buffer.writeln(
      '#   - Phân tích không gian:   ${(stats['avgAnalysisMs'] as double).toStringAsFixed(1)} ms',
    );
    buffer.writeln(
      '#   - Tổng độ trễ pipeline:   ${(stats['avgTotalMs'] as double).toStringAsFixed(1)} ms',
    );
    buffer.writeln('# Delegate AI sử dụng: ${stats['delegate']}');
    buffer.writeln(
      '# ============================================================',
    );
    buffer.writeln(csvHeader);
    for (final entry in _benchmarkEntries) {
      buffer.writeln(entry.toCsvRow());
    }
    return buffer.toString();
  }

  String exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln(
      '# TRẠNG THÁI: DỮ LIỆU CẦN ĐO TRÊN THIẾT BỊ THẬT, KHÔNG TỰ BỊA SỐ HIỆU NĂNG',
    );
    buffer.writeln(csvHeader);
    for (final entry in _entries) {
      buffer.writeln(entry.toCsvRow());
    }
    return buffer.toString();
  }

  void clear() {
    _entries.clear();
    _benchmarkEntries.clear();
  }
}

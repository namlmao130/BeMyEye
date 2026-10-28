import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/services/csv_logger.dart';

void main() {
  group(
      'NV12.8 - Đo hiệu năng: Chế độ chạy 3 phút xuất CSV & Yêu cầu đo trên máy thật',
      () {
    test(
        'Tiêu chí 1: Khởi động và theo dõi tiến trình Benchmark 180 giây (3 phút)',
        () {
      final logger = CsvLogger();
      expect(logger.isBenchmarkRunning, isFalse);

      logger.startBenchmark(durationSeconds: 180, customNowMs: 10000);

      expect(logger.isBenchmarkRunning, isTrue);
      expect(logger.benchmarkDurationSeconds, equals(180));
      expect(logger.benchmarkEntries, isEmpty);
    });

    test(
        'Tiêu chí 2: Thu thập FPS, độ trễ từng bước, delegate, nhiệt độ trong phiên đo',
        () {
      final logger = CsvLogger();
      logger.startBenchmark(durationSeconds: 180, customNowMs: 1000);

      // Ghi nhận 5 khung hình mẫu trong phiên benchmark
      for (int i = 1; i <= 5; i++) {
        logger.logFrame(
          fps: 15.0 + i,
          latencyPreprocessMs: 8,
          latencyInferenceMs: 45,
          latencyAnalysisMs: 5,
          latencyTotalMs: 58,
          objectCount: 2,
          primaryThreat: 'motorcycle',
          threatDirection: 'center',
          threatDistance: '1.5m - 3.0m',
          delegate: 'NNAPI (GPU Fallback)',
          batteryLevel: 85,
          thermalStatus: 1,
          customNowMs: 1000 + (i * 1000),
        );
      }

      expect(logger.benchmarkEntries.length, equals(5));

      final stats = logger.computeBenchmarkStats();
      expect(stats['frameCount'], equals(5));
      expect(stats['avgPreprocessMs'], equals(8.0));
      expect(stats['avgInferenceMs'], equals(45.0));
      expect(stats['avgAnalysisMs'], equals(5.0));
      expect(stats['avgTotalMs'], equals(58.0));
      expect(stats['delegate'], contains('NNAPI'));
      expect(stats['minFps'], equals(16.0));
      expect(stats['maxFps'], equals(20.0));
    });

    test(
        'Tiêu chí 3: Tự động hoàn thành sau khi đủ thời lượng và xuất CSV kèm Banner cảnh báo trung thực',
        () {
      final logger = CsvLogger();
      String? completedCsv;

      logger.startBenchmark(
        durationSeconds: 180,
        onComplete: (data) {
          completedCsv = data;
        },
        customNowMs: 0,
      );

      // Giả lập ghi frame ở mốc thời gian trước khi hết giờ (t = 100s < 180s)
      logger.logFrame(
        fps: 18.5,
        latencyPreprocessMs: 7,
        latencyInferenceMs: 42,
        latencyAnalysisMs: 4,
        latencyTotalMs: 53,
        objectCount: 1,
        primaryThreat: 'person',
        threatDirection: 'left',
        threatDistance: '> 3.0m',
        delegate: 'CPU',
        batteryLevel: 90,
        thermalStatus: 0,
        customNowMs: 100000,
      );
      expect(logger.isBenchmarkRunning, isTrue);
      expect(completedCsv, isNull);

      // Giả lập ghi frame khi đạt đủ 180s (t = 180s)
      logger.logFrame(
        fps: 19.0,
        latencyPreprocessMs: 6,
        latencyInferenceMs: 40,
        latencyAnalysisMs: 4,
        latencyTotalMs: 50,
        objectCount: 1,
        primaryThreat: 'person',
        threatDirection: 'left',
        threatDistance: '> 3.0m',
        delegate: 'CPU',
        batteryLevel: 89,
        thermalStatus: 0,
        customNowMs: 180000,
      );

      // Benchmark tự động dừng và trả về file CSV qua callback
      expect(logger.isBenchmarkRunning, isFalse);
      expect(completedCsv, isNotNull);

      // KHẲNG ĐỊNH BẮT BUỘC (NV12.8):
      // Tiêu đề file CSV phải ghi rõ "CẦN CHẠY TRÊN MÁY THẬT", không tự khẳng định kết quả
      expect(completedCsv, contains('CẦN CHẠY TRÊN MÁY THẬT'));
      expect(completedCsv, contains('BÁO CÁO BENCHMARK HIỆU NĂNG 3 PHÚT'));
      expect(completedCsv, contains('latency_preprocess_ms'));
      expect(completedCsv, contains('latency_inference_ms'));
      expect(completedCsv, contains('latency_analysis_ms'));
      expect(completedCsv, contains('latency_total_ms'));
      expect(completedCsv, contains('CPU'));
    });

    test(
        'Tiêu chí 4: Hàm exportCsv thông thường cũng có banner nhắc nhở dữ liệu thực địa',
        () {
      final logger = CsvLogger()..isLoggingEnabled = true;
      logger.logFrame(
        fps: 20.0,
        latencyPreprocessMs: 5,
        latencyInferenceMs: 38,
        latencyAnalysisMs: 3,
        latencyTotalMs: 46,
        objectCount: 0,
        primaryThreat: 'none',
        threatDirection: 'none',
        threatDistance: 'none',
        delegate: 'NNAPI',
      );

      final csv = logger.exportCsv();
      expect(csv, contains('TRẠNG THÁI: DỮ LIỆU CẦN ĐO TRÊN THIẾT BỊ THẬT'));
      expect(csv, contains('fps,latency_preprocess_ms'));
    });

    test(
        'Tiêu chí 5: Ở chế độ thường tắt hoàn toàn ghi CSV, chỉ ghi khi Benchmark hoạt động',
        () {
      final logger = CsvLogger();
      expect(logger.isLoggingEnabled, isFalse);
      expect(logger.isBenchmarkRunning, isFalse);

      // 1. Chế độ thường: logFrame() bị bỏ qua hoàn toàn để tối ưu FPS và bộ nhớ
      logger.logFrame(
        fps: 20.0,
        latencyPreprocessMs: 5,
        latencyInferenceMs: 38,
        latencyAnalysisMs: 3,
        latencyTotalMs: 46,
        objectCount: 0,
        primaryThreat: 'none',
        threatDirection: 'none',
        threatDistance: 'none',
        delegate: 'NNAPI',
      );
      expect(logger.rowCount, equals(0));

      // 2. Bắt đầu Benchmark: ghi nhận khung hình bình thường
      logger.startBenchmark(durationSeconds: 180);
      expect(logger.isBenchmarkRunning, isTrue);

      logger.logFrame(
        fps: 20.0,
        latencyPreprocessMs: 5,
        latencyInferenceMs: 38,
        latencyAnalysisMs: 3,
        latencyTotalMs: 46,
        objectCount: 0,
        primaryThreat: 'none',
        threatDirection: 'none',
        threatDistance: 'none',
        delegate: 'NNAPI',
      );
      expect(logger.rowCount, equals(1));

      // 3. Dừng Benchmark: ngay lập tức ngừng ghi nhận khung hình
      logger.stopBenchmark();
      expect(logger.isBenchmarkRunning, isFalse);

      logger.logFrame(
        fps: 20.0,
        latencyPreprocessMs: 5,
        latencyInferenceMs: 38,
        latencyAnalysisMs: 3,
        latencyTotalMs: 46,
        objectCount: 0,
        primaryThreat: 'none',
        threatDirection: 'none',
        threatDistance: 'none',
        delegate: 'NNAPI',
      );
      expect(logger.rowCount, equals(1)); // Vẫn là 1, không tăng thêm
    });
  });
}

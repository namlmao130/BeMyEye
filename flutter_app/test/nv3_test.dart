import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';
import 'package:be_my_eye_vn/services/image_preprocessor.dart';
import 'package:be_my_eye_vn/services/csv_logger.dart';
import 'package:be_my_eye_vn/services/battery_optimizer.dart';
import 'package:be_my_eye_vn/services/detector_service.dart';
import 'package:be_my_eye_vn/services/spatial_analyzer.dart';
import 'package:be_my_eye_vn/services/ground_analyzer.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';
import 'package:be_my_eye_vn/services/camera_pipeline_service.dart';

void main() {
  group('NV3 - Tiền xử lý khung hình (Image Preprocessor) trong Isolate', () {
    test('preprocessCameraFrame chuyển đổi chính xác kích thước RGB 300x300 và Luma 160x120', () {
      const srcW = 640;
      const srcH = 480;

      // Tạo dữ liệu YUV420 giả lập
      final yPlane = Uint8List(srcW * srcH);
      for (int i = 0; i < yPlane.length; i++) {
        yPlane[i] = (i % 256);
      }

      final uPlane = Uint8List((srcW ~/ 2) * (srcH ~/ 2));
      uPlane.fillRange(0, uPlane.length, 128);

      final vPlane = Uint8List((srcW ~/ 2) * (srcH ~/ 2));
      vPlane.fillRange(0, vPlane.length, 128);

      final frameData = CameraFrameData(
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: srcW,
        uvRowStride: srcW ~/ 2,
        yPixelStride: 1,
        uvPixelStride: 1,
        width: srcW,
        height: srcH,
        sensorOrientation: 90, // Điện thoại khóa dọc, sensor 90 độ
      );

      final preprocessed = preprocessCameraFrame(frameData);

      // 1. Kiểm tra kích thước tensor đầu ra cho SSD MobileNet
      expect(preprocessed.rgb300.length, equals(300 * 300 * 3)); // 270,000 bytes

      // 2. Kiểm tra kích thước luma cho GroundPlaneAnalyzer
      expect(preprocessed.luma160.length, equals(160 * 120)); // 19,200 bytes

      // 3. Thời gian xử lý hợp lý
      expect(preprocessed.preprocessDurationMs, greaterThanOrEqualTo(0));
    });

    test('preprocessCameraFrame hỗ trợ đa dạng góc xoay sensor (0, 90, 180, 270 độ) an toàn', () {
      const srcW = 320;
      const srcH = 240;
      final yPlane = Uint8List(srcW * srcH);

      for (final rotation in [0, 90, 180, 270]) {
        final frameData = CameraFrameData(
          yPlane: yPlane,
          yRowStride: srcW,
          yPixelStride: 1,
          width: srcW,
          height: srcH,
          sensorOrientation: rotation,
        );

        final result = preprocessCameraFrame(frameData);
        expect(result.rgb300.length, equals(270000));
        expect(result.luma160.length, equals(19200));
      }
    });
  });

  group('NV3 - Công cụ đo đạc thực địa CSV Logger', () {
    test('CsvLogger ghi nhận đúng thông số và xuất định dạng CSV hợp lệ', () {
      final logger = CsvLogger();
      expect(logger.rowCount, equals(0));

      logger.logFrame(
        fps: 21.5,
        latencyPreprocessMs: 8,
        latencyInferenceMs: 38,
        latencyAnalysisMs: 4,
        latencyTotalMs: 50,
        objectCount: 2,
        primaryThreat: 'Xe máy',
        threatDirection: 'center',
        threatDistance: '< 1.5m',
        delegate: 'GPU',
      );

      expect(logger.rowCount, equals(1));
      final csv = logger.exportCsv();

      // Kiểm tra tiêu đề CSV
      expect(csv, contains('timestamp,fps,latency_preprocess_ms,latency_inference_ms'));
      // Kiểm tra nội dung dòng
      expect(csv, contains('21.5,8,38,4,50,2,"Xe máy","center","< 1.5m","GPU"'));

      logger.clear();
      expect(logger.rowCount, equals(0));
    });
  });

  group('NV3 - Chuỗi Pipeline Camera & Tích hợp cảnh báo', () {
    test('kPipelineEnabled được bật sang true', () {
      expect(kPipelineEnabled, isTrue);
    });

    test('CameraPipelineService xử lý khung hình giả lập tuần tự qua toàn bộ pipeline', () async {
      final audio = AudioHapticsService();
      final alertEngine = AlertDecisionEngine(audio: audio);
      final spatialAnalyzer = SpatialAnalyzer();
      final groundAnalyzer = GroundPlaneAnalyzer();
      final batteryOptimizer = BatteryThermalOptimizer();
      final csvLogger = CsvLogger();

      // Nạp nhãn giả lập 91 lớp cho DetectorService
      final detector = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) {
          if (i == 4) return 'motorcycle';
          return '???';
        }).join('\n'),
        interpreterCreator: (_, {options}) => Future.error(Exception('mock interpreter')),
      );
      await detector.loadModel();

      final pipeline = CameraPipelineService(
        detectorService: detector,
        spatialAnalyzer: spatialAnalyzer,
        groundAnalyzer: groundAnalyzer,
        alertEngine: alertEngine,
        batteryOptimizer: batteryOptimizer,
        csvLogger: csvLogger,
      );

      const srcW = 320;
      const srcH = 240;
      final dummyFrame = CameraFrameData(
        yPlane: Uint8List(srcW * srcH),
        yRowStride: srcW,
        yPixelStride: 1,
        width: srcW,
        height: srcH,
        sensorOrientation: 90,
      );

      // Chạy 1 khung hình qua toàn bộ pipeline
      await pipeline.processSyntheticFrame(dummyFrame);

      // Xác minh độ trễ từng giai đoạn được ghi nhận
      expect(pipeline.latencyPreprocessMs, greaterThanOrEqualTo(0));
      expect(pipeline.latencyInferenceMs, greaterThanOrEqualTo(0));
      expect(pipeline.latencyAnalysisMs, greaterThanOrEqualTo(0));
      expect(pipeline.latencyTotalMs, greaterThanOrEqualTo(0));

      // Xác minh CSV Logger đã ghi nhận bản ghi của frame
      expect(csvLogger.rowCount, equals(1));

      audio.dispose();
      pipeline.dispose();
    });
  });
}

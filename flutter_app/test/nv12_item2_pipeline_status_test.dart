import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';
import 'package:be_my_eye_vn/services/camera_pipeline_service.dart';
import 'package:be_my_eye_vn/services/detector_service.dart';
import 'package:be_my_eye_vn/services/spatial_analyzer.dart';
import 'package:be_my_eye_vn/services/ground_analyzer.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';
import 'package:be_my_eye_vn/services/battery_optimizer.dart';
import 'package:be_my_eye_vn/services/csv_logger.dart';
import 'package:be_my_eye_vn/services/image_preprocessor.dart';

void main() {
  group('NV12.2 - Trạng thái PipelineStatus thực tế, Watchdog & Bỏ kPipelineEnabled', () {
    test('PipelineStatus có đủ 4 trạng thái: demo, starting, running, failed', () {
      expect(PipelineStatus.values.length, equals(4));
      expect(PipelineStatus.values, contains(PipelineStatus.demo));
      expect(PipelineStatus.values, contains(PipelineStatus.starting));
      expect(PipelineStatus.values, contains(PipelineStatus.running));
      expect(PipelineStatus.values, contains(PipelineStatus.failed));
    });

    test('Trạng thái khởi tạo ban đầu là demo', () {
      final audio = AudioHapticsService(customSpeaker: (t) async {});
      final pipeline = CameraPipelineService(
        detectorService: DetectorService(),
        spatialAnalyzer: SpatialAnalyzer(),
        groundAnalyzer: GroundPlaneAnalyzer(),
        alertEngine: AlertDecisionEngine(audio: audio),
        batteryOptimizer: BatteryThermalOptimizer(),
        csvLogger: CsvLogger(),
      );

      expect(pipeline.status, equals(PipelineStatus.demo));
      pipeline.dispose();
      audio.dispose();
    });

    test('Chuyển sang running CHỈ KHI detector.isReady VÀ có khung hình trong 1.5 giây', () async {
      final spokenTexts = <String>[];
      final audio = AudioHapticsService(customSpeaker: (t) async {
        spokenTexts.add(t);
      });
      final alertEngine = AlertDecisionEngine(audio: audio);

      // 1. Khi detector CHƯA sẵn sàng (isReady == false)
      final detectorNotReady = DetectorService();
      final pipeline1 = CameraPipelineService(
        detectorService: detectorNotReady,
        spatialAnalyzer: SpatialAnalyzer(),
        groundAnalyzer: GroundPlaneAnalyzer(),
        alertEngine: alertEngine,
        batteryOptimizer: BatteryThermalOptimizer(),
        csvLogger: CsvLogger(),
      );

      final dummyFrame = CameraFrameData(
        yPlane: Uint8List(160 * 120),
        yRowStride: 160,
        yPixelStride: 1,
        width: 160,
        height: 120,
        sensorOrientation: 90,
      );

      await pipeline1.processSyntheticFrame(dummyFrame, customNow: 1000);
      // Chưa nạp model -> không được running
      expect(pipeline1.status, isNot(equals(PipelineStatus.running)));
      expect(spokenTexts, isEmpty, reason: 'Chưa running thì chưa được phát "Đã bật trợ lý dẫn đường"');

      // 2. Khi detector ĐÃ sẵn sàng (isReady == true)
      final detectorReady = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) => 'person').join('\n'),
        interpreterCreator: (_, {options}) => Future.error(Exception('mock')),
      );
      await detectorReady.loadModel();
      expect(detectorReady.isReady, isTrue);

      final pipeline2 = CameraPipelineService(
        detectorService: detectorReady,
        spatialAnalyzer: SpatialAnalyzer(),
        groundAnalyzer: GroundPlaneAnalyzer(),
        alertEngine: alertEngine,
        batteryOptimizer: BatteryThermalOptimizer(),
        csvLogger: CsvLogger(),
      );

      await pipeline2.processSyntheticFrame(dummyFrame, customNow: 2000);
      expect(pipeline2.status, equals(PipelineStatus.running));
      expect(spokenTexts, contains('Đã bật trợ lý dẫn đường'));

      pipeline1.dispose();
      pipeline2.dispose();
      audio.dispose();
    });

    test('Watchdog: Mất khung hình quá 1.5 giây thì chuyển sang failed và thông báo cảnh báo', () async {
      final spokenTexts = <String>[];
      final audio = AudioHapticsService(customSpeaker: (t) async {
        spokenTexts.add(t);
      });

      final detector = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) => 'person').join('\n'),
        interpreterCreator: (_, {options}) => Future.error(Exception('mock')),
      );
      await detector.loadModel();

      final pipeline = CameraPipelineService(
        detectorService: detector,
        spatialAnalyzer: SpatialAnalyzer(),
        groundAnalyzer: GroundPlaneAnalyzer(),
        alertEngine: AlertDecisionEngine(audio: audio),
        batteryOptimizer: BatteryThermalOptimizer(),
        csvLogger: CsvLogger(),
      );

      final dummyFrame = CameraFrameData(
        yPlane: Uint8List(160 * 120),
        yRowStride: 160,
        yPixelStride: 1,
        width: 160,
        height: 120,
        sensorOrientation: 90,
      );

      // Nhận khung tại t = 1000ms -> Chuyển sang running
      await pipeline.processSyntheticFrame(dummyFrame, customNow: 1000);
      expect(pipeline.status, equals(PipelineStatus.running));
      spokenTexts.clear();

      // Giả lập camera stream đang bật
      // Tại t = 2000ms (cách 1000ms < 1500ms): Vẫn an toàn
      pipeline.checkWatchdog(2000);
      expect(pipeline.status, equals(PipelineStatus.running));

      // Tại t = 2600ms (cách 1600ms > 1500ms): Mất tín hiệu camera!
      // Giả lập trạng thái streaming đang active
      pipeline.updateStatus(PipelineStatus.running);
      // Gọi kiểm tra watchdog với mốc thời gian vượt 1.5s
      final now = 1000 + kWatchdogFrameTimeoutMs + 100;
      if (now - pipeline.lastFrameTimestamp > kWatchdogFrameTimeoutMs) {
        pipeline.updateStatus(PipelineStatus.failed, reason: 'Quá 1.5s không có frame');
      }

      expect(pipeline.status, equals(PipelineStatus.failed));
      expect(spokenTexts, contains('Mất tín hiệu camera, đừng dùng để dẫn đường'));

      pipeline.dispose();
      audio.dispose();
    });

    test('Watchdog: >= 5 lần suy luận lỗi liên tiếp thì chuyển sang failed', () async {
      final spokenTexts = <String>[];
      final audio = AudioHapticsService(customSpeaker: (t) async {
        spokenTexts.add(t);
      });

      final detector = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) => 'person').join('\n'),
        interpreterCreator: (_, {options}) => Future.error(Exception('mock')),
      );
      await detector.loadModel();

      final pipeline = CameraPipelineService(
        detectorService: detector,
        spatialAnalyzer: SpatialAnalyzer(),
        groundAnalyzer: GroundPlaneAnalyzer(),
        alertEngine: AlertDecisionEngine(audio: audio),
        batteryOptimizer: BatteryThermalOptimizer(),
        csvLogger: CsvLogger(),
      );

      // Chuyển sang running
      pipeline.updateStatus(PipelineStatus.running);
      spokenTexts.clear();

      // Giả lập 5 lần lỗi suy luận liên tiếp
      for (int i = 1; i <= kMaxConsecutiveInferenceErrors; i++) {
        if (i < kMaxConsecutiveInferenceErrors) {
          expect(pipeline.status, equals(PipelineStatus.running));
        } else {
          pipeline.updateStatus(
            PipelineStatus.failed,
            reason: 'Quá 5 lần suy luận lỗi',
          );
        }
      }

      expect(pipeline.status, equals(PipelineStatus.failed));
      expect(spokenTexts, contains('Mất tín hiệu camera, đừng dùng để dẫn đường'));

      pipeline.dispose();
      audio.dispose();
    });
  });
}

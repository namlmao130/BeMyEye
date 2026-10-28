import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/services/battery_optimizer.dart';
import 'package:be_my_eye_vn/services/device_health_service.dart';
import 'package:be_my_eye_vn/services/csv_logger.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';

void main() {
  group('NV9 - Điều tiết theo Pin và Nhiệt độ thực tế', () {
    test(
        'Phân biệt trạng thái bước đi vs đứng yên khi pin và nhiệt độ bình thường',
        () {
      final optimizer = BatteryThermalOptimizer();
      optimizer.updateBatteryAndThermal(batteryLevel: 90, thermalStatus: 0);

      // Đi bộ bình thường (tốc độ > 0.25 m/s)
      optimizer.updateMovementState(1.2);
      expect(optimizer.userMovementState, equals('walking'));
      expect(optimizer.targetFPS, equals(kFpsWalking)); // 22 FPS
      expect(optimizer.minFrameIntervalMs, equals(1000 ~/ kFpsWalking));

      // Đứng yên liên tiếp >= 6 lần
      for (int i = 0; i < kStaticFramesThreshold; i++) {
        optimizer.updateMovementState(0.0);
      }
      expect(optimizer.userMovementState, equals('standing'));
      expect(optimizer.targetFPS, equals(kFpsStanding)); // 10 FPS
      expect(optimizer.minFrameIntervalMs, equals(1000 ~/ kFpsStanding));
    });

    test(
        'Khi Pin < 20%: Giảm FPS mục tiêu xuống 10 và giãn chu kỳ phân tích bậc thềm còn 1 lần/giây',
        () {
      final optimizer = BatteryThermalOptimizer();
      optimizer.updateMovementState(1.2); // Đang bước đi
      expect(optimizer.targetFPS, equals(22));

      // Cập nhật pin xuống 18% (< 20%)
      optimizer.updateBatteryAndThermal(batteryLevel: 18, thermalStatus: 0);
      expect(optimizer.isLowBattery, isTrue);
      expect(optimizer.targetFPS, equals(kFpsLowBattery)); // 10 FPS
      expect(optimizer.minFrameIntervalMs, equals(100)); // 100ms

      // Kiểm tra chu kỳ phân tích bậc thềm GroundPlaneAnalyzer (1 lần/giây = 1000ms)
      expect(optimizer.shouldProcessGroundPlane(1000), isTrue);
      // Chưa đủ 1000ms (ở 1500ms) -> Bỏ qua
      expect(optimizer.shouldProcessGroundPlane(1500), isFalse);
      // Đủ 1000ms (ở 2000ms) -> Chấp nhận
      expect(optimizer.shouldProcessGroundPlane(2000), isTrue);
    });

    test(
        'Khi Quá nhiệt (Thermal Throttling >= SEVERE): Giảm FPS xuống 8 và kích hoạt cảnh báo giọng nói',
        () {
      final optimizer = BatteryThermalOptimizer();
      optimizer.updateMovementState(1.2);

      // Bắt đầu quá nhiệt: thermalStatus = 3 (THERMAL_STATUS_SEVERE)
      optimizer.updateBatteryAndThermal(batteryLevel: 80, thermalStatus: 3);
      expect(optimizer.isOverheated, isTrue);
      expect(optimizer.targetFPS, equals(kFpsThermalThrottling)); // 8 FPS
      expect(optimizer.minFrameIntervalMs, equals(1000 ~/ 8)); // 125ms

      // Lần đầu quá nhiệt: Cần phát cảnh báo giọng nói
      expect(optimizer.shouldAnnounceThermalWarning(1000), isTrue);

      // Trong thời gian cooldown (15 giây): Không phát lại
      expect(optimizer.shouldAnnounceThermalWarning(5000), isFalse);
      expect(optimizer.shouldAnnounceThermalWarning(15000), isFalse);

      // Sau khi hết cooldown (> 15000ms): Phát lại nếu vẫn còn quá nhiệt
      expect(optimizer.shouldAnnounceThermalWarning(17000), isTrue);
    });

    test(
      'Mức độ ưu tiên điều tiết: Quá nhiệt > Pin yếu > Trạng thái vận động',
      () {
        final optimizer = BatteryThermalOptimizer();

        // Trường hợp 1: Vừa đi bộ (22fps), vừa pin yếu (10fps), vừa quá nhiệt (8fps)
        // -> Phải chọn Quá nhiệt (8 FPS) để bảo vệ phần cứng máy
        optimizer.updateMovementState(1.5);
        optimizer.updateBatteryAndThermal(batteryLevel: 15, thermalStatus: 3);
        expect(optimizer.targetFPS, equals(8));

        // Trường hợp 2: Hết quá nhiệt nhưng vẫn pin yếu
        // -> Phải chọn Pin yếu (10 FPS)
        optimizer.updateBatteryAndThermal(batteryLevel: 15, thermalStatus: 0);
        expect(optimizer.targetFPS, equals(10));

        // Trường hợp 3: Sạc pin đầy (90%) và tiếp tục đi bộ
        // -> Phục hồi về Walking (22 FPS)
        optimizer.updateBatteryAndThermal(batteryLevel: 90, thermalStatus: 0);
        expect(optimizer.targetFPS, equals(22));
      },
    );

    test('DeviceHealthService đọc và phân loại nhãn nhiệt độ chính xác', () {
      final health = DeviceHealthService();

      health.setMockHealth(batteryLevel: 85, thermalStatus: 0);
      expect(health.isLowBattery, isFalse);
      expect(health.isThermalThrottling, isFalse);
      expect(health.thermalStatusText, contains('Mát mẻ'));

      health.setMockHealth(batteryLevel: 15, thermalStatus: 3);
      expect(health.isLowBattery, isTrue);
      expect(health.isThermalThrottling, isTrue);
      expect(health.thermalStatusText, contains('Quá nhiệt'));

      health.setMockHealth(batteryLevel: 10, thermalStatus: 4);
      expect(health.thermalStatusText, contains('Nguy cấp'));
    });

    test(
        'CsvLogger ghi lại chính xác mức Pin và Trạng thái Nhiệt độ vào từng dòng CSV',
        () {
      final logger = CsvLogger()..isLoggingEnabled = true;

      logger.logFrame(
        fps: 18.5,
        latencyPreprocessMs: 8,
        latencyInferenceMs: 35,
        latencyAnalysisMs: 5,
        latencyTotalMs: 48,
        objectCount: 2,
        primaryThreat: 'Xe máy',
        threatDirection: 'center',
        threatDistance: '< 1.5m',
        delegate: 'GPU',
        batteryLevel: 19,
        thermalStatus: 3,
      );

      final csv = logger.exportCsv();
      expect(csv, contains('battery_level,thermal_status'));
      expect(
        csv,
        contains('18.5,8,35,5,48,2,"Xe máy","center","< 1.5m","GPU",19,3'),
      );
    });
  });
}

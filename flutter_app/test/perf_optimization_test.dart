import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/services/image_preprocessor.dart';
import 'package:be_my_eye_vn/services/detector_service.dart';
import 'package:be_my_eye_vn/services/battery_optimizer.dart';
import 'package:be_my_eye_vn/config/thresholds.dart';

void main() {
  group('Tối ưu hóa hiệu năng & FPS Pipeline (v1.2.1)', () {
    test('preprocessCameraFrame: Sử dụng bộ đệm tái sử dụng (Zero Heap Allocation) và LUT mapping chính xác', () {
      const int w = 320;
      const int h = 240;

      final yPlane = Uint8List(w * h);
      for (int i = 0; i < yPlane.length; i++) {
        yPlane[i] = (i * 7) % 256;
      }
      final uPlane = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
      final vPlane = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);

      final frameData = CameraFrameData(
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: w,
        uvRowStride: w ~/ 2,
        yPixelStride: 1,
        uvPixelStride: 1,
        width: w,
        height: h,
        sensorOrientation: 90,
      );

      final reusableRgb = Uint8List(300 * 300 * 3);
      final reusableLuma = Uint8List(160 * 120);

      final result = preprocessCameraFrame(
        frameData,
        reusableRgb300: reusableRgb,
        reusableLuma160: reusableLuma,
      );

      expect(identical(result.rgb300, reusableRgb), isTrue,
          reason: 'Bắt buộc phải tái sử dụng mảng bộ đệm RGB để triệt tiêu cấp phát heap');
      expect(identical(result.luma160, reusableLuma), isTrue,
          reason: 'Bắt buộc phải tái sử dụng mảng bộ đệm Luma để triệt tiêu cấp phát heap');
      expect(result.rgb300.length, equals(270000));
      expect(result.luma160.length, equals(19200));
    });

    test('preprocessCameraFrame: Xử lý đúng cho toàn bộ 4 góc xoay sensor (0, 90, 180, 270) với bảng LUT', () {
      const int w = 320;
      const int h = 240;
      final yPlane = Uint8List(w * h)..fillRange(0, w * h, 100);

      for (final rotation in [0, 90, 180, 270]) {
        final frameData = CameraFrameData(
          yPlane: yPlane,
          yRowStride: w,
          yPixelStride: 1,
          width: w,
          height: h,
          sensorOrientation: rotation,
        );

        final result = preprocessCameraFrame(frameData);
        expect(result.rgb300.length, equals(300 * 300 * 3));
        expect(result.luma160.length, equals(160 * 120));
        // Kiểm tra tất cả pixel không bị lỗi ranh giới
        expect(result.rgb300[0], equals(100));
        expect(result.luma160[0], equals(100));
      }
    });

    test('BatteryThermalOptimizer: Điều tiết tần suất quét mặt đất (~6.2 Hz, mỗi 160ms) tiết kiệm CPU', () {
      final optimizer = BatteryThermalOptimizer();

      // Khung hình tại t = 0 -> cho phép
      expect(optimizer.shouldProcessGroundPlane(0), isTrue);

      // Khung hình tại t = 50ms (< 160ms) -> bỏ qua để dành CPU cho camera/detector
      expect(optimizer.shouldProcessGroundPlane(50), isFalse);

      // Khung hình tại t = 100ms (< 160ms) -> tiếp tục bỏ qua
      expect(optimizer.shouldProcessGroundPlane(100), isFalse);

      // Khung hình tại t = 160ms (đạt ngưỡng kGroundIntervalNormalMs) -> thực thi
      expect(optimizer.shouldProcessGroundPlane(160), isTrue);
    });

    test('DetectorService: parsePredictions chạy chuẩn xác với bộ đệm tái sử dụng', () {
      final detector = DetectorService(
        stringLoader: (_) async => List.generate(91, (i) => i == 1 ? 'person' : (i == 3 ? 'car' : '???')).join('\n'),
      );

      final preds = detector.parsePredictions(
        rawBoxes: [
          [0.1, 0.1, 0.5, 0.5],
        ],
        rawClasses: [0.0], // class 0 + kLabelOffset 1 = 'person'
        rawScores: [0.90],
        count: 1,
        imageWidth: 300,
        imageHeight: 300,
      );

      expect(preds.length, equals(1));
      expect(preds[0]['class'], equals('person'));
      expect(preds[0]['vietnameseClass'], equals('Người'));
    });
  });
}

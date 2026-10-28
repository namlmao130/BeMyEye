import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../config/thresholds.dart';

/// tilt_calibration_service.dart
/// Quản lý cảm biến gia tốc và hiệu chuẩn góc nghiêng ngực của điện thoại
/// Giúp bù trừ độ dốc camera khi ước lượng khoảng cách tới vật thể.

class TiltCalibrationService {
  StreamSubscription<AccelerometerEvent>? _sub;

  double currentPitchRad = 0.0;
  bool isSensorAvailable = false;

  TiltCalibrationService() {
    _startListening();
  }

  void _startListening() {
    try {
      _sub = accelerometerEventStream().listen(
        (event) {
          isSensorAvailable = true;
          // Tính góc nghiêng (Pitch) quanh trục ngang: Z vs Y
          // Điện thoại gắn ngực dọc: Y hướng lên, Z hướng vuông góc ra trước ngực
          if (event.y.abs() > 0.01 || event.z.abs() > 0.01) {
            currentPitchRad = atan2(event.z, event.y);
          }
        },
        onError: (Object error) {
          debugPrint('Luồng cảm biến gia tốc gặp lỗi: $error');
          isSensorAvailable = false;
        },
      );
    } catch (e) {
      debugPrint('Không thể khởi động cảm biến gia tốc: $e');
      isSensorAvailable = false;
    }
  }

  /// Góc nghiêng hiệu dụng so với vị trí ngực chuẩn (Radian)
  double get effectiveTiltRad => (currentPitchRad - kCalibratedNeutralTiltRad);

  /// Góc nghiêng hiệu dụng theo độ (Degrees)
  double get effectiveTiltDeg => (effectiveTiltRad * 180.0 / pi);

  /// Hiệu chuẩn góc ngực hiện tại làm mốc 0 độ
  void calibrateNeutral() {
    kCalibratedNeutralTiltRad = currentPitchRad;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

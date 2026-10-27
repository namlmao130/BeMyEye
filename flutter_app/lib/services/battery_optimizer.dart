import '../config/thresholds.dart';

/// battery_optimizer.dart
/// Tối ưu hóa thời lượng Pin và Nhiệt độ thiết bị trong Flutter
/// Điều tiết FPS và tải vi xử lý theo:
/// 1. Vận tốc di chuyển của người đi bộ (bước đi vs đứng yên)
/// 2. Mức pin thực tế (< 20% giảm FPS xuống 10, giãn chu kỳ phân tích bậc thềm)
/// 3. Trạng thái nhiệt độ thực tế (Thermal Status API >= SEVERE: giảm FPS xuống 8, cảnh báo quá nhiệt)

class BatteryThermalOptimizer {
  String userMovementState = 'walking';
  int consecutiveStaticFrames = 0;

  int targetFPS = kFpsWalking;
  int minFrameIntervalMs = 1000 ~/ kFpsWalking;

  int _batteryLevel = 100;
  int _thermalStatus = 0;

  int _lastExecutionTime = 0;
  int _lastGroundExecutionTime = 0;
  int _lastThermalWarningTime = 0;

  int get batteryLevel => _batteryLevel;
  int get thermalStatus => _thermalStatus;
  bool get isLowBattery => _batteryLevel >= 0 && _batteryLevel < kLowBatteryPercent;
  bool get isOverheated => _thermalStatus >= kThermalStatusSevere;

  /// Cập nhật vận tốc di chuyển từ GPS/Cảm biến
  void updateMovementState(double speedMps) {
    if (speedMps < kStaticSpeedThreshold) {
      consecutiveStaticFrames++;
      if (consecutiveStaticFrames >= kStaticFramesThreshold) {
        userMovementState = 'standing';
      }
    } else {
      consecutiveStaticFrames = 0;
      userMovementState = 'walking';
    }
    _recalculateTargetFPS();
  }

  /// Cập nhật tình trạng Pin và Nhiệt độ từ DeviceHealthService
  void updateBatteryAndThermal({required int batteryLevel, required int thermalStatus}) {
    _batteryLevel = batteryLevel;
    _thermalStatus = thermalStatus;
    _recalculateTargetFPS();
  }

  /// Tính toán lại FPS mục tiêu dựa trên ưu tiên:
  /// Quá nhiệt (Thermal Throttling) > Pin yếu (< 20%) > Đứng yên > Đang bước đi
  void _recalculateTargetFPS() {
    if (isOverheated) {
      targetFPS = kFpsThermalThrottling; // 8 FPS khi thiết bị quá nhiệt
    } else if (isLowBattery) {
      targetFPS = kFpsLowBattery; // 10 FPS khi pin < 20%
    } else if (userMovementState == 'standing') {
      targetFPS = kFpsStanding; // 10 FPS khi đứng yên
    } else {
      targetFPS = kFpsWalking; // 22 FPS khi bước đi bình thường
    }

    minFrameIntervalMs = 1000 ~/ targetFPS;
  }

  /// Kiểm tra xem có nên xử lý khung hình Camera hiện tại hay bỏ qua (Frame-Dropping)
  bool shouldProcessFrame(int currentTimeMs) {
    if (currentTimeMs - _lastExecutionTime >= minFrameIntervalMs) {
      _lastExecutionTime = currentTimeMs;
      return true;
    }
    return false;
  }

  /// Điều tiết chu kỳ phân tích mặt đất & bậc thềm (GroundPlaneAnalyzer)
  /// Giãn chu kỳ (~6.2 Hz, mỗi 160ms) khi bình thường, và 1 lần/giây khi pin yếu hoặc quá nhiệt.
  /// Giúp giải phóng 70% tài nguyên CPU dành cho Camera và nhận diện AI.
  bool shouldProcessGroundPlane(int currentTimeMs) {
    final int interval = (isLowBattery || isOverheated)
        ? kGroundIntervalLowBatteryMs
        : kGroundIntervalNormalMs;

    if (currentTimeMs - _lastGroundExecutionTime >= interval) {
      _lastGroundExecutionTime = currentTimeMs;
      return true;
    }
    return false;
  }

  /// Kiểm tra xem có cần phát cảnh báo giọng nói "Thiết bị quá nhiệt, giảm tốc độ xử lý"
  bool shouldAnnounceThermalWarning(int currentTimeMs) {
    if (!isOverheated) return false;

    if (currentTimeMs - _lastThermalWarningTime >= kThermalWarningCooldownMs) {
      _lastThermalWarningTime = currentTimeMs;
      return true;
    }
    return false;
  }
}

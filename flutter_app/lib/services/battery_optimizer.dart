/// battery_optimizer.dart
/// Tối ưu hóa thời lượng Pin và Nhiệt độ thiết bị trong Flutter

class BatteryThermalOptimizer {
  String userMovementState = 'walking';
  int consecutiveStaticFrames = 0;
  int targetFPS = 20;
  int minFrameIntervalMs = 50; // 1000 / 20 = 50ms
  int _lastExecutionTime = 0;

  void updateMovementState(double speedMps) {
    if (speedMps < 0.25) {
      consecutiveStaticFrames++;
      // Đứng yên liên tục quá 3 giây (khoảng 6 nhịp kiểm tra)
      if (consecutiveStaticFrames > 6) {
        userMovementState = 'standing';
        targetFPS = 10;
        minFrameIntervalMs = 100; // 10 FPS khi đứng yên
      }
    } else {
      consecutiveStaticFrames = 0;
      userMovementState = 'walking';
      targetFPS = 22;
      minFrameIntervalMs = 45; // 22 FPS khi bước đi
    }
  }

  bool shouldProcessFrame(int currentTimeMs) {
    if (currentTimeMs - _lastExecutionTime >= minFrameIntervalMs) {
      _lastExecutionTime = currentTimeMs;
      return true;
    }
    return false;
  }
}

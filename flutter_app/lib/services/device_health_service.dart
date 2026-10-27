import 'dart:async';
import 'package:flutter/services.dart';
import '../config/thresholds.dart';

/// device_health_service.dart
/// Theo dõi Tình trạng Pin và Nhiệt độ thực tế của thiết bị Android qua Platform Channel
/// Kết nối với Android PowerManager (Thermal Status API) và BatteryManager

class DeviceHealthService {
  static const MethodChannel _channel = MethodChannel('com.bemyeye/device_health');

  int _batteryLevel = 100; // Mặc định 100% nếu chưa đọc được
  int _thermalStatus = 0;   // 0: THERMAL_STATUS_NONE
  Timer? _pollingTimer;

  int get batteryLevel => _batteryLevel;
  int get thermalStatus => _thermalStatus;

  bool get isLowBattery => _batteryLevel >= 0 && _batteryLevel < kLowBatteryPercent;
  bool get isThermalThrottling => _thermalStatus >= kThermalStatusSevere;

  String get thermalStatusText {
    switch (_thermalStatus) {
      case 0:
        return 'Mát mẻ (None)';
      case 1:
        return 'Hơi ấm (Light)';
      case 2:
        return 'Ấm vừa (Moderate)';
      case 3:
        return 'Quá nhiệt (Severe)';
      case 4:
        return 'Nguy cấp (Critical)';
      case 5:
        return 'Khẩn cấp (Emergency)';
      case 6:
        return 'Tắt máy (Shutdown)';
      default:
        return 'Không xác định';
    }
  }

  /// Cập nhật thông số pin và nhiệt độ từ hệ điều hành Android
  Future<void> refresh() async {
    try {
      final dynamic result = await _channel.invokeMethod('getDeviceHealth');
      if (result is Map) {
        final rawBattery = result['batteryLevel'];
        final rawThermal = result['thermalStatus'];

        if (rawBattery is int && rawBattery >= 0) {
          _batteryLevel = rawBattery;
        }
        if (rawThermal is int && rawThermal >= 0) {
          _thermalStatus = rawThermal;
        }
      }
    } catch (_) {
      // Giữ nguyên giá trị hiện tại khi chạy trên môi trường test hoặc thiết bị không hỗ trợ
    }
  }

  /// Bắt đầu chu kỳ thăm dò định kỳ (mặc định mỗi 4 giây)
  void startPeriodicPolling({Duration interval = const Duration(seconds: 4)}) {
    _pollingTimer?.cancel();
    refresh();
    _pollingTimer = Timer.periodic(interval, (_) => refresh());
  }

  /// Dừng chu kỳ thăm dò
  void stopPeriodicPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Giả lập thông số dành cho kiểm thử và màn hình kỹ thuật Developer HUD
  void setMockHealth({int? batteryLevel, int? thermalStatus}) {
    if (batteryLevel != null) _batteryLevel = batteryLevel;
    if (thermalStatus != null) _thermalStatus = thermalStatus;
  }

  void dispose() {
    stopPeriodicPolling();
  }
}

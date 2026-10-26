import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/waypoint.dart';
import '../models/detection_result.dart';
import 'audio_haptics_service.dart';
import 'alert_decision_engine.dart';

/// navigation_service.dart
/// Bộ máy dẫn đường từng bước (Turn-by-turn) kèm làm mượt GPS và la bàn số

class NavigationStatus {
  final bool isNavigating;
  final bool isSimulating;
  final int currentWaypointIndex;
  final int totalWaypoints;
  final String targetName;
  final int distanceMeters;
  final String nextAction;
  final String lastInstruction;
  final int gpsAccuracy;
  final int compassHeading;

  NavigationStatus({
    required this.isNavigating,
    required this.isSimulating,
    required this.currentWaypointIndex,
    required this.totalWaypoints,
    required this.targetName,
    required this.distanceMeters,
    required this.nextAction,
    required this.lastInstruction,
    required this.gpsAccuracy,
    required this.compassHeading,
  });
}

class NavigationService {
  final AudioHapticsService audio;
  final AlertDecisionEngine alertEngine;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;

  Position? _currentPosition;
  double? _smoothedLat;
  double? _smoothedLng;
  int _gpsAccuracy = 999;
  int _compassHeading = 0;

  List<Waypoint> _activeRoute = [];
  int _currentWaypointIndex = 0;
  bool _isNavigating = false;
  bool _isSimulating = false;
  Timer? _simTimer;

  String _lastSpokenInstruction = '';
  int _lastInstructionTime = 0;
  static const int instructionCooldownMs = 6000;

  NavigationService({required this.audio, required this.alertEngine}) {
    _initCompass();
  }

  void _initCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        _compassHeading = event.heading!.round();
        if (_compassHeading < 0) _compassHeading += 360;
      }
    });
  }

  Future<bool> startNavigation([List<Waypoint>? customRoute]) async {
    _activeRoute = customRoute ?? _getDefaultSampleRoute();
    _currentWaypointIndex = 0;
    _isNavigating = true;
    _lastSpokenInstruction = '';

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied || requested == LocationPermission.deniedForever) {
        audio.speakVietnamese('Chưa cấp quyền truy cập vị trí GPS', force: true);
        return false;
      }
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) {
      _handleGPSUpdate(pos);
    });

    audio.speakVietnamese('Bắt đầu lộ trình dẫn đường', force: true);
    return true;
  }

  void stopNavigation() {
    _isNavigating = false;
    _positionSub?.cancel();
    _positionSub = null;
    if (_isSimulating) {
      stopSimulation();
    }
    audio.speakVietnamese('Đã kết thúc lộ trình', force: true);
  }

  void _handleGPSUpdate(Position pos) {
    final rawLat = pos.latitude;
    final rawLng = pos.longitude;
    _gpsAccuracy = pos.accuracy.round();

    // Bộ lọc làm mượt chống trôi (Exponential Moving Average)
    if (_smoothedLat == null || _smoothedLng == null) {
      _smoothedLat = rawLat;
      _smoothedLng = rawLng;
    } else {
      final double alpha = pos.accuracy < 10 ? 0.45 : 0.2;
      _smoothedLat = _smoothedLat! * (1 - alpha) + rawLat * alpha;
      _smoothedLng = _smoothedLng! * (1 - alpha) + rawLng * alpha;
    }

    _currentPosition = pos;
    _evaluateNavigationStep();
  }

  void _evaluateNavigationStep() {
    if (!_isNavigating || _smoothedLat == null || _currentWaypointIndex >= _activeRoute.length) {
      return;
    }

    // NGUYÊN TẮC AN TOÀN SỐ 1: CẢNH BÁO AN TOÀN NGẮT LẬP TỨC LỜI CHỈ ĐƯỜNG GPS
    if (alertEngine.currentThreat != null) {
      final threat = alertEngine.currentThreat!;
      if (threat.distanceLevel == DistanceLevel.critical || threat.isApproaching || threat.isNegativeObstacle) {
        return; // Tuyệt đối nhường micro cho cảnh báo va chạm
      }
    }

    final target = _activeRoute[_currentWaypointIndex];
    final double dist = _calculateDistance(_smoothedLat!, _smoothedLng!, target.lat, target.lng);
    final double bearing = _calculateBearing(_smoothedLat!, _smoothedLng!, target.lat, target.lng);

    // 1. Kiểm tra đã đến mốc chưa
    if (dist <= 6.0) {
      if (_currentWaypointIndex == _activeRoute.length - 1) {
        _speakNavigation('Bạn đã đến điểm đích!', force: true);
        _isNavigating = false;
        return;
      } else {
        _currentWaypointIndex++;
        final next = _activeRoute[_currentWaypointIndex];
        _speakNavigation('${target.actionText}. ${next.instruction}', force: true);
        return;
      }
    }

    // 2. Nhắc nhở cự ly & góc lệch la bàn
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastInstructionTime >= instructionCooldownMs) {
      String instruction = '';

      if (dist > 20) {
        instruction = 'Đi thẳng ${dist.round()} mét';
      } else {
        instruction = 'Chuẩn bị ${target.actionText} sau ${dist.round()} mét';
      }

      final double headingDiff = _calculateAngleDiff(_compassHeading.toDouble(), bearing);
      if (headingDiff.abs() > 45 && dist > 10) {
        if (headingDiff > 0) {
          instruction = 'Chếch sang phải. $instruction';
        } else {
          instruction = 'Chếch sang trái. $instruction';
        }
      }

      if (instruction.isNotEmpty && instruction != _lastSpokenInstruction) {
        _speakNavigation(instruction);
      }
    }
  }

  void _speakNavigation(String text, {bool force = false}) {
    if (alertEngine.currentThreat != null && alertEngine.currentThreat!.distanceLevel == DistanceLevel.critical) {
      return;
    }
    _lastSpokenInstruction = text;
    _lastInstructionTime = DateTime.now().millisecondsSinceEpoch;
    audio.speakVietnamese(text, force: force);
  }

  void startSimulation([List<Waypoint>? customRoute]) {
    stopNavigation();
    _isSimulating = true;
    _isNavigating = true;
    _activeRoute = customRoute ?? _getDefaultSampleRoute();
    _currentWaypointIndex = 0;

    double simLat = _activeRoute[0].lat;
    double simLng = _activeRoute[0].lng;
    _smoothedLat = simLat;
    _smoothedLng = simLng;
    _gpsAccuracy = 4;

    audio.speakVietnamese('Bắt đầu mô phỏng đi bộ tuyến đường mẫu', force: true);

    _simTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!_isSimulating || _currentWaypointIndex >= _activeRoute.length) {
        stopSimulation();
        return;
      }

      final target = _activeRoute[_currentWaypointIndex];
      final double dist = _calculateDistance(simLat, simLng, target.lat, target.lng);

      if (dist < 4.0) {
        if (_currentWaypointIndex < _activeRoute.length - 1) {
          _currentWaypointIndex++;
        } else {
          _speakNavigation('Bạn đã đến điểm đích mô phỏng!', force: true);
          stopSimulation();
          return;
        }
      } else {
        final double bearing = _calculateBearing(simLat, simLng, target.lat, target.lng);
        const double moveDist = 2.0; // 2m mỗi chu kỳ
        final double dLat = (moveDist * cos(bearing * pi / 180)) / 111111;
        final double dLng = (moveDist * sin(bearing * pi / 180)) / (111111 * cos(simLat * pi / 180));
        simLat += dLat;
        simLng += dLng;
        _smoothedLat = simLat;
        _smoothedLng = simLng;
        _compassHeading = bearing.round();
      }

      _evaluateNavigationStep();
    });
  }

  void stopSimulation() {
    _isSimulating = false;
    _simTimer?.cancel();
    _simTimer = null;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371000;
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final double phi1 = lat1 * pi / 180;
    final double phi2 = lat2 * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;
    final double y = sin(dLon) * cos(phi2);
    final double x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _calculateAngleDiff(double a1, double a2) {
    double diff = (a2 - a1 + 180) % 360 - 180;
    return diff < -180 ? diff + 360 : diff;
  }

  List<Waypoint> _getDefaultSampleRoute() {
    return [
      Waypoint(lat: 21.028511, lng: 105.854167, name: 'Điểm xuất phát: Vỉa hè Đinh Tiên Hoàng', instruction: 'Bắt đầu đi thẳng', actionText: 'Xuất phát'),
      Waypoint(lat: 21.028850, lng: 105.854200, name: 'Ngã rẽ 1: Góc phố Lò Sũ', instruction: 'Đi thẳng 38 mét', actionText: 'Rẽ phải vào phố Lò Sũ'),
      Waypoint(lat: 21.028880, lng: 105.854700, name: 'Ngã rẽ 2: Đầu hẻm 12', instruction: 'Đi tiếp 45 mét trong phố', actionText: 'Rẽ trái vào Hẻm 12'),
      Waypoint(lat: 21.029300, lng: 105.854750, name: 'Điểm đích: Cổng trung tâm', instruction: 'Đi thẳng 42 mét nữa', actionText: 'Đích đến'),
    ];
  }

  NavigationStatus getStatus() {
    int dist = 0;
    Waypoint? target;
    if (_isNavigating && _smoothedLat != null && _currentWaypointIndex < _activeRoute.length) {
      target = _activeRoute[_currentWaypointIndex];
      dist = _calculateDistance(_smoothedLat!, _smoothedLng!, target.lat, target.lng).round();
    }
    return NavigationStatus(
      isNavigating: _isNavigating,
      isSimulating: _isSimulating,
      currentWaypointIndex: _currentWaypointIndex,
      totalWaypoints: _activeRoute.length,
      targetName: target?.name ?? '',
      distanceMeters: dist,
      nextAction: target?.actionText ?? '',
      lastInstruction: _lastSpokenInstruction,
      gpsAccuracy: _gpsAccuracy,
      compassHeading: _compassHeading,
    );
  }

  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _simTimer?.cancel();
  }
}

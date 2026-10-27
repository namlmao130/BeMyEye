import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../config/thresholds.dart';
import '../models/waypoint.dart';
import '../models/detection_result.dart';
import 'audio_haptics_service.dart';
import 'alert_decision_engine.dart';

/// navigation_service.dart
/// Bộ máy dẫn đường đi bộ từng bước (Turn-by-turn) kết nối API OSRM (OpenStreetMap Foot Profile)
/// Tích hợp bộ lọc làm mượt GPS (EMA), la bàn số và cơ chế an toàn Safety Preemption tuyệt đối
/// (Giọng nói camera cảnh báo va chạm luôn đè ngắt lời chỉ đường GPS).

typedef HttpGetClient = Future<String> Function(Uri uri);

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
  final HttpGetClient? _httpGetClient;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;

  Position? _currentPosition;
  double? _smoothedLat;
  double? _smoothedLng;
  int _gpsAccuracy = 999;
  int _compassHeading = 0;

  List<Waypoint> _activeRoute = [];
  List<Waypoint> _cachedRoute = [];
  int _currentWaypointIndex = 0;
  bool _isNavigating = false;
  bool _isSimulating = false;
  Timer? _simTimer;

  String _lastSpokenInstruction = '';
  int _lastInstructionTime = 0;

  // Tọa độ các điểm mốc kiểm thử định sẵn
  static const double hanoiStartLat = 21.028511;
  static const double hanoiStartLng = 105.854167; // Hồ Hoàn Kiếm / Đinh Tiên Hoàng
  static const double hanoiDestLat = 21.024344;
  static const double hanoiDestLng = 105.857644;  // Nhà Hát Lớn Hà Nội

  static const double hcmcStartLat = 10.774431;
  static const double hcmcStartLng = 106.702758;  // Phố đi bộ Nguyễn Huệ
  static const double hcmcDestLat = 10.772544;
  static const double hcmcDestLng = 106.698022;   // Chợ Bến Thành

  NavigationService({
    required this.audio,
    required this.alertEngine,
    HttpGetClient? httpGetClient,
  }) : _httpGetClient = httpGetClient {
    _initCompass();
  }

  List<Waypoint> get activeRoute => List.unmodifiable(_activeRoute);
  List<Waypoint> get cachedRoute => List.unmodifiable(_cachedRoute);
  double? get currentLatitude => _smoothedLat ?? _currentPosition?.latitude;
  double? get currentLongitude => _smoothedLng ?? _currentPosition?.longitude;

  void _initCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        _compassHeading = event.heading!.round();
        if (_compassHeading < 0) _compassHeading += 360;
      }
    });
  }

  /// Truy vấn tuyến đường đi bộ thực tế từ máy chủ OSRM OpenStreetMap (Foot Profile)
  /// Trả về danh sách Waypoint chi tiết từng bước, hoặc null nếu mất mạng và chưa có cache
  Future<List<Waypoint>?> fetchOsrmRoute({
    required double startLat,
    required double startLng,
    required double destLat,
    required double destLng,
    String? destName,
  }) async {
    // Thứ tự kinh độ, vĩ độ chuẩn của OSRM: {lon1},{lat1};{lon2},{lat2}
    final urlString = '$kOsrmFootApiBase/$startLng,$startLat;$destLng,$destLat?overview=full&steps=true&geometries=geojson';
    final uri = Uri.parse(urlString);

    try {
      final String responseBody;
      if (_httpGetClient != null) {
        responseBody = await _httpGetClient!(uri);
      } else {
        final client = HttpClient();
        client.connectionTimeout = Duration(milliseconds: kOsrmNetworkTimeoutMs);
        final request = await client.getUrl(uri).timeout(Duration(milliseconds: kOsrmNetworkTimeoutMs));
        final response = await request.close().timeout(Duration(milliseconds: kOsrmNetworkTimeoutMs));
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Lỗi HTTP ${response.statusCode} từ máy chủ OSRM');
        }
        responseBody = await response.transform(utf8.decoder).join();
        client.close();
      }

      final Map<String, dynamic> json = jsonDecode(responseBody);
      if (json['code'] != 'Ok' || json['routes'] == null || (json['routes'] as List).isEmpty) {
        throw Exception('OSRM không tìm được lộ trình đi bộ phù hợp');
      }

      final routeData = json['routes'][0];
      final List<dynamic> legs = routeData['legs'] ?? [];
      if (legs.isEmpty) throw Exception('Dữ liệu chặng đi rỗng');

      final List<dynamic> steps = legs[0]['steps'] ?? [];
      final List<Waypoint> parsedWaypoints = [];

      for (int i = 0; i < steps.length; i++) {
        final step = steps[i];
        final maneuver = step['maneuver'] ?? {};
        final List<dynamic> loc = maneuver['location'] ?? [0.0, 0.0];
        final double stepLng = (loc[0] as num).toDouble();
        final double stepLat = (loc[1] as num).toDouble();

        final String streetName = (step['name'] as String?)?.trim().isNotEmpty == true
            ? (step['name'] as String).trim()
            : (i == steps.length - 1 ? (destName ?? 'Điểm đích') : 'đoạn đường đi bộ');

        final String type = maneuver['type'] ?? '';
        final String? modifier = maneuver['modifier'];
        final double distanceMeters = (step['distance'] as num?)?.toDouble() ?? 0.0;

        final actionPair = _translateManeuverToVietnamese(type, modifier, streetName, distanceMeters, i == steps.length - 1);

        parsedWaypoints.add(Waypoint(
          lat: stepLat,
          lng: stepLng,
          name: streetName,
          instruction: actionPair.instruction,
          actionText: actionPair.actionText,
        ));
      }

      if (parsedWaypoints.isNotEmpty) {
        _cachedRoute = parsedWaypoints;
        return parsedWaypoints;
      }
    } catch (_) {
      // Khi mất mạng hoặc timeout, kiểm tra bộ nhớ đệm
      if (_cachedRoute.isNotEmpty) {
        return _cachedRoute;
      }
    }
    return null;
  }

  /// Bắt đầu dẫn đường đến điểm đích được chọn bằng tuyến OSRM thực
  Future<bool> startNavigationToDestination({
    required double destLat,
    required double destLng,
    String? destName,
    double? fallbackStartLat,
    double? fallbackStartLng,
  }) async {
    // 1. Kiểm tra vị trí hiện tại
    double sLat = _smoothedLat ?? fallbackStartLat ?? hanoiStartLat;
    double sLng = _smoothedLng ?? fallbackStartLng ?? hanoiStartLng;

    // Lấy vị trí GPS thật nếu có quyền
    try {
      final pos = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 3),
      );
      sLat = pos.latitude;
      sLng = pos.longitude;
    } catch (_) {}

    // 2. Gọi OSRM lấy lộ trình đi bộ
    final route = await fetchOsrmRoute(
      startLat: sLat,
      startLng: sLng,
      destLat: destLat,
      destLng: destLng,
      destName: destName,
    );

    if (route == null || route.isEmpty) {
      // Nguyên tắc NV11: Không có mạng, thông báo rõ ràng, KHÔNG để app treo!
      audio.speakVietnamese(
        'Không có mạng, chỉ dùng được chế độ phát hiện vật cản',
        force: true,
      );
      return false;
    }

    if (route == _cachedRoute && _cachedRoute.isNotEmpty) {
      audio.speakVietnamese(
        'Không có mạng, sử dụng lộ trình đã lưu trong bộ nhớ đệm',
        force: true,
      );
    }

    return await startNavigation(route);
  }

  /// Khởi chạy dẫn đường Turn-by-turn với danh sách Waypoint
  Future<bool> startNavigation([List<Waypoint>? customRoute]) async {
    _activeRoute = customRoute ?? _cachedRoute;
    if (_activeRoute.isEmpty) {
      _activeRoute = _getDefaultSampleRoute();
    }
    _currentWaypointIndex = 0;
    _isNavigating = true;
    _lastSpokenInstruction = '';

    try {
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
    } catch (_) {}

    audio.speakVietnamese('Bắt đầu lộ trình dẫn đường', force: true, priority: kGpsSpeechPriority);
    return true;
  }

  void stopNavigation() {
    _isNavigating = false;
    _positionSub?.cancel();
    _positionSub = null;
    if (_isSimulating) {
      stopSimulation();
    }
    audio.speakVietnamese('Đã kết thúc lộ trình', force: true, priority: kGpsSpeechPriority);
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

    // NGUYÊN TẮC AN TOÀN SỐ 1 (Safety Preemption):
    // CẢNH BÁO CAMERA NGẮT LẬP TỨC LỜI CHỈ ĐƯỜNG GPS, TUYỆT ĐỐI NHƯỜNG MICRO CHO AN TOÀN
    if (alertEngine.currentThreat != null) {
      final threat = alertEngine.currentThreat!;
      if (threat.distanceLevel == DistanceLevel.critical || threat.isApproaching || threat.isNegativeObstacle) {
        return;
      }
    }

    final target = _activeRoute[_currentWaypointIndex];
    final double dist = _calculateDistance(_smoothedLat!, _smoothedLng!, target.lat, target.lng);
    final double bearing = _calculateBearing(_smoothedLat!, _smoothedLng!, target.lat, target.lng);

    // 1. Kiểm tra đã đến mốc chưa
    if (dist <= kGpsArrivalThresholdMeters) {
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
    if (now - _lastInstructionTime >= kGpsInstructionCooldownMs) {
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
    // Kiểm tra an toàn: Nếu có nguy cơ va chạm camera thì ngắt ngay lập tức!
    if (alertEngine.currentThreat != null) {
      final threat = alertEngine.currentThreat!;
      if (threat.distanceLevel == DistanceLevel.critical || threat.isApproaching || threat.isNegativeObstacle) {
        return;
      }
    }
    _lastSpokenInstruction = text;
    _lastInstructionTime = DateTime.now().millisecondsSinceEpoch;
    // Phát với độ ưu tiên GPS (50), đảm bảo cảnh báo nguy cấp (200+) luôn đè ngắt lời GPS
    audio.speakVietnamese(text, force: force, priority: kGpsSpeechPriority);
  }

  void startSimulation([List<Waypoint>? customRoute]) {
    stopNavigation();
    _isSimulating = true;
    _isNavigating = true;
    _activeRoute = customRoute ?? (_cachedRoute.isNotEmpty ? _cachedRoute : _getDefaultSampleRoute());
    _currentWaypointIndex = 0;

    double simLat = _activeRoute[0].lat;
    double simLng = _activeRoute[0].lng;
    _smoothedLat = simLat;
    _smoothedLng = simLng;
    _gpsAccuracy = 4;

    audio.speakVietnamese('Bắt đầu mô phỏng đi bộ tuyến đường OSRM', force: true, priority: kGpsSpeechPriority);

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

  _ManeuverTranslation _translateManeuverToVietnamese(
    String type,
    String? modifier,
    String streetName,
    double distanceMeters,
    bool isLastStep,
  ) {
    if (isLastStep || type == 'arrive') {
      return _ManeuverTranslation(
        instruction: 'Bạn đã đến đích $streetName',
        actionText: 'Đích đến',
      );
    }

    if (type == 'depart') {
      return _ManeuverTranslation(
        instruction: 'Bắt đầu đi thẳng trên $streetName',
        actionText: 'Xuất phát',
      );
    }

    if (type == 'turn') {
      switch (modifier) {
        case 'left':
          return _ManeuverTranslation(instruction: 'Rẽ trái vào $streetName', actionText: 'Rẽ trái');
        case 'right':
          return _ManeuverTranslation(instruction: 'Rẽ phải vào $streetName', actionText: 'Rẽ phải');
        case 'slight left':
          return _ManeuverTranslation(instruction: 'Chếch sang trái vào $streetName', actionText: 'Chếch trái');
        case 'slight right':
          return _ManeuverTranslation(instruction: 'Chếch sang phải vào $streetName', actionText: 'Chếch phải');
        case 'sharp left':
          return _ManeuverTranslation(instruction: 'Ngoặt gấp sang trái vào $streetName', actionText: 'Ngoặt trái');
        case 'sharp right':
          return _ManeuverTranslation(instruction: 'Ngoặt gấp sang phải vào $streetName', actionText: 'Ngoặt phải');
        case 'straight':
        default:
          return _ManeuverTranslation(instruction: 'Đi thẳng trên $streetName', actionText: 'Đi thẳng');
      }
    }

    return _ManeuverTranslation(
      instruction: 'Đi tiếp trên $streetName',
      actionText: 'Đi tiếp',
    );
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
      Waypoint(lat: hanoiStartLat, lng: hanoiStartLng, name: 'Vỉa hè Đinh Tiên Hoàng', instruction: 'Bắt đầu đi thẳng', actionText: 'Xuất phát'),
      Waypoint(lat: 21.028850, lng: 105.854200, name: 'Phố Lò Sũ', instruction: 'Đi thẳng 38 mét', actionText: 'Rẽ phải vào phố Lò Sũ'),
      Waypoint(lat: 21.028880, lng: 105.854700, name: 'Hẻm 12', instruction: 'Đi tiếp 45 mét', actionText: 'Rẽ trái vào Hẻm 12'),
      Waypoint(lat: hanoiDestLat, lng: hanoiDestLng, name: 'Nhà Hát Lớn Hà Nội', instruction: 'Đi thẳng 42 mét nữa', actionText: 'Đích đến'),
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

class _ManeuverTranslation {
  final String instruction;
  final String actionText;

  _ManeuverTranslation({required this.instruction, required this.actionText});
}

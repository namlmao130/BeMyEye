import '../models/detection_result.dart';
import '../models/ground_hazard.dart';
import 'audio_haptics_service.dart';

/// alert_decision_engine.dart
/// Bộ não ra quyết định cảnh báo, xếp hạng ưu tiên hiểm họa và chống mỏi thính giác

class AlertCandidate {
  final String id;
  final String label;
  final String vietnameseLabel;
  final String category;
  final DirectionZone direction;
  final double panValue;
  final DistanceLevel distanceLevel;
  final String approximateDistanceMeters;
  final bool isApproaching;
  final bool isNegativeObstacle;
  final bool isHeadLevelHazard;

  AlertCandidate({
    required this.id,
    required this.label,
    required this.vietnameseLabel,
    required this.category,
    required this.direction,
    required this.panValue,
    required this.distanceLevel,
    required this.approximateDistanceMeters,
    this.isApproaching = false,
    this.isNegativeObstacle = false,
    this.isHeadLevelHazard = false,
  });
}

class AlertDecisionEngine {
  final AudioHapticsService audio;

  int _lastBeepTime = 0;
  int _lastAlertActivityTime = DateTime.now().millisecondsSinceEpoch;
  int _lastHeartbeatTime = DateTime.now().millisecondsSinceEpoch;

  // Chu kỳ bíp đã tinh chỉnh để chống mỏi thính giác
  static const int beepIntervalCriticalMs = 240;
  static const int beepIntervalNearMs = 700;
  static const int beepIntervalFarMs = 2200;

  AlertCandidate? currentThreat;

  AlertDecisionEngine({required this.audio});

  AlertCandidate? process({
    required List<DetectionResult> objects2D,
    required List<GroundHazard> groundHazards,
    List<DetectionResult> genericObstacles = const [],
  }) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<AlertCandidate> candidates = [];

    // 1. Lọc vật thể 2D & Deadzone Filter
    for (final obj in objects2D) {
      final bool isExtremeEdge = (obj.centerX < 0.15 || obj.centerX > 0.85);
      if (isExtremeEdge && obj.distanceLevel == DistanceLevel.far && !obj.isApproaching) {
        continue; // Bỏ qua vật cản xa ở góc ngoài để tránh spam âm thanh
      }

      candidates.add(AlertCandidate(
        id: obj.id,
        label: obj.label,
        vietnameseLabel: obj.vietnameseLabel,
        category: obj.category,
        direction: obj.direction,
        panValue: obj.panValue,
        distanceLevel: obj.distanceLevel,
        approximateDistanceMeters: obj.approximateDistanceMeters,
        isApproaching: obj.isApproaching,
        isHeadLevelHazard: obj.isHeadLevelHazard,
      ));
    }

    // 2. Chướng ngại vật tầm đầu
    for (final go in genericObstacles) {
      candidates.add(AlertCandidate(
        id: go.id,
        label: go.label,
        vietnameseLabel: go.vietnameseLabel,
        category: 'obstacle',
        direction: go.direction,
        panValue: go.panValue,
        distanceLevel: go.distanceLevel,
        approximateDistanceMeters: go.approximateDistanceMeters,
        isHeadLevelHazard: true,
      ));
    }

    // 3. Hiểm họa mặt đất (Bậc tam cấp / Lề đường)
    for (final gh in groundHazards) {
      candidates.add(AlertCandidate(
        id: 'ground_${gh.type.name}_${(gh.normalizedY * 100).toInt()}',
        label: gh.type.name,
        vietnameseLabel: gh.vietnameseName,
        category: 'ground_hazard',
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: gh.distanceLevel,
        approximateDistanceMeters: gh.distanceMeters,
        isNegativeObstacle: gh.isNegativeObstacle,
      ));
    }

    // NẾU KHÔNG CÓ HIỂM HỌA NÀO
    if (candidates.isEmpty) {
      currentThreat = null;

      // Nhịp đập giữ liên lạc: Rung nhẹ 35ms mỗi 12 giây im lặng
      if ((now - _lastAlertActivityTime >= 12000) && (now - _lastHeartbeatTime >= 12000)) {
        audio.triggerHeartbeatHaptic();
        _lastHeartbeatTime = now;
      }

      return null;
    }

    // Chọn hiểm họa có điểm nguy hiểm cao nhất
    final primary = _selectPrimaryThreat(candidates);
    currentThreat = primary;

    if (primary == null) return null;

    // Kiểm tra Cooldown
    int requiredInterval = beepIntervalFarMs;
    if (primary.distanceLevel == DistanceLevel.critical) {
      requiredInterval = beepIntervalCriticalMs;
    } else if (primary.distanceLevel == DistanceLevel.near) {
      requiredInterval = beepIntervalNearMs;
    }

    if (now - _lastBeepTime >= requiredInterval) {
      _emitAlert(primary);
      _lastBeepTime = now;
      _lastAlertActivityTime = now;
    }

    return primary;
  }

  AlertCandidate? _selectPrimaryThreat(List<AlertCandidate> list) {
    AlertCandidate? best;
    int highestScore = -1;

    for (final c in list) {
      int score = 0;

      // Cự ly
      if (c.distanceLevel == DistanceLevel.critical) score += 100;
      else if (c.distanceLevel == DistanceLevel.near) score += 40;
      else score += 10;

      // Hướng: Hành lang giữa nguy hiểm nhất
      if (c.direction == DirectionZone.center) score += 50;
      else score += 15;

      // Hiểm họa đặc biệt: Bậc bước xuống / mép lề đường (Vật cản âm)
      if (c.isNegativeObstacle) score += 170;

      // Xe máy lao tới
      if (c.isApproaching) score += 160;

      // Vật cản tầm đầu / bạt che
      if (c.isHeadLevelHazard) score += 130;

      // Bậc tam cấp bước lên
      if (c.category == 'ground_hazard' && !c.isNegativeObstacle) score += 85;

      // Phương tiện & Người
      if (c.category == 'vehicle') score += 35;
      else if (c.category == 'pedestrian') score += 15;

      if (score > highestScore) {
        highestScore = score;
        best = c;
      }
    }

    return best;
  }

  void _emitAlert(AlertCandidate threat) {
    // 1. CẢNH BÁO BẬC BƯỚC XUỐNG / MÉP LỀ ĐƯỜNG (Cực kỳ nguy hiểm)
    if (threat.isNegativeObstacle) {
      audio.playDirectionalBeep(pan: 0.0, pitch: 320, durationMs: 110);
      audio.triggerHaptic(HapticIntensity.critical);
      audio.speakVietnamese('Chú ý: bậc đi xuống!', force: true);
      return;
    }

    // 2. BẬC BƯỚC LÊN
    if (threat.category == 'ground_hazard') {
      audio.playDirectionalBeep(pan: 0.0, pitch: 480, durationMs: 80);
      audio.triggerHaptic(HapticIntensity.near);
      if (threat.distanceLevel != DistanceLevel.far) {
        audio.speakVietnamese('Có bậc bước lên');
      }
      return;
    }

    // 3. VẬT CẢN TẦM ĐẦU / BẠT CHE
    if (threat.isHeadLevelHazard) {
      audio.playDirectionalBeep(pan: threat.panValue, pitch: 1100, durationMs: 75);
      audio.triggerHaptic(HapticIntensity.critical);
      audio.speakVietnamese('Vật cản ngang đầu!', force: true);
      return;
    }

    // 4. VẬT THỂ TIÊU CHUẨN
    int pitch = 440;
    if (threat.distanceLevel == DistanceLevel.critical) pitch = 980;
    else if (threat.distanceLevel == DistanceLevel.near) pitch = 680;

    final int duration = threat.distanceLevel == DistanceLevel.critical ? 80 : 50;

    audio.playDirectionalBeep(pan: threat.panValue, pitch: pitch, durationMs: duration);

    if (threat.distanceLevel == DistanceLevel.critical || threat.isApproaching) {
      audio.triggerHaptic(HapticIntensity.critical);
    } else if (threat.distanceLevel == DistanceLevel.near) {
      audio.triggerHaptic(HapticIntensity.near);
    }

    // Giọng nói ngắn gọn chỉ khi nguy cấp
    if (threat.isApproaching) {
      audio.speakVietnamese('${threat.vietnameseLabel} đang tới gần!', force: true);
    } else if (threat.distanceLevel == DistanceLevel.critical && threat.direction == DirectionZone.center) {
      audio.speakVietnamese('Vật cản trước mặt');
    }
  }
}

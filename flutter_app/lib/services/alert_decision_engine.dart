import '../config/thresholds.dart';
import '../models/detection_result.dart';
import '../models/ground_hazard.dart';
import 'audio_haptics_service.dart';

/// alert_decision_engine.dart
/// Bộ não ra quyết định cảnh báo, xếp hạng ưu tiên hiểm họa và chống mỏi thính giác
/// Sửa Lỗi 2: Bíp và rung vẫn lặp theo chu kỳ nhưng giọng nói không lặp và không cắt ngang câu.

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
  final double confidence;
  final bool isMediumConfidence;

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
    this.confidence = 1.0,
    this.isMediumConfidence = false,
  });
}

class AlertDecisionEngine {
  final AudioHapticsService audio;

  int _lastBeepTime = 0;
  int _lastAlertActivityTime = 0;
  int _lastHeartbeatTime = 0;

  // Quản lý trạng thái giọng nói chống lặp và chống cắt ngang
  final Map<String, int> _threatSpeechTimeMap = {};
  int _lastAnySpeechTime = 0;
  int _lastSpokenPriority = 0;

  AlertCandidate? currentThreat;

  AlertDecisionEngine({required this.audio}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastAlertActivityTime = now;
    _lastHeartbeatTime = now;
  }

  AlertCandidate? process({
    required List<DetectionResult> objects2D,
    required List<GroundHazard> groundHazards,
    List<DetectionResult> genericObstacles = const [],
    int? customNow,
  }) {
    final int now = customNow ?? DateTime.now().millisecondsSinceEpoch;
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
      final bool isMedium = gh.confidence < 0.80 || gh.vietnameseName.contains('Có thể');
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
        confidence: gh.confidence,
        isMediumConfidence: isMedium,
      ));
    }

    // NẾU KHÔNG CÓ HIỂM HỌA NÀO
    if (candidates.isEmpty) {
      currentThreat = null;

      // Nhịp đập giữ liên lạc: Rung nhẹ 35ms mỗi 12 giây im lặng
      if ((now - _lastAlertActivityTime >= kHeartbeatIntervalMs) &&
          (now - _lastHeartbeatTime >= kHeartbeatIntervalMs)) {
        audio.triggerHeartbeatHaptic();
        _lastHeartbeatTime = now;
      }

      return null;
    }

    // Chọn hiểm họa có điểm nguy hiểm cao nhất
    final primary = _selectPrimaryThreat(candidates);
    currentThreat = primary;

    if (primary == null) return null;

    final int threatScore = calculateThreatScore(primary);

    // Chu kỳ bíp định hướng âm thanh (240ms nguy cấp, 700ms gần, 2200ms xa)
    int requiredBeepInterval = kBeepIntervalFarMs;
    if (primary.distanceLevel == DistanceLevel.critical) {
      requiredBeepInterval = kBeepIntervalCriticalMs;
    } else if (primary.distanceLevel == DistanceLevel.near) {
      requiredBeepInterval = kBeepIntervalNearMs;
    }

    // Bíp và Rung phát liên tục theo chu kỳ để giữ cảm nhận không gian
    if (now - _lastBeepTime >= requiredBeepInterval) {
      _playBeepAndHaptic(primary);
      _lastBeepTime = now;
      _lastAlertActivityTime = now;
    }

    // Xử lý Giọng nói riêng biệt: mỗi mối đe dọa chỉ nói 1 lần rồi im tối thiểu 3 giây
    _handleSpeechAlert(primary, threatScore, now);

    return primary;
  }

  int calculateThreatScore(AlertCandidate c) {
    int score = 0;

    // Cự ly
    if (c.distanceLevel == DistanceLevel.critical) {
      score += 100;
    } else if (c.distanceLevel == DistanceLevel.near) {
      score += 40;
    } else {
      score += 10;
    }

    // Hướng: Hành lang giữa nguy hiểm nhất
    if (c.direction == DirectionZone.center) {
      score += 50;
    } else {
      score += 15;
    }

    // Hiểm họa đặc biệt: Bậc bước xuống / mép lề đường (Vật cản âm độ tin cậy cao)
    if (c.isNegativeObstacle && !c.isMediumConfidence) score += 170;

    // Xe máy lao tới
    if (c.isApproaching) score += 160;

    // Vật cản tầm đầu / bạt che
    if (c.isHeadLevelHazard) score += 130;

    // Hiểm họa mặt đất (bậc thềm, lề đường bước lên hoặc độ tin cậy trung bình)
    if (c.category == 'ground_hazard' && !c.isNegativeObstacle) {
      if (c.isMediumConfidence) {
        // Cảnh báo ground_hazard độ tin cậy trung bình KHÔNG ĐƯỢC VƯỢT xe hoặc người ở mức near
        score += kMediumGroundHazardThreatBonus;
      } else {
        score += kHighGroundHazardThreatBonus;
      }
    }

    // Phương tiện & Người
    if (c.category == 'vehicle') {
      score += 35;
    } else if (c.category == 'pedestrian') {
      score += 15;
    }

    return score;
  }

  AlertCandidate? _selectPrimaryThreat(List<AlertCandidate> list) {
    AlertCandidate? best;
    int highestScore = -1;

    for (final c in list) {
      final score = calculateThreatScore(c);
      if (score > highestScore) {
        highestScore = score;
        best = c;
      }
    }

    return best;
  }

  /// Phát âm thanh bíp định hướng và rung xúc giác theo chu kỳ
  void _playBeepAndHaptic(AlertCandidate threat) {
    if (threat.isNegativeObstacle) {
      audio.playDirectionalBeep(
        pan: 0.0,
        pitch: 320,
        durationMs: 110,
        direction: DirectionZone.center,
      );
      audio.triggerHaptic(HapticIntensity.critical);
      return;
    }

    if (threat.category == 'ground_hazard') {
      audio.playDirectionalBeep(
        pan: 0.0,
        pitch: 480,
        durationMs: 80,
        direction: DirectionZone.center,
      );
      audio.triggerHaptic(HapticIntensity.near);
      return;
    }

    if (threat.isHeadLevelHazard) {
      audio.playDirectionalBeep(
        pan: threat.panValue,
        pitch: 1100,
        durationMs: 75,
        direction: threat.direction,
      );
      audio.triggerHaptic(HapticIntensity.critical);
      return;
    }

    int pitch = 750;
    if (threat.direction == DirectionZone.left) {
      pitch = 500;
    } else if (threat.direction == DirectionZone.right) {
      pitch = 1000;
    }

    final int duration = threat.distanceLevel == DistanceLevel.critical ? 80 : 50;
    audio.playDirectionalBeep(
      pan: threat.panValue,
      pitch: pitch,
      durationMs: duration,
      direction: threat.direction,
    );

    if (threat.distanceLevel == DistanceLevel.critical || threat.isApproaching) {
      audio.triggerHaptic(HapticIntensity.critical);
    } else if (threat.distanceLevel == DistanceLevel.near) {
      audio.triggerHaptic(HapticIntensity.near);
    }
  }

  /// Quản lý phát giọng nói: Mỗi mối đe dọa chỉ nói một lần, sau đó im tối thiểu 3 giây.
  /// Chỉ ngắt câu khi mối đe dọa mới có mức ưu tiên cao hơn hẳn.
  void _handleSpeechAlert(AlertCandidate threat, int threatScore, int now) {
    String? text;
    String speechKey = '';
    int speechPriority = 0;

    if (threat.isNegativeObstacle) {
      text = 'Chú ý: bậc đi xuống!';
      speechKey = 'step_down';
      speechPriority = 250;
    } else if (threat.isHeadLevelHazard) {
      text = 'Vật cản ngang đầu!';
      speechKey = 'head_hazard';
      speechPriority = 220;
    } else if (threat.isApproaching) {
      text = '${threat.vietnameseLabel} đang tới gần!';
      speechKey = 'approaching_${threat.id}';
      speechPriority = 210;
    } else if (threat.category == 'ground_hazard') {
      if (threat.distanceLevel != DistanceLevel.far) {
        text = threat.vietnameseLabel;
        speechKey = 'ground_${threat.label}';
        speechPriority = 120;
      }
    } else if (threat.distanceLevel == DistanceLevel.critical &&
        threat.direction == DirectionZone.center) {
      text = 'Vật cản trước mặt';
      speechKey = 'critical_center_${threat.id}';
      speechPriority = 160;
    }

    if (text == null) return;

    final int lastSpoken = _threatSpeechTimeMap[speechKey] ?? 0;
    final int elapsedThisThreat = now - lastSpoken;
    final int elapsedAnySpeech = now - _lastAnySpeechTime;

    // Điều kiện phát giọng nói:
    // 1. Mối đe dọa này chưa được nói trong vòng kSpeechCooldownMs (tối thiểu 3 giây)
    // 2. VÀ hệ thống không đang nói câu khác trong 3 giây gần nhất,
    //    TRỪ KHI câu mới có mức ưu tiên cao hơn hẳn (chênh lệch >= 40 điểm) và câu cũ đã nói ít nhất 800ms
    final bool canSpeakThis = elapsedThisThreat >= kSpeechCooldownMs;
    final bool isHigherPriorityInterrupt =
        (speechPriority >= _lastSpokenPriority + 40) && (elapsedAnySpeech >= 800);

    if (canSpeakThis && (elapsedAnySpeech >= kSpeechCooldownMs || isHigherPriorityInterrupt)) {
      _threatSpeechTimeMap[speechKey] = now;
      _lastAnySpeechTime = now;
      _lastSpokenPriority = speechPriority;

      audio.speakVietnamese(
        text,
        force: isHigherPriorityInterrupt,
        priority: speechPriority,
        customNow: now,
      );
    }

    // Dọn dẹp cache lịch sử cũ sau 15 giây
    if (_threatSpeechTimeMap.length > 20) {
      _threatSpeechTimeMap.removeWhere((_, time) => now - time > 15000);
    }
  }

  void reset() {
    _lastBeepTime = 0;
    _lastAlertActivityTime = 0;
    _lastHeartbeatTime = 0;
    _lastAnySpeechTime = 0;
    _lastSpokenPriority = 0;
    _threatSpeechTimeMap.clear();
    currentThreat = null;
  }
}

/**
 * alert_engine.js
 * Bộ não ra quyết định cảnh báo (Decision Engine) - Đã tinh chỉnh theo Giai đoạn 3
 * 
 * NÂNG CẤP GIAI ĐOẠN 3:
 * 1. Chống mỏi thính giác: Tăng Cooldown cự ly xa từ 1.4s lên 2.2s.
 * 2. Lọc vùng mù ngoại vi (Peripheral Deadzone): Không bíp dồn dập vật cản ở rìa xa.
 * 3. Nhịp đập giữ liên lạc (Heartbeat Haptic Pulse): Rung nhẹ 35ms mỗi 12 giây im lặng để giải tỏa âu lo.
 * 4. Bậc bước xuống / mép lề đường & Xe máy lao tới giữ nguyên mức ưu tiên số 1.
 */

class AlertDecisionEngine {
  constructor(audioHaptics) {
    this.audio = audioHaptics;

    // Thời gian lần bíp gần nhất
    this.lastBeepTime = 0;
    // Thời gian lần phát cảnh báo gần nhất (âm thanh hoặc giọng nói)
    this.lastAlertActivityTime = Date.now();
    // Thời gian lần rung heartbeat gần nhất
    this.lastHeartbeatTime = Date.now();

    // Chu kỳ bíp đã tinh chỉnh để chống mỏi thính giác
    this.BEEP_INTERVALS = {
      'critical': 240, // 4 lần / giây khi rất gần hoặc đang lao tới
      'near': 700,     // ~1.4 lần / giây khi ở cự ly 1.5 - 3m
      'far': 2200      // Bíp thưa 2.2s / lần ở cự ly xa để không gây đau đầu trên phố đông
    };

    // Tần số âm thanh (Pitch Hz) theo mức độ
    this.PITCH_LEVELS = {
      'critical': 980,
      'near': 680,
      'far': 440
    };

    this.currentThreat = null;
  }

  /**
   * Xử lý hợp nhất toàn bộ các nguồn phát hiện
   */
  process(analyzed2DObjects = [], genericObstacles = [], groundHazards = []) {
    const now = Date.now();
    const allCandidates = [];

    // 1. Lọc vật thể 2D: Loại bỏ các vật cản tĩnh ở rìa ngoài góc nhìn (x < 15% hoặc x > 85%) và ở xa
    for (const obj of analyzed2DObjects) {
      const isExtremeEdge = obj.normalized && (obj.normalized.centerX < 0.15 || obj.normalized.centerX > 0.85);
      if (isExtremeEdge && obj.distanceLevel === 'far' && !obj.isApproaching) {
        // Bỏ qua để không spam âm thanh khi đi qua dãy xe máy đỗ dọc lề
        continue;
      }
      allCandidates.push(obj);
    }

    if (genericObstacles && genericObstacles.length > 0) {
      allCandidates.push(...genericObstacles);
    }

    if (groundHazards && groundHazards.length > 0) {
      for (const gh of groundHazards) {
        allCandidates.push({
          id: 'ground_' + gh.type + '_' + Math.round(gh.normalizedY * 100),
          class: gh.type,
          vietnameseClass: gh.vietnameseName,
          category: 'ground_hazard',
          direction: 'center',
          panValue: 0.0,
          distanceLevel: gh.distanceLevel,
          approximateDistanceMeters: gh.distanceMeters,
          isNegativeObstacle: gh.isNegativeObstacle,
          score: gh.confidence
        });
      }
    }

    // NẾU KHÔNG CÓ HIỂM HỌA NÀO
    if (allCandidates.length === 0) {
      this.currentThreat = null;

      // Kích hoạt Heartbeat Pulse nếu đã im lặng quá 12 giây
      if (now - this.lastAlertActivityTime >= 12000 && now - this.lastHeartbeatTime >= 12000) {
        this.audio.triggerHeartbeatHaptic();
        this.lastHeartbeatTime = now;
      }

      return null;
    }

    // 2. Chọn hiểm họa nguy hiểm nhất
    const primaryThreat = this.selectPrimaryThreat(allCandidates);
    this.currentThreat = primaryThreat;

    if (!primaryThreat) return null;

    // 3. Kiểm tra chu kỳ bíp (Cooldown)
    const requiredInterval = this.BEEP_INTERVALS[primaryThreat.distanceLevel] || 1200;
    if (now - this.lastBeepTime >= requiredInterval) {
      this.emitAlert(primaryThreat);
      this.lastBeepTime = now;
      this.lastAlertActivityTime = now;
    }

    return primaryThreat;
  }

  /**
   * Thuật toán chấm điểm mối đe dọa (Threat Scoring)
   */
  selectPrimaryThreat(objects) {
    let bestCandidate = null;
    let highestThreatScore = -1;

    for (const obj of objects) {
      let score = 0;

      // Điểm cự ly
      if (obj.distanceLevel === 'critical') score += 100;
      else if (obj.distanceLevel === 'near') score += 40;
      else score += 10;

      // Điểm hướng: Hành lang giữa nguy hiểm nhất
      if (obj.direction === 'center') score += 50;
      else score += 15;

      // Bậc bước xuống / lề đường tụt (Negative obstacle)
      if (obj.isNegativeObstacle) {
        score += 170;
      }

      // Xe máy lao tới
      if (obj.isApproaching) {
        score += 160;
      }

      // Vật cản tầm đầu / bạt che
      if (obj.isHeadLevelHazard) {
        score += 130;
      }

      // Bậc tam cấp bước lên
      if (obj.category === 'ground_hazard' && !obj.isNegativeObstacle) {
        score += 85;
      }

      // Phương tiện & Người
      if (obj.category === 'vehicle') score += 35;
      else if (obj.category === 'pedestrian') score += 15;

      if (score > highestThreatScore) {
        highestThreatScore = score;
        bestCandidate = obj;
      }
    }

    return bestCandidate;
  }

  /**
   * Phát tín hiệu cảnh báo
   */
  emitAlert(threat) {
    // 1. BẬC BƯỚC XUỐNG / MÉP LỀ ĐƯỜNG (Step Down / Drop-off)
    if (threat.isNegativeObstacle) {
      this.audio.playDirectionalBeep(0.0, 320, 110);
      this.audio.triggerHaptic('critical');
      this.audio.speakVietnamese('Chú ý: bậc đi xuống!', true);
      return;
    }

    // 2. BẬC TAM CẤP BƯỚC LÊN (Step Up)
    if (threat.category === 'ground_hazard') {
      this.audio.playDirectionalBeep(0.0, 480, 80);
      this.audio.triggerHaptic('near');
      if (threat.distanceLevel === 'critical' || threat.distanceLevel === 'near') {
        this.audio.speakVietnamese('Có bậc bước lên', false);
      }
      return;
    }

    // 3. VẬT CẢN TẦM ĐẦU / BẠT CHE (Head Level Hazard)
    if (threat.isHeadLevelHazard) {
      this.audio.playDirectionalBeep(threat.panValue, 1100, 75);
      this.audio.triggerHaptic('critical');
      this.audio.speakVietnamese('Vật cản ngang đầu!', true);
      return;
    }

    // 4. VẬT THỂ TIÊU CHUẨN (2D Objects)
    const pitch = this.PITCH_LEVELS[threat.distanceLevel] || 500;
    const duration = threat.distanceLevel === 'critical' ? 80 : 50;

    this.audio.playDirectionalBeep(threat.panValue, pitch, duration);

    if (threat.distanceLevel === 'critical' || threat.isApproaching) {
      this.audio.triggerHaptic('critical');
    } else if (threat.distanceLevel === 'near') {
      this.audio.triggerHaptic('near');
    }

    if (threat.isApproaching) {
      this.audio.speakVietnamese(`${threat.vietnameseClass} đang tới gần!`, true);
    } else if (threat.distanceLevel === 'critical' && threat.direction === 'center') {
      this.audio.speakVietnamese('Vật cản trước mặt', false);
    }
  }
}

window.AlertDecisionEngine = AlertDecisionEngine;

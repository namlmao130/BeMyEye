import 'dart:math';

import '../config/thresholds.dart';
import '../models/detection_result.dart';

/// spatial_analyzer.dart
/// Phân tích không gian 2D, 3 hành lang di chuyển và tốc độ lao tới của vật thể
/// Khắc phục Lỗi 3 & Lỗi 4:
/// - Tính tốc độ tăng diện tích tương đối trên cửa sổ trượt ~0.5 giây
/// - Chỉ đánh dấu isApproaching cho category == 'vehicle'
/// - Trừ chuyển động của chính người đi bộ (bù trừ vận tốc GPS/bước chân)
/// - Ghép track một-một (Greedy matching) và ID tăng dần tránh trùng lặp

class AreaSample {
  final int timestamp;
  final double area;

  AreaSample(this.timestamp, this.area);
}

class ApproachingEvaluation {
  final bool isApproaching;
  final double growthRate;
  final double rSquared;
  final double slope;

  const ApproachingEvaluation({
    required this.isApproaching,
    required this.growthRate,
    required this.rSquared,
    required this.slope,
  });
}

class SpatialTrack {
  final String id;
  final String label;
  final String category;
  int lastTimeMs;
  double lastArea;
  double lastCx;
  double lastCy;
  final List<AreaSample> areaHistory = [];
  int consecutiveApproachingFrames = 0;

  SpatialTrack({
    required this.id,
    required this.label,
    required this.category,
    required this.lastTimeMs,
    required this.lastArea,
    required this.lastCx,
    required this.lastCy,
  }) {
    areaHistory.add(AreaSample(lastTimeMs, lastArea));
  }

  void addSample(int timestamp, double area, double cx, double cy) {
    lastTimeMs = timestamp;
    lastArea = area;
    lastCx = cx;
    lastCy = cy;
    areaHistory.add(AreaSample(timestamp, area));

    // Cửa sổ trượt kAreaHistoryWindowMs (mặc định 800ms) để đủ ít nhất 5 mẫu và >= 0.3s
    areaHistory.removeWhere(
      (s) => timestamp - s.timestamp > kAreaHistoryWindowMs,
    );
  }

  /// Hồi quy tuyến tính diện tích trên >= 5 mẫu, khoảng thời gian >= 0.3s để làm mượt
  /// và xác định chính xác phương tiện có đang lao tới hay chỉ là nhiễu nhảy hộp (+-20%)
  ApproachingEvaluation evaluateApproaching(int now, double walkingSpeedMps) {
    if (areaHistory.length < kMinApproachingSamples) {
      return const ApproachingEvaluation(
        isApproaching: false,
        growthRate: 0.0,
        rSquared: 0.0,
        slope: 0.0,
      );
    }

    final oldest = areaHistory.first;
    final double timeSpanSec = (now - oldest.timestamp) / 1000.0;
    if (timeSpanSec < kMinApproachingTimeSpanSec) {
      return const ApproachingEvaluation(
        isApproaching: false,
        growthRate: 0.0,
        rSquared: 0.0,
        slope: 0.0,
      );
    }

    final int n = areaHistory.length;
    final int t0 = oldest.timestamp;

    double sumX = 0.0;
    double sumY = 0.0;
    for (int i = 0; i < n; i++) {
      final double xi = (areaHistory[i].timestamp - t0) / 1000.0;
      final double yi = areaHistory[i].area;
      sumX += xi;
      sumY += yi;
    }

    final double meanX = sumX / n;
    final double meanY = sumY / n;
    if (meanY <= 0.001) {
      return const ApproachingEvaluation(
        isApproaching: false,
        growthRate: 0.0,
        rSquared: 0.0,
        slope: 0.0,
      );
    }

    double ssXX = 0.0;
    double ssXY = 0.0;
    double ssYY = 0.0;
    for (int i = 0; i < n; i++) {
      final double xi = (areaHistory[i].timestamp - t0) / 1000.0;
      final double yi = areaHistory[i].area;
      final double dx = xi - meanX;
      final double dy = yi - meanY;
      ssXX += dx * dx;
      ssXY += dx * dy;
      ssYY += dy * dy;
    }

    if (ssXX < 1e-9) {
      return const ApproachingEvaluation(
        isApproaching: false,
        growthRate: 0.0,
        rSquared: 0.0,
        slope: 0.0,
      );
    }

    final double slope = ssXY / ssXX;
    final double rSquared = (ssYY > 1e-9) ? (ssXY * ssXY) / (ssXX * ssYY) : 0.0;
    final double relativeGrowthRate = slope / meanY;

    // Bù trừ chuyển động của chính người đi bộ (bước chân/GPS)
    final double dynamicThreshold =
        kApproachThreshold + (walkingSpeedMps * 0.15);

    // Tính tính liên tục tăng tương đối giữa các bước kế tiếp nhau
    int nonDecreasingSteps = 0;
    for (int i = 1; i < n; i++) {
      if (areaHistory[i].area >= areaHistory[i - 1].area * 0.90) {
        nonDecreasingSteps++;
      }
    }
    final double continuityRatio = nonDecreasingSteps / (n - 1);

    // Điều kiện tiếp cận:
    // 1. Độ dốc dương (slope > 0)
    // 2. Tốc độ tăng tương đối vượt ngưỡng động
    // 3. R^2 >= kMinApproachingRSquared (loại bỏ hộp dao động ngẫu nhiên quanh 1 giá trị)
    // 4. Mẫu cuối cùng phải lớn hơn mẫu đầu tiên
    // 5. Tỷ lệ bước tăng tương đối liên tục đạt chuẩn
    final bool isConsistentIncrease = slope > 0 &&
        relativeGrowthRate >= dynamicThreshold &&
        rSquared >= kMinApproachingRSquared &&
        areaHistory.last.area > oldest.area &&
        continuityRatio >= 0.70;

    return ApproachingEvaluation(
      isApproaching: isConsistentIncrease,
      growthRate: relativeGrowthRate,
      rSquared: rSquared,
      slope: slope,
    );
  }

  /// Tính tốc độ tăng diện tích tương đối (fallback backward-compatibility)
  double calculateRelativeGrowthRate(int now) {
    final eval = evaluateApproaching(now, 0.0);
    return eval.growthRate;
  }
}

class MatchCandidate {
  final int detectionIndex;
  final int trackIndex;
  final double distance;

  MatchCandidate(this.detectionIndex, this.trackIndex, this.distance);
}

class SpatialAnalyzer {
  final List<SpatialTrack> _trackedObjects = [];
  int _nextTrackId = 1;

  List<SpatialTrack> get activeTracks => List.unmodifiable(_trackedObjects);

  /// Phân tích vị trí không gian 2D, gán track 1-1 và xác định phương tiện đang lao tới
  List<DetectionResult> analyze(
    List<Map<String, dynamic>> rawDetections,
    double frameWidth,
    double frameHeight, {
    double walkingSpeedMps = 0.0,
    double tiltAngleRad = 0.0,
    int? customNow,
  }) {
    final now = customNow ?? DateTime.now().millisecondsSinceEpoch;
    final List<DetectionResult> results = [];

    // 1. Thu thập dữ liệu trắc lượng thô của các detections
    final List<Map<String, dynamic>> parsedDetections = [];
    for (int i = 0; i < rawDetections.length; i++) {
      final raw = rawDetections[i];
      final List<double> bbox = List<double>.from(raw['bbox']);
      final double x = bbox[0];
      final double y = bbox[1];
      final double w = bbox[2];
      final double h = bbox[3];

      final double cx = (x + w / 2) / frameWidth;
      final double bottomY = (y + h) / frameHeight;
      final double areaRatio = (w * h) / (frameWidth * frameHeight);
      final String label = raw['label'] ?? raw['class'] ?? 'unknown';
      final String category = raw['category'] ?? 'obstacle';

      parsedDetections.add({
        'rawIndex': i,
        'raw': raw,
        'bbox': bbox,
        'cx': cx,
        'bottomY': bottomY,
        'areaRatio': areaRatio,
        'label': label,
        'category': category,
      });
    }

    // 2. GHÉP TRACK MỘT-MỘT (Greedy 1-to-1 Bipartite Matching)
    final List<MatchCandidate> matchCandidates = [];
    for (int dIdx = 0; dIdx < parsedDetections.length; dIdx++) {
      final d = parsedDetections[dIdx];
      for (int tIdx = 0; tIdx < _trackedObjects.length; tIdx++) {
        final t = _trackedObjects[tIdx];
        if (t.label == d['label']) {
          final dist = sqrt(
            pow(t.lastCx - (d['cx'] as double), 2) +
                pow(t.lastCy - (d['bottomY'] as double), 2),
          );
          // Ngưỡng khoảng cách tối đa để coi là cùng 1 track (35% màn hình)
          if (dist <= 0.35) {
            matchCandidates.add(MatchCandidate(dIdx, tIdx, dist));
          }
        }
      }
    }

    // Sắp xếp các cặp ghép theo khoảng cách tăng dần (gần nhất ghép trước)
    matchCandidates.sort((a, b) => a.distance.compareTo(b.distance));

    final Set<int> matchedDetections = {};
    final Set<int> matchedTracks = {};
    final Map<int, int> detectionToTrackMap = {}; // dIdx -> tIdx

    for (final match in matchCandidates) {
      if (!matchedDetections.contains(match.detectionIndex) &&
          !matchedTracks.contains(match.trackIndex)) {
        matchedDetections.add(match.detectionIndex);
        matchedTracks.add(match.trackIndex);
        detectionToTrackMap[match.detectionIndex] = match.trackIndex;
      }
    }

    // 3. Cập nhật các track đã ghép & Tạo track mới cho các detection chưa ghép
    for (int dIdx = 0; dIdx < parsedDetections.length; dIdx++) {
      final d = parsedDetections[dIdx];
      final raw = d['raw'] as Map<String, dynamic>;
      final bbox = d['bbox'] as List<double>;
      final double cx = d['cx'];
      final double bottomY = d['bottomY'];
      final double areaRatio = d['areaRatio'];
      final String label = d['label'];
      final String category = d['category'];

      SpatialTrack track;
      if (detectionToTrackMap.containsKey(dIdx)) {
        final int trackIdx = detectionToTrackMap[dIdx]!;
        track = _trackedObjects[trackIdx];
        track.addSample(now, areaRatio, cx, bottomY);
      } else {
        final String newId = 'track_${_nextTrackId++}';
        track = SpatialTrack(
          id: newId,
          label: label,
          category: category,
          lastTimeMs: now,
          lastArea: areaRatio,
          lastCx: cx,
          lastCy: bottomY,
        );
        _trackedObjects.add(track);
      }

      // 4. PHÂN VÙNG HÀNH LANG (Trái / Giữa / Phải) & Pan Âm thanh
      DirectionZone direction = DirectionZone.center;
      double panValue = 0.0;

      if (cx < kLeftBoundary) {
        direction = DirectionZone.left;
        panValue = -0.3 - (1.0 - (cx / kLeftBoundary)) * 0.7;
      } else if (cx > kRightBoundary) {
        direction = DirectionZone.right;
        panValue = 0.3 + ((cx - kRightBoundary) / (1.0 - kRightBoundary)) * 0.7;
      } else {
        direction = DirectionZone.center;
        panValue = (cx - 0.5) * 0.4;
      }

      // Bù trừ góc nghiêng điện thoại (tiltAngleRad)
      // QUY ƯỚC QUAN TRỌNG (NV12.4): Khi camera chúc xuống đất (tiltAngleRad > 0),
      // vật thể trên mặt đất dịch lên trên khung ảnh, do đó ngưỡng bottomY PHẢI GIẢM TƯƠNG ỨNG.
      // Ngược lại khi camera ngửa lên trời (tiltAngleRad < 0), ngưỡng bottomY tăng.
      // (Cần chạy kiểm chứng trên máy thật đeo ngực).
      final double tiltOffset = (tiltAngleRad * kTiltCompensationFactor).clamp(
        -0.15,
        0.15,
      );

      final double effectiveCriticalBottomY =
          (kCriticalBottomY - tiltOffset).clamp(0.60, 0.95);
      final double effectiveNearBottomY = (kNearBottomY - tiltOffset).clamp(
        0.45,
        0.85,
      );

      final double effectiveLargeCriticalBottomY =
          (kLargeVehicleCriticalBottomY - tiltOffset).clamp(0.65, 0.95);
      final double effectiveLargeNearBottomY =
          (kLargeVehicleNearBottomY - tiltOffset).clamp(0.50, 0.85);

      // 5. ƯỚC LƯỢNG CỰ LY THEO LỚP ĐỐI TƯỢNG VÀ BÙ TRỪ GÓC NGHIÊNG
      final bool isLargeVehicle = kLargeVehicleClasses.contains(
        label.toLowerCase(),
      );
      DistanceLevel distLevel = DistanceLevel.far;
      String distText = '> 3.0m';

      if (isLargeVehicle) {
        // ĐỐI VỚI XE BUÝT / XE TẢI:
        // Xe buýt ở xa 15m vẫn chiếm diện tích lớn trong khung hình.
        // Để đạt mức critical (< 1.5m), BẮT BUỘC bánh xe (bottomY) phải chạm gần chân người đi bộ.
        if (bottomY >= effectiveLargeCriticalBottomY && areaRatio >= 0.25) {
          distLevel = DistanceLevel.critical;
          distText = '< 1.5m';
        } else if (bottomY >= effectiveLargeNearBottomY) {
          distLevel = DistanceLevel.near;
          distText = '1.5m - 3.0m';
        } else {
          distLevel = DistanceLevel.far;
          distText = '> 3.0m';
        }
      } else if (category == 'pedestrian') {
        // ĐỐI VỚI NGƯỜI ĐI BỘ:
        // Người đứng sát chân (bottomY >= 0.85) dù diện tích nhỏ (thân người gầy) vẫn là cự ly nguy cấp
        if (bottomY >= effectiveCriticalBottomY) {
          distLevel = DistanceLevel.critical;
          distText = '< 1.5m';
        } else if (bottomY >= effectiveNearBottomY ||
            areaRatio >= kNearAreaRatio) {
          distLevel = DistanceLevel.near;
          distText = '1.5m - 3.0m';
        } else {
          distLevel = DistanceLevel.far;
          distText = '> 3.0m';
        }
      } else {
        // ĐỐI VỚI XE MÁY, Ô TÔ CON VÀ CÁC VẬT CẢN KHÁC:
        if (bottomY >= effectiveCriticalBottomY ||
            (bottomY >= effectiveNearBottomY &&
                areaRatio >= kCriticalAreaRatio)) {
          distLevel = DistanceLevel.critical;
          distText = '< 1.5m';
        } else if (bottomY >= effectiveNearBottomY ||
            areaRatio >= kNearAreaRatio) {
          distLevel = DistanceLevel.near;
          distText = '1.5m - 3.0m';
        } else {
          distLevel = DistanceLevel.far;
          distText = '> 3.0m';
        }
      }

      // 6. XÁC ĐỊNH VẬT THỂ CÓ ĐANG LAO TỚI KHÔNG (isApproaching)
      bool isApproaching = false;
      double growthRate = 0.0;

      // NGUYÊN TẮC: CHỈ ĐÁNH DẤU CHO PHƯƠNG TIỆN (category == 'vehicle')
      // Vật tĩnh (cột điện, ghế, chậu cây, biển báo) tuyệt đối KHÔNG bao giờ là approaching
      if (category == 'vehicle') {
        final eval = track.evaluateApproaching(now, walkingSpeedMps);
        growthRate = eval.growthRate;

        // Yêu cầu diện tích đủ lớn (> 4% khung hình) và thỏa mãn hồi quy tuyến tính tiếp cận
        if (eval.isApproaching && areaRatio > 0.04) {
          track.consecutiveApproachingFrames++;
        } else {
          track.consecutiveApproachingFrames = 0;
        }

        // Yêu cầu duy trì liên tục qua ít nhất 2 khung hình liên tiếp
        if (track.consecutiveApproachingFrames >= 2) {
          isApproaching = true;
          distLevel = DistanceLevel.critical;
        }
      } else {
        track.consecutiveApproachingFrames = 0;
      }

      results.add(
        DetectionResult(
          id: track.id,
          label: label,
          vietnameseLabel:
              raw['vietnameseLabel'] ?? raw['vietnameseClass'] ?? label,
          category: category,
          score: (raw['score'] as num).toDouble(),
          bbox: bbox,
          centerX: cx,
          bottomY: bottomY,
          areaRatio: areaRatio,
          direction: direction,
          panValue: panValue.clamp(-1.0, 1.0),
          distanceLevel: distLevel,
          approximateDistanceMeters: distText,
          isApproaching: isApproaching,
          growthRate: growthRate,
        ),
      );
    }

    _cleanupOldTracks(now);
    return results;
  }

  void _cleanupOldTracks(int now) {
    _trackedObjects.removeWhere(
      (t) => (now - t.lastTimeMs) > kTrackExpirationMs,
    );
  }

  void reset() {
    _trackedObjects.clear();
    _nextTrackId = 1;
  }
}

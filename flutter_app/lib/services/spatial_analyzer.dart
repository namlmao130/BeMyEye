import 'dart:math';
import '../models/detection_result.dart';

/// spatial_analyzer.dart
/// Phân tích không gian 2D, 3 hành lang di chuyển và tốc độ lao tới của vật thể

class SpatialTrack {
  final String id;
  final String label;
  final int firstTimeMs;
  int lastTimeMs;
  final double firstArea;
  double lastArea;
  double lastCx;
  double lastCy;

  SpatialTrack({
    required this.id,
    required this.label,
    required this.firstTimeMs,
    required this.lastTimeMs,
    required this.firstArea,
    required this.lastArea,
    required this.lastCx,
    required this.lastCy,
  });
}

class SpatialAnalyzer {
  static const double leftBoundary = 0.35;
  static const double rightBoundary = 0.65;

  static const double nearBottomY = 0.65;
  static const double criticalBottomY = 0.82;
  static const double nearAreaRatio = 0.08;
  static const double criticalAreaRatio = 0.22;

  static const double approachThreshold = 0.15; // Tốc độ tăng diện tích / giây
  static const int trackExpirationMs = 600;

  final List<SpatialTrack> _trackedObjects = [];

  List<DetectionResult> analyze(
    List<Map<String, dynamic>> rawDetections,
    double frameWidth,
    double frameHeight,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<DetectionResult> results = [];

    for (final raw in rawDetections) {
      final List<double> bbox = List<double>.from(raw['bbox']);
      final double x = bbox[0];
      final double y = bbox[1];
      final double w = bbox[2];
      final double h = bbox[3];

      final double cx = (x + w / 2) / frameWidth;
      final double bottomY = (y + h) / frameHeight;
      final double areaRatio = (w * h) / (frameWidth * frameHeight);

      // 1. Phân vùng Trái / Giữa / Phải & Giá trị Pan
      DirectionZone direction = DirectionZone.center;
      double panValue = 0.0;

      if (cx < leftBoundary) {
        direction = DirectionZone.left;
        panValue = -0.3 - (1.0 - (cx / leftBoundary)) * 0.7;
      } else if (cx > rightBoundary) {
        direction = DirectionZone.right;
        panValue = 0.3 + ((cx - rightBoundary) / (1.0 - rightBoundary)) * 0.7;
      } else {
        direction = DirectionZone.center;
        panValue = (cx - 0.5) * 0.4;
      }

      // 2. Ước lượng cự ly
      DistanceLevel distLevel = DistanceLevel.far;
      String distText = '> 3.0m';

      if (bottomY >= criticalBottomY || areaRatio >= criticalAreaRatio) {
        distLevel = DistanceLevel.critical;
        distText = '< 1.5m';
      } else if (bottomY >= nearBottomY || areaRatio >= nearAreaRatio) {
        distLevel = DistanceLevel.near;
        distText = '1.5m - 3.0m';
      } else {
        distLevel = DistanceLevel.far;
        distText = '> 3.0m';
      }

      // 3. Kiểm tra vật thể có đang lao tới nhanh không
      final String label = raw['label'] ?? 'unknown';
      final approachResult = _checkIfApproaching(label, cx, bottomY, areaRatio, now);
      if (approachResult['isApproaching'] as bool) {
        distLevel = DistanceLevel.critical;
      }

      results.add(DetectionResult(
        id: approachResult['trackId'] as String,
        label: label,
        vietnameseLabel: raw['vietnameseLabel'] ?? label,
        category: raw['category'] ?? 'obstacle',
        score: (raw['score'] as num).toDouble(),
        bbox: bbox,
        centerX: cx,
        bottomY: bottomY,
        areaRatio: areaRatio,
        direction: direction,
        panValue: panValue.clamp(-1.0, 1.0),
        distanceLevel: distLevel,
        approximateDistanceMeters: distText,
        isApproaching: approachResult['isApproaching'] as bool,
        growthRate: (approachResult['growthRate'] as num).toDouble(),
      ));
    }

    _cleanupOldTracks(now);
    return results;
  }

  Map<String, dynamic> _checkIfApproaching(
    String label,
    double cx,
    double cy,
    double area,
    int timestamp,
  ) {
    SpatialTrack? matched;
    double minD = 0.25;

    for (final t in _trackedObjects) {
      if (t.label == label) {
        final d = sqrt(pow(t.lastCx - cx, 2) + pow(t.lastCy - cy, 2));
        if (d < minD) {
          minD = d;
          matched = t;
        }
      }
    }

    if (matched == null) {
      final newId = 'track_${Random().nextInt(100000)}';
      _trackedObjects.add(SpatialTrack(
        id: newId,
        label: label,
        firstTimeMs: timestamp,
        lastTimeMs: timestamp,
        firstArea: area,
        lastArea: area,
        lastCx: cx,
        lastCy: cy,
      ));
      return {'isApproaching': false, 'growthRate': 0.0, 'trackId': newId};
    }

    final double dt = (timestamp - matched.firstTimeMs) / 1000.0;
    double growthRate = 0.0;
    if (dt > 0.15) {
      growthRate = (area - matched.firstArea) / dt;
    }

    matched.lastTimeMs = timestamp;
    matched.lastArea = area;
    matched.lastCx = cx;
    matched.lastCy = cy;

    final bool isApproaching = (growthRate > approachThreshold && area > 0.05);

    return {
      'isApproaching': isApproaching,
      'growthRate': growthRate,
      'trackId': matched.id,
    };
  }

  void _cleanupOldTracks(int now) {
    _trackedObjects.removeWhere((t) => (now - t.lastTimeMs) > trackExpirationMs);
  }
}

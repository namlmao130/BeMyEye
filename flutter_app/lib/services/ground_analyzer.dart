import 'dart:typed_data';
import '../models/detection_result.dart';
import '../models/ground_hazard.dart';

/// ground_analyzer.dart
/// Phân tích mặt phẳng sàn và phát hiện Bậc thềm / Lề đường / Hố sụt

class GroundPlaneAnalyzer {
  static const int procWidth = 160;
  static const int procHeight = 120;
  static const double groundHorizonY = 0.40;
  static const double minStepWidthRatio = 0.35;
  static const int edgeThreshold = 38;

  final List<List<GroundHazard>> _history = [];
  static const int historySize = 8; // Bộ lọc 8 khung hình chống rung lắc nhịp bước chân

  List<GroundHazard> analyzeLuminance(Uint8List grayBytes, int width, int height) {
    final List<GroundHazard> candidates = [];
    final int startY = (procHeight * groundHorizonY).toInt();
    final int endY = (procHeight * 0.95).toInt();

    final Float32List rowEdgeStrength = Float32List(procHeight);

    // Quét ma trận Sobel ngang Gy ở nửa dưới khung hình
    for (int y = startY + 1; y < endY - 1; y++) {
      double horizontalEdgeSum = 0;
      int edgeCount = 0;

      for (int x = 10; x < procWidth - 10; x++) {
        final int idx = y * procWidth + x;
        if (idx - procWidth - 1 < 0 || idx + procWidth + 1 >= grayBytes.length) continue;

        final int gy = 
          -grayBytes[idx - procWidth - 1] - 2 * grayBytes[idx - procWidth] - grayBytes[idx - procWidth + 1] +
           grayBytes[idx + procWidth - 1] + 2 * grayBytes[idx + procWidth] + grayBytes[idx + procWidth + 1];

        final int absGy = gy.abs();
        if (absGy > edgeThreshold * 4) {
          horizontalEdgeSum += absGy;
          edgeCount++;
        }
      }

      if (edgeCount > procWidth * minStepWidthRatio) {
        rowEdgeStrength[y] = horizontalEdgeSum / edgeCount;
      }
    }

    // Tìm các đỉnh (Peaks) thể hiện mép bậc
    for (int y = startY + 2; y < endY - 2; y++) {
      if (rowEdgeStrength[y] > 180 &&
          rowEdgeStrength[y] > rowEdgeStrength[y - 1] &&
          rowEdgeStrength[y] > rowEdgeStrength[y + 1]) {
        
        final double normalizedY = y / procHeight;

        int intensityAbove = 0;
        int intensityBelow = 0;
        const int checkRange = 3;

        for (int x = (procWidth * 0.3).toInt(); x < (procWidth * 0.7).toInt(); x++) {
          final int idxAbove = (y - checkRange) * procWidth + x;
          final int idxBelow = (y + checkRange) * procWidth + x;
          if (idxAbove >= 0 && idxBelow < grayBytes.length) {
            intensityAbove += grayBytes[idxAbove];
            intensityBelow += grayBytes[idxBelow];
          }
        }

        final bool isStepDown = (intensityAbove > intensityBelow + 15);
        final GroundHazardType type = isStepDown ? GroundHazardType.stepDown : GroundHazardType.stepUp;

        DistanceLevel distLevel = DistanceLevel.near;
        String distText = '1.5m - 2.5m';
        if (normalizedY >= 0.78) {
          distLevel = DistanceLevel.critical;
          distText = '< 1.2m';
        } else if (normalizedY < 0.58) {
          distLevel = DistanceLevel.far;
          distText = '> 3.0m';
        }

        candidates.add(GroundHazard(
          type: type,
          vietnameseName: isStepDown ? 'Bậc đi xuống / Mép lề' : 'Bậc tam cấp bước lên',
          normalizedY: normalizedY,
          confidence: (rowEdgeStrength[y] / 300.0).clamp(0.0, 0.95),
          distanceLevel: distLevel,
          distanceMeters: distText,
          isNegativeObstacle: isStepDown,
        ));

        y += 6; // Bỏ qua vài dòng kế tiếp
      }
    }

    return _filterTemporalHazards(candidates);
  }

  List<GroundHazard> _filterTemporalHazards(List<GroundHazard> current) {
    _history.add(current);
    if (_history.length > historySize) {
      _history.removeAt(0);
    }

    if (current.isEmpty) return [];

    final List<GroundHazard> confirmed = [];
    for (final h in current) {
      int hitCount = 0;
      for (final pastList in _history) {
        if (pastList.any((p) => (p.normalizedY - h.normalizedY).abs() < 0.08 && p.type == h.type)) {
          hitCount++;
        }
      }

      // Ổn định qua >= 3/8 frames để triệt tiêu chao đảo lồng ngực
      if (hitCount >= 3) {
        confirmed.add(h);
      }
    }

    return confirmed;
  }
}

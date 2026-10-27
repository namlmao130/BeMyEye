import 'dart:typed_data';
import '../config/thresholds.dart';
import '../models/detection_result.dart';
import '../models/ground_hazard.dart';

/// ground_analyzer.dart
/// Phân tích mặt phẳng sàn và phát hiện Bậc thềm / Lề đường / Hố sụt
/// Khắc phục Lỗi 6:
/// - Tôn trọng kích thước width x height thực tế, kiểm tra đầu vào nghiêm ngặt
/// - Yêu cầu cạnh LIÊN TỤC (continuous edge segment), loại bỏ điểm ảnh rời rạc
/// - Loại bỏ vạch qua đường (Zebra crosswalk) bằng bộ đếm chuyển đổi chu kỳ
/// - Kiểm tra tính nhất quán hướng sáng/tối dọc theo mép bậc
/// - Hạ mức cam kết: Tin cậy vừa đổi thành "Có thể có bậc, hãy dùng gậy kiểm tra"

class GroundPlaneAnalyzer {
  final List<List<GroundHazard>> _history = [];

  List<GroundHazard> analyzeLuminance(Uint8List grayBytes, int width, int height) {
    // 1. Kiểm tra kích thước đầu vào nghiêm ngặt, tôn trọng width/height thực tế
    if (width <= 0 || height <= 0 || grayBytes.length < width * height) {
      throw ArgumentError(
        'Kích thước ảnh không hợp lệ: width=$width, height=$height, bytes=${grayBytes.length}',
      );
    }

    final List<GroundHazard> candidates = [];
    final int startY = (height * kGroundHorizonY).toInt();
    final int endY = (height * 0.95).toInt();
    final int minContinuousPixels = (width * kMinStepWidthRatio).toInt();

    final Float32List rowEdgeStrength = Float32List(height);
    final List<bool> rowIsStepDown = List.filled(height, false);
    final List<double> rowConsistency = List.filled(height, 0.0);

    const int margin = 8;

    // 2. Quét ma trận Sobel ngang Gy ở nửa dưới khung hình
    for (int y = startY + 1; y < endY - 1; y++) {
      double horizontalEdgeSum = 0.0;
      int continuousEdgeRun = 0;
      int maxContinuousEdgeRun = 0;
      int transitionCount = 0;
      bool currentlyInEdge = false;

      // Danh sách các điểm thuộc đoạn cạnh liên tục dài nhất
      int bestRunStartX = 0;
      int currentRunStartX = 0;

      for (int x = margin; x < width - margin; x++) {
        final int idx = y * width + x;

        final int gy =
            -grayBytes[idx - width - 1] - 2 * grayBytes[idx - width] - grayBytes[idx - width + 1] +
             grayBytes[idx + width - 1] + 2 * grayBytes[idx + width] + grayBytes[idx + width + 1];

        final int absGy = gy.abs();
        final bool isEdgePixel = (absGy > kEdgeThreshold * 4);

        if (isEdgePixel) {
          horizontalEdgeSum += absGy;
          if (continuousEdgeRun == 0) {
            currentRunStartX = x;
          }
          continuousEdgeRun++;

          if (continuousEdgeRun > maxContinuousEdgeRun) {
            maxContinuousEdgeRun = continuousEdgeRun;
            bestRunStartX = currentRunStartX;
          }

          if (!currentlyInEdge) {
            currentlyInEdge = true;
            transitionCount++;
          }
        } else {
          continuousEdgeRun = 0;
          currentlyInEdge = false;
        }
      }

      // LOẠI BỎ VẠCH QUA ĐƯỜNG (Zebra Crosswalk) & HOA VĂN GẠCH LÁT:
      // Vạch qua đường có nhiều sọc trắng/đen lặp lại đều đặn -> transitionCount cao
      if (transitionCount > kMaxCrosswalkTransitions) {
        continue;
      }

      // YÊU CẦU CẠNH LIÊN TỤC:
      // Mép bậc thềm thật phải là một đoạn liền mạch dài hơn ngưỡng (tối thiểu 35% chiều rộng ảnh)
      if (maxContinuousEdgeRun >= minContinuousPixels) {
        // KIỂM TRA TÍNH NHẤT QUÁN DỌC THEO CẠNH:
        // Đếm sự đồng nhất của độ chênh lệch sáng/tối trên/dưới bậc
        const int checkRange = 3;
        int stepDownCount = 0;
        int stepUpCount = 0;
        int validComparisons = 0;

        for (int x = bestRunStartX; x < bestRunStartX + maxContinuousEdgeRun; x++) {
          final int idxAbove = (y - checkRange) * width + x;
          final int idxBelow = (y + checkRange) * width + x;

          if (idxAbove >= 0 && idxBelow < grayBytes.length) {
            final int diff = grayBytes[idxAbove] - grayBytes[idxBelow];
            if (diff > 12) {
              stepDownCount++;
            } else if (diff < -12) {
              stepUpCount++;
            }
            validComparisons++;
          }
        }

        if (validComparisons > 0) {
          final int dominantCount = stepDownCount > stepUpCount ? stepDownCount : stepUpCount;
          final double consistency = dominantCount / validComparisons;

          // Phải đạt ngưỡng nhất quán tối thiểu (tránh bóng đổ loang lổ)
          if (consistency >= kStepConsistencyRatio) {
            rowEdgeStrength[y] = horizontalEdgeSum / maxContinuousEdgeRun;
            rowIsStepDown[y] = (stepDownCount >= stepUpCount);
            rowConsistency[y] = consistency;
          }
        }
      }
    }

    // 3. Tìm các đỉnh (Peaks) thể hiện mép bậc
    for (int y = startY + 2; y < endY - 2; y++) {
      if (rowEdgeStrength[y] > 180 &&
          rowEdgeStrength[y] > rowEdgeStrength[y - 1] &&
          rowEdgeStrength[y] > rowEdgeStrength[y + 1]) {

        final double normalizedY = y / height;
        final bool isStepDown = rowIsStepDown[y];
        final double consistency = rowConsistency[y];

        candidates.add(GroundHazard(
          type: isStepDown ? GroundHazardType.stepDown : GroundHazardType.stepUp,
          vietnameseName: isStepDown ? 'Bậc đi xuống / Mép lề' : 'Bậc tam cấp bước lên',
          normalizedY: normalizedY,
          confidence: (rowEdgeStrength[y] / 300.0 * consistency).clamp(0.0, 0.95),
          distanceLevel: normalizedY >= 0.78 ? DistanceLevel.critical : DistanceLevel.near,
          distanceMeters: normalizedY >= 0.78 ? '< 1.2m' : '1.5m - 2.5m',
          isNegativeObstacle: isStepDown,
        ));

        y += 6; // Bỏ qua vài dòng kế tiếp
      }
    }

    return _filterTemporalHazards(candidates);
  }

  /// Bộ lọc thời gian & Hạ mức cam kết cảnh báo
  List<GroundHazard> _filterTemporalHazards(List<GroundHazard> current) {
    _history.add(current);
    if (_history.length > kGroundHistorySize) {
      _history.removeAt(0);
    }

    if (current.isEmpty) return [];

    final List<GroundHazard> confirmed = [];
    for (final h in current) {
      int hitCount = 0;
      for (final pastList in _history) {
        if (pastList.any((p) =>
            (p.normalizedY - h.normalizedY).abs() < 0.08 && p.type == h.type)) {
          hitCount++;
        }
      }

      // 1. MỨC TIN CẬY CAO: Ổn định qua >= 5/8 frames
      if (hitCount >= kGroundHighConfidenceHits) {
        confirmed.add(h);
      }
      // 2. MỨC TIN CẬY TRUNG BÌNH: Ổn định qua 3 hoặc 4/8 frames
      // HẠ MỨC CAM KẾT: Đổi thành câu nhắc dùng gậy kiểm tra, không dùng rung critical
      else if (hitCount >= kGroundMediumConfidenceHits) {
        confirmed.add(GroundHazard(
          type: h.type,
          vietnameseName: 'Có thể có bậc, hãy dùng gậy kiểm tra',
          normalizedY: h.normalizedY,
          confidence: (h.confidence * 0.7).clamp(0.0, 0.75),
          distanceLevel: DistanceLevel.near, // Hạ cự ly xuống near, không dùng critical
          distanceMeters: h.distanceMeters,
          isNegativeObstacle: false, // Không đánh dấu negative obstacle để không kích hoạt rung/ngắt giọng khẩn cấp
        ));
      }
    }

    return confirmed;
  }

  /// Công cụ đo đạc kiểm chuẩn: Đếm số cảnh báo nhầm mỗi phút trên chuỗi ảnh đường phẳng
  double countFalseAlarmsPerMinute(List<Uint8List> sequence, int width, int height, {int fps = 20}) {
    reset();
    int falseAlarmCount = 0;

    for (final frame in sequence) {
      final hazards = analyzeLuminance(frame, width, height);
      if (hazards.isNotEmpty) {
        falseAlarmCount += hazards.length;
      }
    }

    final double totalMinutes = sequence.length / (fps * 60.0);
    if (totalMinutes <= 0) return 0.0;
    return falseAlarmCount / totalMinutes;
  }

  void reset() {
    _history.clear();
  }
}

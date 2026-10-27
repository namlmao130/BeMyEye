import 'dart:typed_data';

/// image_preprocessor.dart
/// Xử lý biến đổi và nắn chỉnh kích thước khung hình camera siêu tốc (Zero Allocation, LUT Optimized)
/// Chuyển đổi YUV420 -> RGB 300x300 (uint8) cho SSD MobileNet
/// và YUV420 -> Luma 160x120 (uint8) cho GroundPlaneAnalyzer
/// Xoay ảnh chính xác theo sensorOrientation của camera điện thoại gắn ngực.
///
/// TỐI ƯU HÓA HIỆU NĂNG CAO:
/// - Tiền tính toán bảng tra cứu tọa độ (Coordinate Lookup Table - LUT)
/// - Đưa hằng số dòng và phép tính UV ra ngoài vòng lặp trong
/// - Loại bỏ hoàn toàn phép chia nguyên (~/) và switch bên trong vòng lặp điểm ảnh
/// - Tái sử dụng bộ đệm (reusable buffers) để tránh Garbage Collection gây giật lag

class CameraFrameData {
  final Uint8List yPlane;
  final Uint8List? uPlane;
  final Uint8List? vPlane;
  final int yRowStride;
  final int uvRowStride;
  final int yPixelStride;
  final int uvPixelStride;
  final int width;
  final int height;
  final int sensorOrientation;

  CameraFrameData({
    required this.yPlane,
    this.uPlane,
    this.vPlane,
    required this.yRowStride,
    this.uvRowStride = 0,
    required this.yPixelStride,
    this.uvPixelStride = 1,
    required this.width,
    required this.height,
    required this.sensorOrientation,
  });
}

class PreprocessedFrame {
  final Uint8List rgb300;   // 300 x 300 x 3 = 270,000 bytes
  final Uint8List luma160;  // 160 x 120 = 19,200 bytes
  final int preprocessDurationMs;

  PreprocessedFrame({
    required this.rgb300,
    required this.luma160,
    required this.preprocessDurationMs,
  });
}

/// Hàm chuyển đổi tối ưu siêu tốc (chạy mượt mà trực tiếp trên mọi smartphone tầm trung)
PreprocessedFrame preprocessCameraFrame(
  CameraFrameData data, {
  Uint8List? reusableRgb300,
  Uint8List? reusableLuma160,
}) {
  final stopwatch = Stopwatch()..start();

  const int targetRgbW = 300;
  const int targetRgbH = 300;
  const int targetLumaW = 160;
  const int targetLumaH = 120;

  final Uint8List rgb300 = reusableRgb300 ?? Uint8List(targetRgbW * targetRgbH * 3);
  final Uint8List luma160 = reusableLuma160 ?? Uint8List(targetLumaW * targetLumaH);

  final int srcW = data.width;
  final int srcH = data.height;
  final int rotation = data.sensorOrientation;

  final Uint8List yPlane = data.yPlane;
  final Uint8List? uPlane = data.uPlane;
  final Uint8List? vPlane = data.vPlane;

  final int yLen = yPlane.length;
  final int uLen = uPlane?.length ?? 0;
  final int vLen = vPlane?.length ?? 0;

  final int yRowStride = data.yRowStride;
  final int uvRowStride = data.uvRowStride > 0 ? data.uvRowStride : (srcW >> 1);
  final int yPixelStride = data.yPixelStride > 0 ? data.yPixelStride : 1;
  final int uvPixelStride = data.uvPixelStride > 0 ? data.uvPixelStride : 1;

  final bool hasChroma = (uPlane != null && vPlane != null && uLen > 0 && vLen > 0);

  // 1. CHUYỂN ĐỔI YUV -> RGB 300x300 TỐI ƯU HÓA THEO GÓC QUAY
  if (rotation == 90) {
    // 90 ĐỘ (Phổ biến nhất trên 95% camera sau Android khi cầm/đeo dọc)
    // srcX phụ thuộc outY, srcY phụ thuộc outX
    final lutSrcX = Int32List(targetRgbH);
    for (int y = 0; y < targetRgbH; y++) {
      lutSrcX[y] = ((y * srcW) ~/ targetRgbH).clamp(0, srcW - 1);
    }
    final lutSrcY = Int32List(targetRgbW);
    for (int x = 0; x < targetRgbW; x++) {
      lutSrcY[x] = (((targetRgbW - 1 - x) * srcH) ~/ targetRgbW).clamp(0, srcH - 1);
    }

    int outIdx = 0;
    for (int outY = 0; outY < targetRgbH; outY++) {
      final int srcX = lutSrcX[outY];
      final int xOffset = srcX * yPixelStride;
      final int uvXOffset = (srcX >> 1) * uvPixelStride;

      if (hasChroma) {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcY = lutSrcY[outX];
          final int yIdx = srcY * yRowStride + xOffset;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;

          final int uvIdx = (srcY >> 1) * uvRowStride + uvXOffset;
          final int uDiff = ((uvIdx < uLen) ? uPlane![uvIdx] : 128) - 128;
          final int vDiff = ((uvIdx < vLen) ? vPlane![uvIdx] : 128) - 128;

          rgb300[outIdx++] = (yVal + ((359 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal - ((88 * uDiff + 183 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal + ((454 * uDiff) >> 8)).clamp(0, 255);
        }
      } else {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcY = lutSrcY[outX];
          final int yIdx = srcY * yRowStride + xOffset;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
        }
      }
    }
  } else if (rotation == 180) {
    // 180 ĐỘ
    final lutSrcX = Int32List(targetRgbW);
    for (int x = 0; x < targetRgbW; x++) {
      lutSrcX[x] = (((targetRgbW - 1 - x) * srcW) ~/ targetRgbW).clamp(0, srcW - 1);
    }
    final lutSrcY = Int32List(targetRgbH);
    for (int y = 0; y < targetRgbH; y++) {
      lutSrcY[y] = (((targetRgbH - 1 - y) * srcH) ~/ targetRgbH).clamp(0, srcH - 1);
    }

    int outIdx = 0;
    for (int outY = 0; outY < targetRgbH; outY++) {
      final int srcY = lutSrcY[outY];
      final int yRowOffset = srcY * yRowStride;
      final int uvRowOffset = (srcY >> 1) * uvRowStride;

      if (hasChroma) {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcX = lutSrcX[outX];
          final int yIdx = yRowOffset + srcX * yPixelStride;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;

          final int uvIdx = uvRowOffset + (srcX >> 1) * uvPixelStride;
          final int uDiff = ((uvIdx < uLen) ? uPlane![uvIdx] : 128) - 128;
          final int vDiff = ((uvIdx < vLen) ? vPlane![uvIdx] : 128) - 128;

          rgb300[outIdx++] = (yVal + ((359 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal - ((88 * uDiff + 183 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal + ((454 * uDiff) >> 8)).clamp(0, 255);
        }
      } else {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcX = lutSrcX[outX];
          final int yIdx = yRowOffset + srcX * yPixelStride;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
        }
      }
    }
  } else if (rotation == 270) {
    // 270 ĐỘ
    final lutSrcX = Int32List(targetRgbH);
    for (int y = 0; y < targetRgbH; y++) {
      lutSrcX[y] = (((targetRgbH - 1 - y) * srcW) ~/ targetRgbH).clamp(0, srcW - 1);
    }
    final lutSrcY = Int32List(targetRgbW);
    for (int x = 0; x < targetRgbW; x++) {
      lutSrcY[x] = ((x * srcH) ~/ targetRgbW).clamp(0, srcH - 1);
    }

    int outIdx = 0;
    for (int outY = 0; outY < targetRgbH; outY++) {
      final int srcX = lutSrcX[outY];
      final int xOffset = srcX * yPixelStride;
      final int uvXOffset = (srcX >> 1) * uvPixelStride;

      if (hasChroma) {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcY = lutSrcY[outX];
          final int yIdx = srcY * yRowStride + xOffset;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;

          final int uvIdx = (srcY >> 1) * uvRowStride + uvXOffset;
          final int uDiff = ((uvIdx < uLen) ? uPlane![uvIdx] : 128) - 128;
          final int vDiff = ((uvIdx < vLen) ? vPlane![uvIdx] : 128) - 128;

          rgb300[outIdx++] = (yVal + ((359 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal - ((88 * uDiff + 183 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal + ((454 * uDiff) >> 8)).clamp(0, 255);
        }
      } else {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcY = lutSrcY[outX];
          final int yIdx = srcY * yRowStride + xOffset;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
        }
      }
    }
  } else {
    // 0 ĐỘ
    final lutSrcX = Int32List(targetRgbW);
    for (int x = 0; x < targetRgbW; x++) {
      lutSrcX[x] = ((x * srcW) ~/ targetRgbW).clamp(0, srcW - 1);
    }
    final lutSrcY = Int32List(targetRgbH);
    for (int y = 0; y < targetRgbH; y++) {
      lutSrcY[y] = ((y * srcH) ~/ targetRgbH).clamp(0, srcH - 1);
    }

    int outIdx = 0;
    for (int outY = 0; outY < targetRgbH; outY++) {
      final int srcY = lutSrcY[outY];
      final int yRowOffset = srcY * yRowStride;
      final int uvRowOffset = (srcY >> 1) * uvRowStride;

      if (hasChroma) {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcX = lutSrcX[outX];
          final int yIdx = yRowOffset + srcX * yPixelStride;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;

          final int uvIdx = uvRowOffset + (srcX >> 1) * uvPixelStride;
          final int uDiff = ((uvIdx < uLen) ? uPlane![uvIdx] : 128) - 128;
          final int vDiff = ((uvIdx < vLen) ? vPlane![uvIdx] : 128) - 128;

          rgb300[outIdx++] = (yVal + ((359 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal - ((88 * uDiff + 183 * vDiff) >> 8)).clamp(0, 255);
          rgb300[outIdx++] = (yVal + ((454 * uDiff) >> 8)).clamp(0, 255);
        }
      } else {
        for (int outX = 0; outX < targetRgbW; outX++) {
          final int srcX = lutSrcX[outX];
          final int yIdx = yRowOffset + srcX * yPixelStride;
          final int yVal = (yIdx < yLen) ? yPlane[yIdx] : 0;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
          rgb300[outIdx++] = yVal;
        }
      }
    }
  }

  // 2. CHUYỂN ĐỔI SANG LUMA 160x120 CHO GROUND PLANE ANALYZER
  if (rotation == 90) {
    final lutLumaX = Int32List(targetLumaH);
    for (int y = 0; y < targetLumaH; y++) {
      lutLumaX[y] = ((y * srcW) ~/ targetLumaH).clamp(0, srcW - 1);
    }
    final lutLumaY = Int32List(targetLumaW);
    for (int x = 0; x < targetLumaW; x++) {
      lutLumaY[x] = (((targetLumaW - 1 - x) * srcH) ~/ targetLumaW).clamp(0, srcH - 1);
    }

    int outLumaIdx = 0;
    for (int outY = 0; outY < targetLumaH; outY++) {
      final int srcX = lutLumaX[outY];
      final int xOffset = srcX * yPixelStride;
      for (int outX = 0; outX < targetLumaW; outX++) {
        final int srcY = lutLumaY[outX];
        final int yIdx = srcY * yRowStride + xOffset;
        luma160[outLumaIdx++] = (yIdx < yLen) ? yPlane[yIdx] : 0;
      }
    }
  } else if (rotation == 180) {
    final lutLumaX = Int32List(targetLumaW);
    for (int x = 0; x < targetLumaW; x++) {
      lutLumaX[x] = (((targetLumaW - 1 - x) * srcW) ~/ targetLumaW).clamp(0, srcW - 1);
    }
    final lutLumaY = Int32List(targetLumaH);
    for (int y = 0; y < targetLumaH; y++) {
      lutLumaY[y] = (((targetLumaH - 1 - y) * srcH) ~/ targetLumaH).clamp(0, srcH - 1);
    }

    int outLumaIdx = 0;
    for (int outY = 0; outY < targetLumaH; outY++) {
      final int yRowOffset = lutLumaY[outY] * yRowStride;
      for (int outX = 0; outX < targetLumaW; outX++) {
        final int yIdx = yRowOffset + lutLumaX[outX] * yPixelStride;
        luma160[outLumaIdx++] = (yIdx < yLen) ? yPlane[yIdx] : 0;
      }
    }
  } else if (rotation == 270) {
    final lutLumaX = Int32List(targetLumaH);
    for (int y = 0; y < targetLumaH; y++) {
      lutLumaX[y] = (((targetLumaH - 1 - y) * srcW) ~/ targetLumaH).clamp(0, srcW - 1);
    }
    final lutLumaY = Int32List(targetLumaW);
    for (int x = 0; x < targetLumaW; x++) {
      lutLumaY[x] = ((x * srcH) ~/ targetLumaW).clamp(0, srcH - 1);
    }

    int outLumaIdx = 0;
    for (int outY = 0; outY < targetLumaH; outY++) {
      final int srcX = lutLumaX[outY];
      final int xOffset = srcX * yPixelStride;
      for (int outX = 0; outX < targetLumaW; outX++) {
        final int srcY = lutLumaY[outX];
        final int yIdx = srcY * yRowStride + xOffset;
        luma160[outLumaIdx++] = (yIdx < yLen) ? yPlane[yIdx] : 0;
      }
    }
  } else {
    // 0 ĐỘ
    final lutLumaX = Int32List(targetLumaW);
    for (int x = 0; x < targetLumaW; x++) {
      lutLumaX[x] = ((x * srcW) ~/ targetLumaW).clamp(0, srcW - 1);
    }
    final lutLumaY = Int32List(targetLumaH);
    for (int y = 0; y < targetLumaH; y++) {
      lutLumaY[y] = ((y * srcH) ~/ targetLumaH).clamp(0, srcH - 1);
    }

    int outLumaIdx = 0;
    for (int outY = 0; outY < targetLumaH; outY++) {
      final int yRowOffset = lutLumaY[outY] * yRowStride;
      for (int outX = 0; outX < targetLumaW; outX++) {
        final int yIdx = yRowOffset + lutLumaX[outX] * yPixelStride;
        luma160[outLumaIdx++] = (yIdx < yLen) ? yPlane[yIdx] : 0;
      }
    }
  }

  stopwatch.stop();

  return PreprocessedFrame(
    rgb300: rgb300,
    luma160: luma160,
    preprocessDurationMs: stopwatch.elapsedMilliseconds,
  );
}

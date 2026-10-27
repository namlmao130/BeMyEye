import 'dart:typed_data';

/// image_preprocessor.dart
/// Xử lý biến đổi và nắn chỉnh kích thước khung hình camera trong Isolate
/// Chuyển đổi YUV420 -> RGB 300x300 (uint8) cho SSD MobileNet
/// và YUV420 -> Luma 160x120 (uint8) cho GroundPlaneAnalyzer
/// Xoay ảnh chính xác theo sensorOrientation của camera điện thoại gắn ngực.

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

/// Hàm chuyển đổi chạy độc lập trong Isolate (không chặn UI thread)
PreprocessedFrame preprocessCameraFrame(CameraFrameData data) {
  final stopwatch = Stopwatch()..start();

  const int targetRgbW = 300;
  const int targetRgbH = 300;
  const int targetLumaW = 160;
  const int targetLumaH = 120;

  final Uint8List rgb300 = Uint8List(targetRgbW * targetRgbH * 3);
  final Uint8List luma160 = Uint8List(targetLumaW * targetLumaH);

  final int srcW = data.width;
  final int srcH = data.height;
  final int rotation = data.sensorOrientation;

  final Uint8List yPlane = data.yPlane;
  final Uint8List? uPlane = data.uPlane;
  final Uint8List? vPlane = data.vPlane;

  final int yRowStride = data.yRowStride;
  final int uvRowStride = data.uvRowStride > 0 ? data.uvRowStride : (srcW >> 1);
  final int yPixelStride = data.yPixelStride > 0 ? data.yPixelStride : 1;
  final int uvPixelStride = data.uvPixelStride > 0 ? data.uvPixelStride : 1;

  final bool hasChroma = (uPlane != null && vPlane != null && uPlane.isNotEmpty && vPlane.isNotEmpty);

  // 1. Chuyển đổi sang RGB 300x300
  for (int outY = 0; outY < targetRgbH; outY++) {
    for (int outX = 0; outX < targetRgbW; outX++) {
      // Ánh xạ tọa độ dựa trên góc quay sensorOrientation
      int srcX;
      int srcY;

      switch (rotation) {
        case 90:
          srcX = ((outY * srcW) ~/ targetRgbH).clamp(0, srcW - 1);
          srcY = (((targetRgbW - 1 - outX) * srcH) ~/ targetRgbW).clamp(0, srcH - 1);
          break;
        case 180:
          srcX = (((targetRgbW - 1 - outX) * srcW) ~/ targetRgbW).clamp(0, srcW - 1);
          srcY = (((targetRgbH - 1 - outY) * srcH) ~/ targetRgbH).clamp(0, srcH - 1);
          break;
        case 270:
          srcX = (((targetRgbH - 1 - outY) * srcW) ~/ targetRgbH).clamp(0, srcW - 1);
          srcY = ((outX * srcH) ~/ targetRgbW).clamp(0, srcH - 1);
          break;
        case 0:
        default:
          srcX = ((outX * srcW) ~/ targetRgbW).clamp(0, srcW - 1);
          srcY = ((outY * srcH) ~/ targetRgbH).clamp(0, srcH - 1);
          break;
      }

      final int yIdx = srcY * yRowStride + srcX * yPixelStride;
      final int yVal = (yIdx < yPlane.length) ? yPlane[yIdx] : 0;

      int r;
      int g;
      int b;

      if (hasChroma) {
        final int uvX = srcX >> 1;
        final int uvY = srcY >> 1;
        final int uIdx = uvY * uvRowStride + uvX * uvPixelStride;
        final int vIdx = uvY * uvRowStride + uvX * uvPixelStride;

        final int uVal = (uIdx < uPlane.length) ? uPlane[uIdx] : 128;
        final int vVal = (vIdx < vPlane.length) ? vPlane[vIdx] : 128;

        // Công thức biến đổi BT.601 tối ưu với phép dịch bit
        final int uDiff = uVal - 128;
        final int vDiff = vVal - 128;

        r = (yVal + ((359 * vDiff) >> 8)).clamp(0, 255);
        g = (yVal - ((88 * uDiff + 183 * vDiff) >> 8)).clamp(0, 255);
        b = (yVal + ((454 * uDiff) >> 8)).clamp(0, 255);
      } else {
        // Fallback đơn sắc (Grayscale)
        r = yVal;
        g = yVal;
        b = yVal;
      }

      final int outIdx = (outY * targetRgbW + outX) * 3;
      rgb300[outIdx] = r;
      rgb300[outIdx + 1] = g;
      rgb300[outIdx + 2] = b;
    }
  }

  // 2. Chuyển đổi sang Luma 160x120 cho GroundPlaneAnalyzer
  for (int outY = 0; outY < targetLumaH; outY++) {
    for (int outX = 0; outX < targetLumaW; outX++) {
      int srcX;
      int srcY;

      switch (rotation) {
        case 90:
          srcX = ((outY * srcW) ~/ targetLumaH).clamp(0, srcW - 1);
          srcY = (((targetLumaW - 1 - outX) * srcH) ~/ targetLumaW).clamp(0, srcH - 1);
          break;
        case 180:
          srcX = (((targetLumaW - 1 - outX) * srcW) ~/ targetLumaW).clamp(0, srcW - 1);
          srcY = (((targetLumaH - 1 - outY) * srcH) ~/ targetLumaH).clamp(0, srcH - 1);
          break;
        case 270:
          srcX = (((targetLumaH - 1 - outY) * srcW) ~/ targetLumaH).clamp(0, srcW - 1);
          srcY = ((outX * srcH) ~/ targetLumaW).clamp(0, srcH - 1);
          break;
        case 0:
        default:
          srcX = ((outX * srcW) ~/ targetLumaW).clamp(0, srcW - 1);
          srcY = ((outY * srcH) ~/ targetLumaH).clamp(0, srcH - 1);
          break;
      }

      final int yIdx = srcY * yRowStride + srcX * yPixelStride;
      luma160[outY * targetLumaW + outX] = (yIdx < yPlane.length) ? yPlane[yIdx] : 0;
    }
  }

  stopwatch.stop();

  return PreprocessedFrame(
    rgb300: rgb300,
    luma160: luma160,
    preprocessDurationMs: stopwatch.elapsedMilliseconds,
  );
}

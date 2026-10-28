import 'dart:typed_data';

/// Camera plane data is borrowed only for synchronous processing of the callback.
class CameraFrameData {
  final Uint8List yPlane;
  final Uint8List? uPlane;
  final Uint8List? vPlane;
  final int yRowStride;
  final int uvRowStride;
  final int yPixelStride;
  final int uvPixelStride;
  final int? vRowStride;
  final int? vPixelStride;
  final int width;
  final int height;
  final int sensorOrientation;
  final bool isBgra;

  CameraFrameData({
    required this.yPlane,
    this.uPlane,
    this.vPlane,
    required this.yRowStride,
    this.uvRowStride = 0,
    required this.yPixelStride,
    this.uvPixelStride = 1,
    this.vRowStride,
    this.vPixelStride,
    required this.width,
    required this.height,
    required this.sensorOrientation,
    this.isBgra = false,
  });
}

class PreprocessedFrame {
  final Uint8List rgb300;
  final Uint8List luma160;
  final int preprocessDurationMs;

  PreprocessedFrame({
    required this.rgb300,
    required this.luma160,
    required this.preprocessDurationMs,
  });
}

/// One camera geometry is active at a time. Cache offsets across frames, including
/// row padding, chroma pixel stride, and rotation; no LUT arrays per video frame.
_SamplingMap? _cachedMap;

class _SamplingMap {
  final int width, height, rotation, yRow, yPixel, uRow, uPixel, vRow, vPixel;
  final Int32List rgbY = Int32List(300 * 300);
  final Int32List rgbU = Int32List(300 * 300);
  final Int32List rgbV = Int32List(300 * 300);
  final Int32List lumaY = Int32List(160 * 120);

  _SamplingMap(CameraFrameData data)
      : width = data.width,
        height = data.height,
        rotation = data.sensorOrientation,
        yRow = data.yRowStride,
        yPixel = data.isBgra ? 4 : data.yPixelStride,
        uRow = data.uvRowStride > 0 ? data.uvRowStride : (data.width + 1) ~/ 2,
        uPixel = data.uvPixelStride,
        vRow = data.vRowStride ??
            (data.uvRowStride > 0 ? data.uvRowStride : (data.width + 1) ~/ 2),
        vPixel = data.vPixelStride ?? data.uvPixelStride {
    _fill(rgbY, 300, 300, chroma: true);
    _fill(lumaY, 160, 120, chroma: false);
  }

  bool matches(CameraFrameData data) =>
      width == data.width &&
      height == data.height &&
      rotation == data.sensorOrientation &&
      yRow == data.yRowStride &&
      yPixel == (data.isBgra ? 4 : data.yPixelStride) &&
      uRow ==
          (data.uvRowStride > 0 ? data.uvRowStride : (data.width + 1) ~/ 2) &&
      uPixel == data.uvPixelStride &&
      vRow ==
          (data.vRowStride ??
              (data.uvRowStride > 0
                  ? data.uvRowStride
                  : (data.width + 1) ~/ 2)) &&
      vPixel == (data.vPixelStride ?? data.uvPixelStride);

  void _fill(
    Int32List destination,
    int outWidth,
    int outHeight, {
    required bool chroma,
  }) {
    var index = 0;
    for (var y = 0; y < outHeight; y++) {
      for (var x = 0; x < outWidth; x++) {
        final int sourceX;
        final int sourceY;
        switch (rotation) {
          case 90:
            sourceX = y * width ~/ outHeight;
            sourceY = (outWidth - 1 - x) * height ~/ outWidth;
            break;
          case 180:
            sourceX = (outWidth - 1 - x) * width ~/ outWidth;
            sourceY = (outHeight - 1 - y) * height ~/ outHeight;
            break;
          case 270:
            sourceX = (outHeight - 1 - y) * width ~/ outHeight;
            sourceY = x * height ~/ outWidth;
            break;
          default:
            sourceX = x * width ~/ outWidth;
            sourceY = y * height ~/ outHeight;
        }
        destination[index] = sourceY * yRow + sourceX * yPixel;
        if (chroma) {
          rgbU[index] = (sourceY >> 1) * uRow + (sourceX >> 1) * uPixel;
          rgbV[index] = (sourceY >> 1) * vRow + (sourceX >> 1) * vPixel;
        }
        index++;
      }
    }
  }
}

void _validatePlane(
  Uint8List plane,
  int width,
  int height,
  int rowStride,
  int pixelStride, {
  int bytesPerPixel = 1,
}) {
  if (rowStride <= 0 ||
      pixelStride <= 0 ||
      rowStride < (width - 1) * pixelStride + bytesPerPixel ||
      plane.length <
          (height - 1) * rowStride +
              (width - 1) * pixelStride +
              bytesPerPixel) {
    throw ArgumentError(
      'Camera plane bị thiếu dữ liệu hoặc stride không hợp lệ',
    );
  }
}

int _saturate(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

PreprocessedFrame preprocessCameraFrame(
  CameraFrameData data, {
  Uint8List? reusableRgb300,
  Uint8List? reusableLuma160,
}) {
  final stopwatch = Stopwatch()..start();
  if (data.width <= 0 ||
      data.height <= 0 ||
      !const [0, 90, 180, 270].contains(data.sensorOrientation)) {
    throw ArgumentError('Kích thước hoặc góc xoay camera không hợp lệ');
  }
  if ((reusableRgb300 != null && reusableRgb300.length != 300 * 300 * 3) ||
      (reusableLuma160 != null && reusableLuma160.length != 160 * 120)) {
    throw ArgumentError('Kích thước bộ đệm ảnh không hợp lệ');
  }
  _validatePlane(
    data.yPlane,
    data.width,
    data.height,
    data.yRowStride,
    data.isBgra ? 4 : data.yPixelStride,
    bytesPerPixel: data.isBgra ? 4 : 1,
  );
  final hasChroma = data.uPlane != null || data.vPlane != null;
  if (hasChroma &&
      (data.isBgra || data.uPlane == null || data.vPlane == null)) {
    throw ArgumentError('Camera YUV cần đủ cả hai plane U và V');
  }
  final uvWidth = (data.width + 1) ~/ 2;
  final uvHeight = (data.height + 1) ~/ 2;
  final uvRow = data.uvRowStride > 0 ? data.uvRowStride : uvWidth;
  if (hasChroma) {
    _validatePlane(data.uPlane!, uvWidth, uvHeight, uvRow, data.uvPixelStride);
    _validatePlane(
      data.vPlane!,
      uvWidth,
      uvHeight,
      data.vRowStride ?? uvRow,
      data.vPixelStride ?? data.uvPixelStride,
    );
  }
  final map = _cachedMap != null && _cachedMap!.matches(data)
      ? _cachedMap!
      : (_cachedMap = _SamplingMap(data));
  final rgb = reusableRgb300 ?? Uint8List(300 * 300 * 3);
  final luma = reusableLuma160 ?? Uint8List(160 * 120);
  final input = data.yPlane;
  var output = 0;
  if (data.isBgra) {
    for (var i = 0; i < map.rgbY.length; i++) {
      final offset = map.rgbY[i];
      rgb[output++] = input[offset + 2];
      rgb[output++] = input[offset + 1];
      rgb[output++] = input[offset];
    }
    for (var i = 0; i < map.lumaY.length; i++) {
      final offset = map.lumaY[i];
      luma[i] = (77 * input[offset + 2] +
              150 * input[offset + 1] +
              29 * input[offset]) >>
          8;
    }
  } else {
    if (hasChroma) {
      final u = data.uPlane!;
      final v = data.vPlane!;
      for (var i = 0; i < map.rgbY.length; i++) {
        final y = input[map.rgbY[i]];
        final ud = u[map.rgbU[i]] - 128;
        final vd = v[map.rgbV[i]] - 128;
        rgb[output++] = _saturate(y + ((359 * vd) >> 8));
        rgb[output++] = _saturate(y - ((88 * ud + 183 * vd) >> 8));
        rgb[output++] = _saturate(y + ((454 * ud) >> 8));
      }
    } else {
      for (var i = 0; i < map.rgbY.length; i++) {
        final y = input[map.rgbY[i]];
        rgb[output++] = y;
        rgb[output++] = y;
        rgb[output++] = y;
      }
    }
    for (var i = 0; i < map.lumaY.length; i++) {
      luma[i] = input[map.lumaY[i]];
    }
  }
  stopwatch.stop();
  return PreprocessedFrame(
    rgb300: rgb,
    luma160: luma,
    preprocessDurationMs: stopwatch.elapsedMilliseconds,
  );
}

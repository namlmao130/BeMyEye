import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../config/thresholds.dart';

/// detector_service.dart
/// Quản lý nạp mô hình TensorFlow Lite on-device (SSD MobileNet)
/// Tự động lựa chọn Hardware Acceleration Delegate (GPU -> NNAPI -> CPU)
/// Đảm bảo nguyên tắc An toàn: Báo lỗi to và khóa dẫn đường nếu không nạp được mô hình.

typedef AssetStringLoader = Future<String> Function(String path);
typedef InterpreterCreator = Future<Interpreter> Function(
  String assetName, {
  InterpreterOptions? options,
});

class DetectorService {
  final AssetStringLoader _stringLoader;
  final InterpreterCreator _interpreterCreator;

  Interpreter? _interpreter;
  bool _isLoaded = false;
  String? loadError;
  String activeDelegate = 'CPU';
  List<String> _labels = [];
  double confidenceThreshold = kDefaultConfidenceThreshold;

  // Tái sử dụng bộ đệm TFLite Output Tensors để loại bỏ 100% cấp phát heap mỗi khung hình
  final List<List<List<double>>> _outputBoxes = List.generate(
    1,
    (_) => List.generate(10, (_) => List.filled(4, 0.0)),
  );
  final List<List<double>> _outputClasses = List.generate(1, (_) => List.filled(10, 0.0));
  final List<List<double>> _outputScores = List.generate(1, (_) => List.filled(10, 0.0));
  final List<double> _numDetections = List.filled(1, 0.0);
  late final Map<int, Object> _outputs = <int, Object>{
    0: _outputBoxes,
    1: _outputClasses,
    2: _outputScores,
    3: _numDetections,
  };

  // Bản đồ nhãn tiếng Việt & Phân loại đối tượng đường phố Việt Nam (đồng bộ hoàn toàn với bản web)
  static const Map<String, Map<String, dynamic>> classMappings = {
    // Phương tiện giao thông (Mức độ ưu tiên cao nhất)
    'motorcycle': {'vi': 'Xe máy', 'category': 'vehicle', 'priority': 1},
    'car': {'vi': 'Ô tô', 'category': 'vehicle', 'priority': 2},
    'bicycle': {'vi': 'Xe đạp', 'category': 'vehicle', 'priority': 3},
    'bus': {'vi': 'Xe buýt', 'category': 'vehicle', 'priority': 1},
    'truck': {'vi': 'Xe tải', 'category': 'vehicle', 'priority': 1},

    // Người đi bộ
    'person': {'vi': 'Người', 'category': 'pedestrian', 'priority': 4},

    // Vật cản tĩnh chiếm lối đi thường gặp trên đường phố Việt Nam
    'chair': {'vi': 'Ghế quán cóc', 'category': 'obstacle', 'priority': 5},
    'bench': {'vi': 'Ghế dài', 'category': 'obstacle', 'priority': 5},
    'potted plant': {'vi': 'Chậu cây', 'category': 'obstacle', 'priority': 6},
    'fire hydrant': {'vi': 'Trụ nước', 'category': 'obstacle', 'priority': 5},
    'stop sign': {'vi': 'Biển báo', 'category': 'obstacle', 'priority': 5},
    'traffic light': {'vi': 'Đèn giao thông', 'category': 'obstacle', 'priority': 6},
    'umbrella': {'vi': 'Dù bạt che', 'category': 'obstacle', 'priority': 4},

    // Động vật
    'dog': {'vi': 'Chó', 'category': 'animal', 'priority': 3},
    'cat': {'vi': 'Mèo', 'category': 'animal', 'priority': 7},
  };

  DetectorService({
    AssetStringLoader? stringLoader,
    InterpreterCreator? interpreterCreator,
  })  : _stringLoader = stringLoader ?? rootBundle.loadString,
        _interpreterCreator = interpreterCreator ?? Interpreter.fromAsset;

  bool get isLoaded => _isLoaded;
  bool get isReady => _isLoaded && loadError == null && _interpreter != null;
  List<String> get labels => List.unmodifiable(_labels);

  /// Tách danh sách nhãn từ nội dung file text
  static List<String> parseLabels(String content) {
    return const LineSplitter()
        .convert(content)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Kiểm tra cấu trúc Output Tensors của SSD MobileNet:
  /// Yêu cầu 4 tensors:
  /// 0: boxes [1, N, 4]
  /// 1: classes [1, N]
  /// 2: scores [1, N]
  /// 3: count [1]
  static bool validateOutputTensors(List<Tensor> tensors) {
    if (tensors.length < 4) return false;

    final boxesShape = tensors[0].shape;
    final classesShape = tensors[1].shape;
    final scoresShape = tensors[2].shape;
    final countShape = tensors[3].shape;

    // Tensor 0: [1, N, 4]
    if (boxesShape.length != 3 || boxesShape[0] != 1 || boxesShape[2] != 4) {
      return false;
    }
    // Tensor 1: [1, N]
    if (classesShape.length != 2 || classesShape[0] != 1) {
      return false;
    }
    // Tensor 2: [1, N]
    if (scoresShape.length != 2 || scoresShape[0] != 1) {
      return false;
    }
    // Tensor 3: [1]
    if (countShape.isEmpty || (countShape.length == 1 && countShape[0] != 1)) {
      return false;
    }

    return true;
  }

  /// Nạp nhãn labelmap và khởi tạo mô hình TFLite với hardware delegates
  Future<void> loadModel({
    String labelPath = 'assets/models/labelmap.txt',
    String modelPath = 'assets/models/mobilenet_ssd.tflite',
  }) async {
    _isLoaded = false;
    loadError = null;
    activeDelegate = 'CPU';
    _labels = [];

    // 1. Nạp và kiểm tra tính toàn vẹn của labelmap (91 nhãn COCO SSD)
    try {
      final labelData = await _stringLoader(labelPath);
      final parsedLabels = parseLabels(labelData);
      if (parsedLabels.length != 91) {
        throw FormatException(
          'Số lượng nhãn trong $labelPath không đúng: ${parsedLabels.length} (yêu cầu 91 dòng nhãn COCO SSD)',
        );
      }
      _labels = parsedLabels;
    } catch (e) {
      loadError = 'Lỗi nạp labelmap: $e';
      _isLoaded = false;
      activeDelegate = 'LỖI';
      return;
    }

    // 2. Thử nạp mô hình với NNAPI / GPU / XNNPack, tự động quay về CPU khi lỗi
    Interpreter? interpreter;
    String selectedDelegate = 'CPU';

    if (Platform.isAndroid) {
      // Ưu tiên 1 trên Android: NNAPI (Neural Networks API cho NPU/DSP phần cứng)
      try {
        final nnapiOptions = InterpreterOptions()
          ..threads = 2
          ..useNnApiForAndroid = true;
        interpreter = await _interpreterCreator(modelPath, options: nnapiOptions);
        selectedDelegate = 'NNAPI';
      } catch (_) {
        interpreter = null;
      }

      // Ưu tiên 2: Thử GPU Delegate nếu NNAPI không tương thích
      if (interpreter == null) {
        try {
          final gpuOptions = InterpreterOptions()..threads = 2;
          try {
            gpuOptions.addDelegate(GpuDelegateV2());
            interpreter = await _interpreterCreator(modelPath, options: gpuOptions);
            selectedDelegate = 'GPU';
          } catch (_) {
            interpreter = null;
          }
        } catch (_) {
          interpreter = null;
        }
      }

      // Ưu tiên 3: Thử XNNPack Delegate
      if (interpreter == null) {
        try {
          final xnnOptions = InterpreterOptions()..threads = 2;
          xnnOptions.addDelegate(XNNPackDelegate());
          interpreter = await _interpreterCreator(modelPath, options: xnnOptions);
          selectedDelegate = 'XNNPACK';
        } catch (_) {
          interpreter = null;
        }
      }
    } else if (Platform.isIOS) {
      try {
        final iosOptions = InterpreterOptions()
          ..threads = 2
          ..useMetalDelegateForIOS = true;
        interpreter = await _interpreterCreator(modelPath, options: iosOptions);
        selectedDelegate = 'METAL';
      } catch (_) {
        try {
          final gpuOptions = InterpreterOptions()..threads = 2;
          gpuOptions.addDelegate(GpuDelegate());
          interpreter = await _interpreterCreator(modelPath, options: gpuOptions);
          selectedDelegate = 'GPU';
        } catch (_) {
          interpreter = null;
        }
      }
    }

    // Fallback về CPU tối ưu 2 luồng (tránh tranh chấp lõi nhỏ trên chip kiến trúc big.LITTLE)
    if (interpreter == null) {
      try {
        final cpuOptions = InterpreterOptions()..threads = 2;
        interpreter = await _interpreterCreator(modelPath, options: cpuOptions);
        selectedDelegate = 'CPU';
      } catch (e) {
        loadError = 'Không thể nạp mô hình TFLite ($modelPath): $e';
        _isLoaded = false;
        activeDelegate = 'LỖI';
        return;
      }
    }

    // 3. Kiểm tra Output Tensors
    try {
      final outputs = interpreter.getOutputTensors();
      if (!validateOutputTensors(outputs)) {
        interpreter.close();
        loadError =
            'Mô hình không đúng cấu trúc SSD MobileNet (cần 4 tensor: boxes, classes, scores, count)';
        _isLoaded = false;
        activeDelegate = 'LỖI';
        return;
      }
    } catch (e) {
      interpreter.close();
      loadError = 'Lỗi kiểm tra tensor mô hình: $e';
      _isLoaded = false;
      activeDelegate = 'LỖI';
      return;
    }

    _interpreter = interpreter;
    activeDelegate = selectedDelegate;
    _isLoaded = true;
    loadError = null;
  }

  /// Xử lý và lọc kết quả dự đoán thô từ SSD MobileNet
  List<Map<String, dynamic>> parsePredictions({
    required List<List<double>> rawBoxes,
    required List<double> rawClasses,
    required List<double> rawScores,
    required int count,
    required int imageWidth,
    required int imageHeight,
  }) {
    final List<Map<String, dynamic>> results = [];
    final limit = count.clamp(0, rawScores.length);

    for (int i = 0; i < limit; i++) {
      final score = rawScores[i];
      // Áp dụng confidenceThreshold thực tế
      if (score < confidenceThreshold) continue;

      final classIndex = rawClasses[i].toInt();
      // Áp dụng kLabelOffset = 1 (NV12.1): Mô hình SSD MobileNet đánh số từ 0 (0: person)
      // trong khi labelmap.txt có dòng đầu tiên là "???" (index 0).
      final effectiveIndex = classIndex + kLabelOffset;
      if (classIndex < 0 || effectiveIndex < 0 || effectiveIndex >= _labels.length) continue;

      final label = _labels[effectiveIndex].toLowerCase();
      if (label == '???' || label.isEmpty) continue;

      final mapping = classMappings[label];
      if (mapping == null) continue;

      // rawBoxes[i] là [ymin, xmin, ymax, xmax] tỷ lệ chuẩn hóa 0.0 -> 1.0
      final ymin = rawBoxes[i][0].clamp(0.0, 1.0);
      final xmin = rawBoxes[i][1].clamp(0.0, 1.0);
      final ymax = rawBoxes[i][2].clamp(0.0, 1.0);
      final xmax = rawBoxes[i][3].clamp(0.0, 1.0);

      final x = xmin * imageWidth;
      final y = ymin * imageHeight;
      final w = (xmax - xmin).clamp(0.0, 1.0) * imageWidth;
      final h = (ymax - ymin).clamp(0.0, 1.0) * imageHeight;

      results.add({
        'class': label,
        'label': label,
        'vietnameseClass': mapping['vi'],
        'vietnameseLabel': mapping['vi'],
        'category': mapping['category'],
        'priority': mapping['priority'],
        'score': score,
        'bbox': [x, y, w, h], // Định dạng [x, y, width, height] pixel cho SpatialAnalyzer
      });
    }

    // Sắp xếp theo mức độ ưu tiên nguy hiểm (priority nhỏ hơn = nguy hiểm hơn)
    results.sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));
    return results;
  }

  /// Suy luận nhận diện vật thể từ khung hình camera (Tái sử dụng bộ đệm, Zero GC Allocation)
  List<Map<String, dynamic>> detectFromImage(
    Uint8List imageBytes,
    int width,
    int height,
  ) {
    if (!isReady || _interpreter == null) {
      return [];
    }

    try {
      _interpreter!.runForMultipleInputs([imageBytes], _outputs);

      return parsePredictions(
        rawBoxes: _outputBoxes[0],
        rawClasses: _outputClasses[0],
        rawScores: _outputScores[0],
        count: _numDetections[0].toInt(),
        imageWidth: width,
        imageHeight: height,
      );
    } catch (e) {
      return [];
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}

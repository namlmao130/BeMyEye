import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../models/detection_result.dart';
import '../models/ground_hazard.dart';
import 'detector_service.dart';
import 'spatial_analyzer.dart';
import 'ground_analyzer.dart';
import 'alert_decision_engine.dart';
import 'battery_optimizer.dart';
import 'csv_logger.dart';
import 'image_preprocessor.dart';
import 'tilt_calibration_service.dart';
import 'device_health_service.dart';

/// camera_pipeline_service.dart
/// Trực tiếp điều khiển luồng Camera thời gian thực, điều tiết khung hình,
/// tiền xử lý ảnh trong Isolate, và điều phối chuỗi suy luận -> phân tích -> cảnh báo.

class CameraPipelineService {
  final DetectorService detectorService;
  final SpatialAnalyzer spatialAnalyzer;
  final GroundPlaneAnalyzer groundAnalyzer;
  final AlertDecisionEngine alertEngine;
  final BatteryThermalOptimizer batteryOptimizer;
  final CsvLogger csvLogger;
  final TiltCalibrationService? tiltService;
  final DeviceHealthService? healthService;

  CameraController? _cameraController;
  CameraController? get controller => _cameraController;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  bool _isProcessingFrame = false;

  // Chỉ số hiệu năng thời gian thực (được tính toán thực sự từ luồng ảnh)
  double currentFps = 0.0;
  int latencyPreprocessMs = 0;
  int latencyInferenceMs = 0;
  int latencyAnalysisMs = 0;
  int latencyTotalMs = 0;

  List<DetectionResult> latestDetections = [];
  List<GroundHazard> latestGroundHazards = [];
  List<GroundHazard> _cachedGroundHazards = [];
  AlertCandidate? currentThreat;

  VoidCallback? onFrameProcessed;

  // Bộ tính toán Rolling FPS
  int _frameCount = 0;
  int _lastFpsCalcTime = 0;

  CameraPipelineService({
    required this.detectorService,
    required this.spatialAnalyzer,
    required this.groundAnalyzer,
    required this.alertEngine,
    required this.batteryOptimizer,
    required this.csvLogger,
    this.tiltService,
    this.healthService,
  });

  /// Khởi tạo camera với cấu hình tối ưu độ trễ và năng lượng
  Future<void> initializeCamera({CameraDescription? customCamera}) async {
    try {
      CameraDescription? targetCamera = customCamera;
      if (targetCamera == null) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          debugPrint('Không tìm thấy camera trên thiết bị (hoặc đang chạy giả lập)');
          return;
        }
        // Ưu tiên camera sau (Back Camera)
        targetCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
      }

      final controller = CameraController(
        targetCamera,
        ResolutionPreset.medium, // 720p/480p: Đảm bảo cân bằng giữa chi tiết và độ trễ
        enableAudio: false,       // Tắt mic trong luồng camera để tiết kiệm tài nguyên
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      _cameraController = controller;
      _isInitialized = true;
    } catch (e) {
      debugPrint('Lỗi khởi tạo CameraController: $e');
      _isInitialized = false;
    }
  }

  /// Bắt đầu stream camera và kích hoạt pipeline
  Future<void> startStream() async {
    if (!_isInitialized || _cameraController == null) {
      await initializeCamera();
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      debugPrint('Không thể bật camera stream: Camera chưa sẵn sàng');
      return;
    }

    if (_isStreaming) return;

    _frameCount = 0;
    _lastFpsCalcTime = DateTime.now().millisecondsSinceEpoch;
    _isProcessingFrame = false;
    _isStreaming = true;

    try {
      await _cameraController!.startImageStream(_handleCameraImage);
    } catch (e) {
      debugPrint('Lỗi startImageStream: $e');
      _isStreaming = false;
    }
  }

  /// Dừng stream camera
  Future<void> stopStream() async {
    if (!_isStreaming || _cameraController == null) return;

    try {
      _isStreaming = false;
      await _cameraController!.stopImageStream();
    } catch (e) {
      debugPrint('Lỗi stopImageStream: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Xử lý từng khung hình từ CameraStream (Non-blocking, Frame-dropping)
  void _handleCameraImage(CameraImage image) {
    if (!_isStreaming || !detectorService.isReady) return;

    // 1. Frame-Dropping: Nếu khung trước đang xử lý thì bỏ qua ngay lập tức, không xếp hàng!
    if (_isProcessingFrame) return;

    final int now = DateTime.now().millisecondsSinceEpoch;

    // 2. Throttling năng lượng: Kiểm tra nhịp thời gian từ BatteryThermalOptimizer
    if (!batteryOptimizer.shouldProcessFrame(now)) return;

    _isProcessingFrame = true;

    // Trích xuất dữ liệu frame để gửi sang Isolate
    final frameData = CameraFrameData(
      yPlane: image.planes[0].bytes,
      uPlane: image.planes.length > 1 ? image.planes[1].bytes : null,
      vPlane: image.planes.length > 2 ? image.planes[2].bytes : null,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
      yPixelStride: image.planes[0].bytesPerPixel ?? 1,
      uvPixelStride: image.planes.length > 1 ? (image.planes[1].bytesPerPixel ?? 1) : 1,
      width: image.width,
      height: image.height,
      sensorOrientation: _cameraController?.description.sensorOrientation ?? 90,
    );

    _executePipeline(frameData, now);
  }

  /// Thực thi toàn bộ chuỗi Pipeline: Preprocess -> Inference -> Spatial -> Ground -> Alert
  Future<void> _executePipeline(CameraFrameData frameData, int frameStartTime) async {
    try {
      // Cập nhật thông số pin và nhiệt độ nếu có DeviceHealthService
      if (healthService != null) {
        batteryOptimizer.updateBatteryAndThermal(
          batteryLevel: healthService!.batteryLevel,
          thermalStatus: healthService!.thermalStatus,
        );
      }

      // Phát cảnh báo bằng giọng nói khi thiết bị quá nhiệt (Thermal Throttling)
      if (batteryOptimizer.shouldAnnounceThermalWarning(frameStartTime)) {
        alertEngine.audio.speakVietnamese(
          'Thiết bị quá nhiệt, giảm tốc độ xử lý',
          force: true,
          priority: 250,
        );
      }

      // BƯỚC 1: Tiền xử lý ảnh trong Isolate
      final preprocessed = await compute(preprocessCameraFrame, frameData);
      final int tPreprocessDone = DateTime.now().millisecondsSinceEpoch;
      latencyPreprocessMs = tPreprocessDone - frameStartTime;

      // BƯỚC 2: Suy luận TFLite SSD MobileNet on-device
      final int tInferStart = DateTime.now().millisecondsSinceEpoch;
      final rawDetections = detectorService.detectFromImage(
        preprocessed.rgb300,
        300,
        300,
      );
      final int tInferDone = DateTime.now().millisecondsSinceEpoch;
      latencyInferenceMs = tInferDone - tInferStart;

      // BƯỚC 3: Phân tích không gian 2D (Spatial Corridor Analysis với bù trừ góc nghiêng)
      final int tAnalysisStart = DateTime.now().millisecondsSinceEpoch;
      final double walkingSpeed = (batteryOptimizer.userMovementState == 'walking') ? 1.0 : 0.0;
      final double tilt = tiltService?.effectiveTiltRad ?? 0.0;
      final spatialHazards = spatialAnalyzer.analyze(
        rawDetections,
        300,
        300,
        walkingSpeedMps: walkingSpeed,
        tiltAngleRad: tilt,
      );

      // BƯỚC 4: Phân tích mặt đất & bậc thềm (Ground Plane Luminance Analysis)
      // Khi Pin < 20% hoặc Quá nhiệt: giãn chu kỳ phân tích còn 1 lần/giây để tiết kiệm vi xử lý
      final List<GroundHazard> groundHazards;
      if (batteryOptimizer.shouldProcessGroundPlane(frameStartTime)) {
        groundHazards = groundAnalyzer.analyzeLuminance(
          preprocessed.luma160,
          160,
          120,
        );
        _cachedGroundHazards = groundHazards;
      } else {
        groundHazards = _cachedGroundHazards;
      }

      // BƯỚC 5: Quyết định cảnh báo âm thanh & xúc giác (Alert Decision Engine)
      final threat = alertEngine.process(
        objects2D: spatialHazards,
        groundHazards: groundHazards,
        genericObstacles: const [],
      );

      final int tAnalysisDone = DateTime.now().millisecondsSinceEpoch;
      latencyAnalysisMs = tAnalysisDone - tAnalysisStart;
      latencyTotalMs = tAnalysisDone - frameStartTime;

      // Cập nhật trạng thái
      latestDetections = spatialHazards;
      latestGroundHazards = groundHazards;
      currentThreat = threat;

      // Tính toán Rolling FPS
      _frameCount++;
      final int elapsedFpsPeriod = tAnalysisDone - _lastFpsCalcTime;
      if (elapsedFpsPeriod >= 1000) {
        currentFps = (_frameCount * 1000.0) / elapsedFpsPeriod;
        _frameCount = 0;
        _lastFpsCalcTime = tAnalysisDone;
      }

      // Ghi log CSV đo đạc thực địa
      csvLogger.logFrame(
        fps: currentFps,
        latencyPreprocessMs: latencyPreprocessMs,
        latencyInferenceMs: latencyInferenceMs,
        latencyAnalysisMs: latencyAnalysisMs,
        latencyTotalMs: latencyTotalMs,
        objectCount: spatialHazards.length,
        primaryThreat: threat?.vietnameseLabel ?? 'None',
        threatDirection: threat?.direction.name ?? 'None',
        threatDistance: threat?.approximateDistanceMeters ?? 'None',
        delegate: detectorService.activeDelegate,
        batteryLevel: batteryOptimizer.batteryLevel,
        thermalStatus: batteryOptimizer.thermalStatus,
      );

      onFrameProcessed?.call();
    } catch (e) {
      debugPrint('Lỗi thực thi camera pipeline: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Hỗ trợ chạy giả lập khung hình cho Unit Test & Benchmark mà không cần phần cứng
  Future<void> processSyntheticFrame(CameraFrameData frameData) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _isProcessingFrame = true;
    await _executePipeline(frameData, now);
  }

  void dispose() {
    stopStream();
    _cameraController?.dispose();
    _cameraController = null;
    _isInitialized = false;
  }
}

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/thresholds.dart';
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

enum PipelineStatus { demo, starting, running, failed }

/// Injectable hardware boundary: lifecycle tests use the real service state machine.
abstract class PipelineCamera {
  CameraController? get controller;
  Future<void> initialize();
  Future<void> start(void Function(CameraFrameData) onFrame);
  Future<void> stop();
  Future<void> dispose();
}

class _DevicePipelineCamera implements PipelineCamera {
  final CameraDescription? customCamera;
  CameraController? _controller;
  bool _disposed = false;

  _DevicePipelineCamera(this.customCamera);

  @override
  CameraController? get controller => _controller;

  @override
  Future<void> initialize() async {
    final cameras = customCamera == null ? await availableCameras() : [customCamera!];
    if (_disposed) return;
    if (cameras.isEmpty) throw StateError('Không tìm thấy camera');
    final target = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    Object? lastError;
    for (final preset in [ResolutionPreset.low, ResolutionPreset.medium]) {
      if (_disposed) return;
      final candidate = CameraController(
        target, preset, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _controller = candidate;
      try {
        await candidate.initialize();
        if (_disposed) await candidate.dispose();
        return;
      } catch (error) {
        lastError = error;
        debugPrint('Camera preset $preset không khả dụng: $error');
        await candidate.dispose();
        _controller = null;
      }
    }
    throw StateError('Không thể khởi tạo camera: $lastError');
  }

  @override
  Future<void> start(void Function(CameraFrameData) onFrame) async {
    final camera = _controller;
    if (_disposed || camera == null) throw StateError('Camera chưa được khởi tạo');
    await camera.startImageStream((image) {
      if (image.planes.isEmpty ||
          (image.format.group != ImageFormatGroup.yuv420 &&
              image.format.group != ImageFormatGroup.bgra8888)) {
        // Invalid frames fail visibly during validation, never become a black image.
        onFrame(CameraFrameData(yPlane: Uint8List(0), yRowStride: 0,
            yPixelStride: 1, width: 0, height: 0, sensorOrientation: 0));
        return;
      }
      onFrame(CameraFrameData(
        yPlane: image.planes[0].bytes,
        uPlane: image.planes.length > 1 ? image.planes[1].bytes : null,
        vPlane: image.planes.length > 2 ? image.planes[2].bytes : null,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
        yPixelStride: image.planes[0].bytesPerPixel ?? 1,
        uvPixelStride: image.planes.length > 1 ? (image.planes[1].bytesPerPixel ?? 1) : 1,
        vRowStride: image.planes.length > 2 ? image.planes[2].bytesPerRow : null,
        vPixelStride: image.planes.length > 2 ? image.planes[2].bytesPerPixel : null,
        width: image.width,
        height: image.height,
        sensorOrientation: camera.description.sensorOrientation,
        isBgra: image.format.group == ImageFormatGroup.bgra8888,
      ));
    });
  }

  @override
  Future<void> stop() async {
    if (_controller?.value.isStreamingImages ?? false) await _controller!.stopImageStream();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final camera = _controller;
    _controller = null;
    await camera?.dispose();
  }
}

class CameraPipelineService {
  final DetectorService detectorService;
  final SpatialAnalyzer spatialAnalyzer;
  final GroundPlaneAnalyzer groundAnalyzer;
  final AlertDecisionEngine alertEngine;
  final BatteryThermalOptimizer batteryOptimizer;
  final CsvLogger csvLogger;
  final TiltCalibrationService? tiltService;
  final DeviceHealthService? healthService;
  final PipelineCamera Function(CameraDescription?) _cameraFactory;
  final Future<bool> Function() _requestCameraPermission;
  final int Function() _now;

  PipelineCamera? _camera;
  CameraController? get controller => _camera?.controller;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;
  bool _isProcessingFrame = false;
  bool _desiredStreaming = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void> _lifecycle = Future<void>.value();
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  PipelineStatus _status = PipelineStatus.demo;
  PipelineStatus get status => _status;
  String? failureReason;
  int _lastFrameTimestamp = 0;
  int get lastFrameTimestamp => _lastFrameTimestamp;
  int? _lastSuccessfulFrameTimestamp;
  int? get lastSuccessfulFrameTimestamp => _lastSuccessfulFrameTimestamp;
  int _startTimestamp = 0;
  int _consecutiveInferenceErrors = 0;
  int get consecutiveInferenceErrors => _consecutiveInferenceErrors;
  Timer? _watchdogTimer;

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
  VoidCallback? onStatusChanged;
  int _frameCount = 0;
  int _lastFpsCalcTime = 0;
  final Uint8List _rgb300Buffer = Uint8List(300 * 300 * 3);
  final Uint8List _luma160Buffer = Uint8List(160 * 120);

  CameraPipelineService({
    required this.detectorService,
    required this.spatialAnalyzer,
    required this.groundAnalyzer,
    required this.alertEngine,
    required this.batteryOptimizer,
    required this.csvLogger,
    this.tiltService,
    this.healthService,
    PipelineCamera Function(CameraDescription?)? cameraFactory,
    Future<bool> Function()? requestCameraPermission,
    int Function()? clock,
  })  : _cameraFactory = cameraFactory ?? _DevicePipelineCamera.new,
        _requestCameraPermission = requestCameraPermission ?? _ensureCameraPermission,
        _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    return status.isGranted || (await Permission.camera.request()).isGranted;
  }

  bool _isCurrent(int generation) =>
      !_disposed && _desiredStreaming && generation == _generation && _status != PipelineStatus.failed;

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _lifecycle.then((_) => operation());
    // Keep the queue usable without hiding errors from the caller awaiting result.
    _lifecycle = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      debugPrint('Camera lifecycle: $error');
    });
    return result;
  }

  void _clearScene() {
    latestDetections = const [];
    latestGroundHazards = const [];
    _cachedGroundHazards = const [];
    currentThreat = null;
    spatialAnalyzer.reset();
    groundAnalyzer.reset();
    alertEngine.reset();
    currentFps = 0;
    _frameCount = 0;
  }

  void updateStatus(PipelineStatus newStatus, {String? reason, String? failureSpeech}) {
    if (_disposed || _status == newStatus) return;
    if (_status == PipelineStatus.failed && newStatus == PipelineStatus.running) return;
    if (newStatus == PipelineStatus.running && _lastSuccessfulFrameTimestamp == null) return;
    final oldStatus = _status;
    _status = newStatus;
    debugPrint('PipelineStatus: $oldStatus -> $newStatus (${reason ?? "no reason"})');
    if (newStatus == PipelineStatus.running) {
      unawaited(alertEngine.audio.speakVietnamese('Đã bật trợ lý dẫn đường', force: true, priority: 100));
    } else if (newStatus == PipelineStatus.failed) {
      failureReason = reason;
      _clearScene();
      unawaited(alertEngine.audio.speakVietnamese(
        failureSpeech ?? 'Mất tín hiệu camera, đừng dùng để dẫn đường',
        force: true, priority: 300,
      ));
      unawaited(stopStream());
    }
    onStatusChanged?.call();
    onFrameProcessed?.call();
  }

  /// Fresh camera arrivals cannot conceal failed or stalled inference.
  void checkWatchdog([int? customNow]) {
    if (_disposed || !_desiredStreaming) return;
    final now = customNow ?? _now();
    if (_status == PipelineStatus.starting && now - _startTimestamp > kPipelineStartupTimeoutMs) {
      updateStatus(PipelineStatus.failed, reason: 'Quá thời gian khởi động camera và nhận diện');
    } else if (_status == PipelineStatus.running &&
        (_lastSuccessfulFrameTimestamp == null ||
            now - _lastSuccessfulFrameTimestamp! > kWatchdogFrameTimeoutMs)) {
      updateStatus(PipelineStatus.failed, reason: 'Không có kết quả nhận diện mới trong ${kWatchdogFrameTimeoutMs}ms');
    }
  }

  Future<void> initializeCamera({CameraDescription? customCamera}) {
    final generation = _generation;
    return _enqueue(() async {
      if (_disposed || generation != _generation || _isInitialized) return;
      await _initializeCamera(generation, customCamera);
    });
  }

  Future<void> _initializeCamera(int generation, CameraDescription? customCamera) async {
    final camera = _cameraFactory(customCamera);
    _camera = camera;
    await camera.initialize().timeout(const Duration(milliseconds: kPipelineStartupTimeoutMs));
    if (_disposed || generation != _generation) return;
    _isInitialized = true;
  }

  Future<void> startStream() {
    if (_disposed) return Future<void>.value();
    if (_desiredStreaming) return _startFuture ?? Future<void>.value();
    _desiredStreaming = true;
    final generation = ++_generation;
    _clearScene();
    batteryOptimizer.resetTiming();
    failureReason = null;
    _lastSuccessfulFrameTimestamp = null;
    _lastFrameTimestamp = 0;
    _consecutiveInferenceErrors = 0;
    _startTimestamp = _now();
    _lastFpsCalcTime = _startTimestamp;
    updateStatus(PipelineStatus.starting);
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => checkWatchdog());
    final operation = _enqueue(() async {
      try {
        if (!_isCurrent(generation)) return;
        final permission = await _requestCameraPermission()
            .timeout(const Duration(milliseconds: kPipelineStartupTimeoutMs));
        if (!_isCurrent(generation)) return;
        if (!permission) {
          updateStatus(PipelineStatus.failed, reason: 'Quyền camera bị từ chối',
              failureSpeech: 'Chưa cấp quyền camera, không thể dẫn đường');
          return;
        }
        if (!detectorService.isReady) {
          updateStatus(PipelineStatus.failed, reason: detectorService.loadError ?? 'Mô hình nhận diện chưa sẵn sàng',
              failureSpeech: 'Nhận diện chưa sẵn sàng, không thể dẫn đường');
          return;
        }
        if (!_isInitialized) await _initializeCamera(generation, null);
        if (!_isCurrent(generation)) return;
        _isStreaming = true;
        await _camera!.start((frame) => _handleFrame(frame, generation))
            .timeout(const Duration(milliseconds: kPipelineStartupTimeoutMs));
      } catch (error) {
        if (_isCurrent(generation)) {
          updateStatus(PipelineStatus.failed, reason: 'Không thể khởi động camera: $error',
              failureSpeech: 'Không thể khởi động camera, đừng dùng để dẫn đường');
        }
      }
    });
    _startFuture = operation;
    return operation;
  }

  Future<void> stopStream() {
    _desiredStreaming = false;
    ++_generation; // Cancel pending permission/init and callbacks immediately.
    _isStreaming = false;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _clearScene();
    if (!_disposed && _status != PipelineStatus.failed) updateStatus(PipelineStatus.demo);
    return _enqueue(_releaseCamera);
  }

  Future<void> _releaseCamera() async {
    final camera = _camera;
    _camera = null;
    _isInitialized = false;
    if (camera == null) return;
    try {
      await camera.stop().timeout(const Duration(milliseconds: kPipelineStartupTimeoutMs));
    } catch (error) {
      debugPrint('Lỗi dừng camera: $error');
    } finally {
      try {
        await camera.dispose().timeout(const Duration(milliseconds: kPipelineStartupTimeoutMs));
      } catch (error) {
        debugPrint('Lỗi giải phóng camera: $error');
      }
    }
  }

  void _handleFrame(CameraFrameData frame, int generation) {
    if (!_isCurrent(generation) || !_isStreaming) return;
    final now = _now();
    _lastFrameTimestamp = now;
    if (_isProcessingFrame || !batteryOptimizer.shouldProcessFrame(now)) return;
    _executePipeline(frame, now, generation);
  }

  void _executePipeline(CameraFrameData frameData, int frameStartTime, int generation) {
    _isProcessingFrame = true;
    try {
      if (!detectorService.isReady) throw StateError('Mô hình nhận diện không sẵn sàng');
      if (healthService != null) {
        batteryOptimizer.updateBatteryAndThermal(
          batteryLevel: healthService!.batteryLevel, thermalStatus: healthService!.thermalStatus);
      }
      if (batteryOptimizer.shouldAnnounceThermalWarning(frameStartTime)) {
        unawaited(alertEngine.audio.speakVietnamese('Thiết bị quá nhiệt, giảm tốc độ xử lý', force: true, priority: 250));
      }
      final preprocessed = preprocessCameraFrame(frameData,
          reusableRgb300: _rgb300Buffer, reusableLuma160: _luma160Buffer);
      final preprocessDone = _now();
      latencyPreprocessMs = preprocessDone - frameStartTime;
      final List<Map<String, dynamic>> rawDetections;
      try {
        rawDetections = detectorService.detectFromImage(preprocessed.rgb300, 300, 300);
        _consecutiveInferenceErrors = 0;
      } catch (error) {
        _consecutiveInferenceErrors++;
        debugPrint('Lỗi nhận diện ($_consecutiveInferenceErrors): $error');
        _clearScene();
        if (_consecutiveInferenceErrors >= kMaxConsecutiveInferenceErrors) {
          updateStatus(PipelineStatus.failed, reason: 'Nhận diện lỗi $kMaxConsecutiveInferenceErrors lần liên tiếp');
        } else {
          onFrameProcessed?.call();
        }
        return; // Failed inference must not be processed as an empty scene.
      }
      final inferenceDone = _now();
      latencyInferenceMs = inferenceDone - preprocessDone;
      if (!_isCurrent(generation)) return;
      // Synchronous inference can delay Timer callbacks: reject stale results
      // here too, before emitting any navigation or threat feedback.
      if (inferenceDone - frameStartTime > kWatchdogFrameTimeoutMs) {
        updateStatus(PipelineStatus.failed, reason: 'Kết quả nhận diện quá cũ');
        return;
      }
      final spatialHazards = spatialAnalyzer.analyze(rawDetections, 300, 300,
          walkingSpeedMps: batteryOptimizer.userMovementState == 'walking' ? 1.0 : 0.0,
          tiltAngleRad: tiltService?.effectiveTiltRad ?? 0.0);
      if (batteryOptimizer.shouldProcessGroundPlane(frameStartTime)) {
        _cachedGroundHazards = groundAnalyzer.analyzeLuminance(preprocessed.luma160, 160, 120);
      }
      final groundHazards = _cachedGroundHazards;
      final analysisDone = _now();
      if (!_isCurrent(generation) || analysisDone - frameStartTime > kWatchdogFrameTimeoutMs) {
        if (_isCurrent(generation)) updateStatus(PipelineStatus.failed, reason: 'Phân tích hình ảnh quá chậm');
        return;
      }
      _lastSuccessfulFrameTimestamp = analysisDone;
      updateStatus(PipelineStatus.running);
      if (!_isCurrent(generation)) return;
      final threat = alertEngine.process(objects2D: spatialHazards, groundHazards: groundHazards, genericObstacles: const []);
      latencyAnalysisMs = analysisDone - inferenceDone;
      latencyTotalMs = analysisDone - frameStartTime;
      latestDetections = spatialHazards;
      latestGroundHazards = groundHazards;
      currentThreat = threat;
      _frameCount++;
      final elapsed = analysisDone - _lastFpsCalcTime;
      if (elapsed >= 1000) {
        currentFps = _frameCount * 1000.0 / elapsed;
        _frameCount = 0;
        _lastFpsCalcTime = analysisDone;
      }
      if (csvLogger.isBenchmarkRunning || csvLogger.isLoggingEnabled) {
        csvLogger.logFrame(fps: currentFps, latencyPreprocessMs: latencyPreprocessMs,
            latencyInferenceMs: latencyInferenceMs, latencyAnalysisMs: latencyAnalysisMs,
            latencyTotalMs: latencyTotalMs, objectCount: spatialHazards.length,
            primaryThreat: threat?.vietnameseLabel ?? 'None', threatDirection: threat?.direction.name ?? 'None',
            threatDistance: threat?.approximateDistanceMeters ?? 'None', delegate: detectorService.activeDelegate,
            batteryLevel: batteryOptimizer.batteryLevel, thermalStatus: batteryOptimizer.thermalStatus);
      }
      onFrameProcessed?.call();
    } catch (error) {
      updateStatus(PipelineStatus.failed, reason: 'Lỗi xử lý hình ảnh: $error');
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Benchmark hook. Lifecycle tests inject PipelineCamera and call startStream.
  Future<void> processSyntheticFrame(CameraFrameData frameData, {int? customNow}) async {
    if (_disposed || _status == PipelineStatus.failed || _isProcessingFrame) return;
    if (!_desiredStreaming) {
      _desiredStreaming = true;
      ++_generation;
      _clearScene();
      batteryOptimizer.resetTiming();
      _startTimestamp = customNow ?? _now();
      _lastFpsCalcTime = _startTimestamp;
      updateStatus(PipelineStatus.starting);
    }
    final now = customNow ?? _now();
    _lastFrameTimestamp = now;
    _executePipeline(frameData, now, _generation);
  }

  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposed = true;
    onFrameProcessed = null;
    onStatusChanged = null;
    return _disposeFuture = stopStream();
  }
}

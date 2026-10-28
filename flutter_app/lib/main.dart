import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/audio_haptics_service.dart';
import 'services/alert_decision_engine.dart';
import 'services/navigation_service.dart';
import 'services/spatial_analyzer.dart';
import 'services/ground_analyzer.dart';
import 'services/detector_service.dart';
import 'services/battery_optimizer.dart';
import 'services/csv_logger.dart';
import 'services/camera_pipeline_service.dart';
import 'services/tilt_calibration_service.dart';
import 'services/device_health_service.dart';
import 'ui/accessible_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khóa hướng dọc cho điện thoại gắn ngực
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const BeMyEyeApp());
}

class BeMyEyeApp extends StatefulWidget {
  const BeMyEyeApp({Key? key}) : super(key: key);

  @override
  State<BeMyEyeApp> createState() => _BeMyEyeAppState();
}

class _BeMyEyeAppState extends State<BeMyEyeApp> with WidgetsBindingObserver {
  late final AudioHapticsService _audioService;
  late final AlertDecisionEngine _alertEngine;
  late final NavigationService _navService;
  late final SpatialAnalyzer _spatialAnalyzer;
  late final GroundPlaneAnalyzer _groundAnalyzer;
  late final DetectorService _detectorService;
  late final BatteryThermalOptimizer _batteryOptimizer;
  late final CsvLogger _csvLogger;
  late final TiltCalibrationService _tiltService;
  late final DeviceHealthService _healthService;
  late final CameraPipelineService _cameraPipeline;

  bool _isAppActive = false;
  bool _isTransitioning = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audioService = AudioHapticsService();
    _alertEngine = AlertDecisionEngine(audio: _audioService);
    _navService = NavigationService(
      audio: _audioService,
      alertEngine: _alertEngine,
      isVisionReady: () => _cameraPipeline.status == PipelineStatus.running,
    );
    _spatialAnalyzer = SpatialAnalyzer();
    _groundAnalyzer = GroundPlaneAnalyzer();
    _detectorService = DetectorService();
    _batteryOptimizer = BatteryThermalOptimizer();
    _csvLogger = CsvLogger();
    _tiltService = TiltCalibrationService();
    _healthService = DeviceHealthService()..startPeriodicPolling();

    _cameraPipeline = CameraPipelineService(
      detectorService: _detectorService,
      spatialAnalyzer: _spatialAnalyzer,
      groundAnalyzer: _groundAnalyzer,
      alertEngine: _alertEngine,
      batteryOptimizer: _batteryOptimizer,
      csvLogger: _csvLogger,
      tiltService: _tiltService,
      healthService: _healthService,
    );
    _cameraPipeline.onStatusChanged = _handlePipelineStatusChanged;

    _initDetector();
  }

  void _handlePipelineStatusChanged() {
    if (!mounted || _isDisposed) return;
    final failed = _cameraPipeline.status == PipelineStatus.failed;
    setState(() {
      _isAppActive = _cameraPipeline.status == PipelineStatus.running ||
          _cameraPipeline.status == PipelineStatus.starting;
    });

    if (failed) {
      if (_navService.getStatus().isNavigating) {
        _navService.stopNavigation(announce: false);
      }
      unawaited(
        WakelockPlus.disable().catchError((Object e) {
          debugPrint('Không thể tắt wakelock sau lỗi pipeline: $e');
        }),
      );
    }
  }

  Future<void> _initDetector() async {
    await _detectorService.loadModel();
    if (mounted && !_isDisposed) {
      setState(() {});
      if (!_detectorService.isReady) {
        // Nguyên tắc an toàn: Lỗi phải kêu to, không âm thầm bỏ qua
        _audioService.speakVietnamese(
          'Không tải được mô hình nhận diện, đừng dùng ứng dụng để dẫn đường',
          force: true,
        );
      }
    }
  }

  Future<void> _retryModel() async {
    if (_isTransitioning || _isDisposed) return;
    setState(() => _isTransitioning = true);
    try {
      await _initDetector();
    } finally {
      if (mounted && !_isDisposed) setState(() => _isTransitioning = false);
    }
  }

  Future<void> _toggleApp() async {
    if (_isTransitioning || _isDisposed) return;
    // Nếu mô hình chưa sẵn sàng hoặc có lỗi, khóa hoàn toàn chức năng dẫn đường
    if (!_detectorService.isReady) {
      _audioService.speakVietnamese(
        'Không tải được mô hình nhận diện, đừng dùng ứng dụng để dẫn đường',
        force: true,
      );
      return;
    }

    setState(() => _isTransitioning = true);
    try {
      if (_cameraPipeline.status != PipelineStatus.running &&
          _cameraPipeline.status != PipelineStatus.starting) {
        // Giữ màn hình luôn sáng bằng WakelockPlus khi dẫn đường
        try {
          await WakelockPlus.enable();
        } catch (e) {
          debugPrint('Không thể bật wakelock: $e');
        }

        // Chỉ công bố sẵn sàng sau khung hình suy luận thành công đầu tiên.
        await _cameraPipeline.startStream();
      } else {
        await _cameraPipeline.stopStream();
        try {
          await WakelockPlus.disable();
        } catch (e) {
          debugPrint('Không thể tắt wakelock: $e');
        }

        _audioService.speakVietnamese('Đã tạm dừng', force: true);
        _navService.stopNavigation();
      }
    } finally {
      if (mounted && !_isDisposed) setState(() => _isTransitioning = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_pauseForBackground());
    }
  }

  Future<void> _pauseForBackground() async {
    final wasActive = _isAppActive || _isTransitioning;
    await _cameraPipeline.stopStream();
    _navService.stopNavigation(announce: false);
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('Không thể tắt wakelock khi ứng dụng vào nền: $e');
    }
    if (wasActive && !_isDisposed) {
      await _audioService.speakVietnamese(
        'Đã tạm dừng khi rời ứng dụng. Mở lại và bấm bắt đầu để tiếp tục.',
        force: true,
        priority: 300,
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cameraPipeline.onStatusChanged = null;
    _healthService.dispose();
    _tiltService.dispose();
    unawaited(
      WakelockPlus.disable().catchError((Object e) {
        debugPrint('Không thể giải phóng wakelock: $e');
      }),
    );
    _navService.dispose();
    unawaited(_disposePipeline());
    super.dispose();
  }

  Future<void> _disposePipeline() async {
    await _cameraPipeline.dispose();
    _detectorService.dispose();
    _audioService.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Be My Eyes VN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000), // OLED Pure Black
        primaryColor: const Color(0xFFFACC15),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFACC15),
          secondary: Color(0xFF22C55E),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: Builder(
        builder: (ctx) => AccessibleScreen(
          audio: _audioService,
          alertEngine: _alertEngine,
          navService: _navService,
          detectorService: _detectorService,
          pipelineService: _cameraPipeline,
          isAppActive: _isAppActive,
          onToggleApp: _toggleApp,
          onRetryModel: _retryModel,
          isTransitioning: _isTransitioning,
        ),
      ),
    );
  }
}

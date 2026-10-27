import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'config/thresholds.dart';
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
import 'ui/accessible_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khóa hướng dọc cho điện thoại gắn ngực
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const BeMyEyeApp());
}

class BeMyEyeApp extends StatefulWidget {
  const BeMyEyeApp({Key? key}) : super(key: key);

  @override
  State<BeMyEyeApp> createState() => _BeMyEyeAppState();
}

class _BeMyEyeAppState extends State<BeMyEyeApp> {
  late final AudioHapticsService _audioService;
  late final AlertDecisionEngine _alertEngine;
  late final NavigationService _navService;
  late final SpatialAnalyzer _spatialAnalyzer;
  late final GroundPlaneAnalyzer _groundAnalyzer;
  late final DetectorService _detectorService;
  late final BatteryThermalOptimizer _batteryOptimizer;
  late final CsvLogger _csvLogger;
  late final TiltCalibrationService _tiltService;
  late final CameraPipelineService _cameraPipeline;

  bool _isAppActive = false;

  @override
  void initState() {
    super.initState();
    _audioService = AudioHapticsService();
    _alertEngine = AlertDecisionEngine(audio: _audioService);
    _navService = NavigationService(audio: _audioService, alertEngine: _alertEngine);
    _spatialAnalyzer = SpatialAnalyzer();
    _groundAnalyzer = GroundPlaneAnalyzer();
    _detectorService = DetectorService();
    _batteryOptimizer = BatteryThermalOptimizer();
    _csvLogger = CsvLogger();
    _tiltService = TiltCalibrationService();

    _cameraPipeline = CameraPipelineService(
      detectorService: _detectorService,
      spatialAnalyzer: _spatialAnalyzer,
      groundAnalyzer: _groundAnalyzer,
      alertEngine: _alertEngine,
      batteryOptimizer: _batteryOptimizer,
      csvLogger: _csvLogger,
      tiltService: _tiltService,
    );

    _initDetector();
  }

  Future<void> _initDetector() async {
    await _detectorService.loadModel();
    if (mounted) {
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

  void _toggleApp() async {
    // Nếu mô hình chưa sẵn sàng hoặc có lỗi, khóa hoàn toàn chức năng dẫn đường
    if (!_detectorService.isReady) {
      _audioService.speakVietnamese(
        'Không tải được mô hình nhận diện, đừng dùng ứng dụng để dẫn đường',
        force: true,
      );
      return;
    }

    setState(() {
      _isAppActive = !_isAppActive;
    });

    if (_isAppActive) {
      // Giữ màn hình luôn sáng bằng WakelockPlus khi dẫn đường
      try {
        await WakelockPlus.enable();
      } catch (_) {}

      // Kích hoạt luồng camera stream
      await _cameraPipeline.startStream();

      if (!kPipelineEnabled) {
        _audioService.speakVietnamese(
          'Bản thử nghiệm, chưa nhận diện camera. Không dùng để dẫn đường thực tế.',
          force: true,
        );
      } else {
        _audioService.speakVietnamese('Đã bật trợ lý dẫn đường', force: true);
      }
    } else {
      // Dừng stream camera và giải phóng wakelock
      await _cameraPipeline.stopStream();
      try {
        await WakelockPlus.disable();
      } catch (_) {}

      _audioService.speakVietnamese('Đã tạm dừng', force: true);
      _navService.stopNavigation();
    }
  }

  @override
  void dispose() {
    _cameraPipeline.dispose();
    _tiltService.dispose();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    _audioService.dispose();
    _navService.dispose();
    _detectorService.dispose();
    super.dispose();
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
        ),
      ),
    );
  }
}

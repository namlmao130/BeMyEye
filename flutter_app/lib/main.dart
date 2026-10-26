import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/audio_haptics_service.dart';
import 'services/alert_decision_engine.dart';
import 'services/navigation_service.dart';
import 'services/spatial_analyzer.dart';
import 'services/ground_analyzer.dart';
import 'services/detector_service.dart';
import 'services/battery_optimizer.dart';
import 'ui/accessible_screen.dart';
import 'ui/widgets/safety_disclaimer_dialog.dart';

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

    _detectorService.loadModel();
  }

  void _toggleApp() {
    setState(() {
      _isAppActive = !_isAppActive;
    });

    if (_isAppActive) {
      _audioService.speakVietnamese('Đã bật trợ lý dẫn đường', force: true);
    } else {
      _audioService.speakVietnamese('Đã tạm dừng', force: true);
      _navService.stopNavigation();
    }
  }

  @override
  void dispose() {
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
          isAppActive: _isAppActive,
          onToggleApp: _toggleApp,
        ),
      ),
    );
  }
}

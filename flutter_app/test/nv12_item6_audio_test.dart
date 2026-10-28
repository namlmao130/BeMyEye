import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/models/ground_hazard.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
      'NV12.6 - Âm thanh: Tôn trọng pitch/durationMs & Phân biệt tiếng bậc đi xuống',
      () {
    late AudioHapticsService audio;

    setUp(() {
      audio = AudioHapticsService(customSpeaker: (t) async {});
    });

    tearDown(() {
      audio.dispose();
    });

    test(
        'Tiêu chí 1: Tiếng "bậc đi xuống" (isNegativeObstacle) phát file sounds/step_down.wav, KHÁC tiếng vật cản thường',
        () async {
      // 1. Phát âm thanh vật cản thông thường ở giữa
      await audio.playDirectionalBeep(
        pan: 0.0,
        pitch: 750,
        durationMs: 60,
        direction: DirectionZone.center,
        isNegativeObstacle: false,
      );
      expect(audio.lastPlayedAsset, equals('sounds/beep_center.wav'));
      expect(audio.lastIsNegativeObstacle, isFalse);

      // 2. Phát âm thanh bậc đi xuống (hố sụt, lề tụt dốc)
      await audio.playDirectionalBeep(
        pan: 0.0,
        pitch: 320,
        durationMs: 110,
        direction: DirectionZone.center,
        isNegativeObstacle: true,
      );
      // Bắt buộc phải phát step_down.wav
      expect(audio.lastPlayedAsset, equals('sounds/step_down.wav'));
      expect(audio.lastIsNegativeObstacle, isTrue);
      expect(
        audio.lastPlayedAsset,
        isNot(equals('sounds/beep_center.wav')),
        reason: 'Tiếng bậc đi xuống phải khác tiếng vật cản thông thường',
      );
    });

    test(
        'Tiêu chí 2: Tôn trọng pitch và durationMs qua thuộc tính và playbackRate',
        () async {
      await audio.playDirectionalBeep(
        pan: 0.0,
        pitch: 1100,
        durationMs: 75,
        direction: DirectionZone.center,
      );

      expect(audio.lastPlayedPitch, equals(1100));
      expect(audio.lastPlayedDurationMs, equals(75));
      // Tốc độ phát được điều chỉnh theo pitch (1100 / 750 = ~1.467)
      expect(audio.lastPlayedPlaybackRate, closeTo(1100 / 750.0, 0.01));
    });

    test(
      'Tiêu chí 3: Đảo kênh tai nghe khi người dùng đeo ngược L/R',
      () async {
        audio.isChannelsSwapped = true;

        // Yêu cầu phát bên trái -> vì đảo kênh nên thực tế phát bên phải
        await audio.playDirectionalBeep(
          pan: -1.0,
          pitch: 500,
          direction: DirectionZone.left,
        );
        expect(audio.lastPlayedAsset, equals('sounds/beep_right.wav'));

        // Yêu cầu phát bên phải -> thực tế phát bên trái
        await audio.playDirectionalBeep(
          pan: 1.0,
          pitch: 1000,
          direction: DirectionZone.right,
        );
        expect(audio.lastPlayedAsset, equals('sounds/beep_left.wav'));
      },
    );

    test(
        'Tiêu chí 4: AlertDecisionEngine khi gặp bậc đi xuống thực sự kích hoạt tiếng step_down.wav',
        () {
      final engine = AlertDecisionEngine(audio: audio);

      final stepDownHazard = GroundHazard(
        type: GroundHazardType.stepDown,
        vietnameseName: 'Bậc đi xuống, chú ý hụt chân',
        normalizedY: 0.85,
        confidence: 0.95,
        distanceLevel: DistanceLevel.critical,
        distanceMeters: '< 1.5m',
        isNegativeObstacle: true,
      );

      final threat = engine.process(
        objects2D: [],
        groundHazards: [stepDownHazard],
        genericObstacles: [],
        customNow: 1000,
      );

      expect(threat, isNotNull);
      expect(threat!.isNegativeObstacle, isTrue);
      expect(
        audio.lastPlayedAsset,
        equals('sounds/step_down.wav'),
        reason:
            'Engine phát hiện bậc đi xuống phải phát âm thanh step_down.wav đặc thù',
      );
      expect(audio.lastPlayedPitch, equals(320));
      expect(audio.lastPlayedDurationMs, equals(110));
    });
  });
}

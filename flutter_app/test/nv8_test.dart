import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';

void main() {
  group(
    'NV8 - Âm thanh định hướng Stereo Pan PCM & Thử nghiệm Tai nghe (Lỗi 7)',
    () {
      test(
        'Định tuyến file PCM Stereo vật lý theo hướng DirectionZone',
        () async {
          final audio = AudioHapticsService(customSpeaker: (text) async {});

          // Hướng Trái
          await audio.playDirectionalBeep(
            pan: -1.0,
            pitch: 500,
            direction: DirectionZone.left,
          );
          expect(audio.lastPlayedAsset, equals('sounds/beep_left.wav'));

          // Hướng Giữa
          await audio.playDirectionalBeep(
            pan: 0.0,
            pitch: 750,
            direction: DirectionZone.center,
          );
          expect(audio.lastPlayedAsset, equals('sounds/beep_center.wav'));

          // Hướng Phải
          await audio.playDirectionalBeep(
            pan: 1.0,
            pitch: 1000,
            direction: DirectionZone.right,
          );
          expect(audio.lastPlayedAsset, equals('sounds/beep_right.wav'));

          audio.dispose();
        },
      );

      test(
        'Định tuyến file PCM khi chỉ truyền panValue (fallback tính từ pan)',
        () async {
          final audio = AudioHapticsService(customSpeaker: (text) async {});

          // Pan lệch trái (< -0.25)
          await audio.playDirectionalBeep(pan: -0.65, pitch: 500);
          expect(audio.lastPlayedAsset, equals('sounds/beep_left.wav'));

          // Pan ở giữa (-0.25 <= pan <= 0.25)
          await audio.playDirectionalBeep(pan: 0.10, pitch: 750);
          expect(audio.lastPlayedAsset, equals('sounds/beep_center.wav'));

          // Pan lệch phải (> 0.25)
          await audio.playDirectionalBeep(pan: 0.75, pitch: 1000);
          expect(audio.lastPlayedAsset, equals('sounds/beep_right.wav'));

          audio.dispose();
        },
      );

      test(
          'Hỗ trợ Đảo kênh L/R (isChannelsSwapped) khi người khiếm thị đeo ngược tai nghe',
          () async {
        final audio = AudioHapticsService(customSpeaker: (text) async {});
        audio.isChannelsSwapped = true;

        // Vật thể ở bên Trái -> Phải phát sang kênh Phải của tai nghe để đến đúng tai Trái
        await audio.playDirectionalBeep(
          pan: -1.0,
          pitch: 500,
          direction: DirectionZone.left,
        );
        expect(audio.lastPlayedAsset, equals('sounds/beep_right.wav'));

        // Vật thể ở bên Phải -> Phát sang kênh Trái của tai nghe
        await audio.playDirectionalBeep(
          pan: 1.0,
          pitch: 1000,
          direction: DirectionZone.right,
        );
        expect(audio.lastPlayedAsset, equals('sounds/beep_left.wav'));

        // Vật thể ở Giữa -> Vẫn giữ nguyên ở Giữa
        await audio.playDirectionalBeep(
          pan: 0.0,
          pitch: 750,
          direction: DirectionZone.center,
        );
        expect(audio.lastPlayedAsset, equals('sounds/beep_center.wav'));

        audio.dispose();
      });

      test(
          'Quy trình kiểm tra tai nghe (Earphone Check Sequence) gọi đủ 4 bước Trái -> Giữa -> Phải -> Hoàn tất',
          () async {
        final stepsRecorded = <String>[];
        final spokenRecorded = <String>[];

        final audio = AudioHapticsService(
          customSpeaker: (text) async {
            spokenRecorded.add(text);
          },
        );

        // Chạy quy trình kiểm tra tai nghe (chỉ mất ~4-5 giây mô phỏng)
        await audio.runEarphoneCheckSequence(
          onStepChange: (step) => stepsRecorded.add(step),
        );

        expect(stepsRecorded, equals(['left', 'center', 'right', 'done']));
        expect(spokenRecorded.length, equals(4));
        expect(spokenRecorded[0], contains('trái'));
        expect(spokenRecorded[1], contains('giữa'));
        expect(spokenRecorded[2], contains('phải'));
        expect(spokenRecorded[3], contains('Hoàn tất'));

        audio.dispose();
      });

      test(
          'AlertDecisionEngine kết nối hướng của vật thể với âm thanh định hướng PCM tương ứng',
          () {
        final audio = AudioHapticsService(customSpeaker: (text) async {});
        final engine = AlertDecisionEngine(audio: audio);

        final leftObstacle = DetectionResult(
          id: 'obs_left',
          label: 'motorcycle',
          vietnameseLabel: 'Xe máy',
          category: 'vehicle',
          score: 0.90,
          bbox: [50, 200, 100, 100],
          centerX: 0.20,
          bottomY: 0.85,
          areaRatio: 0.20,
          direction: DirectionZone.left,
          panValue: -0.60,
          distanceLevel: DistanceLevel.critical,
          approximateDistanceMeters: '< 1.5m',
          isApproaching: true,
        );

        engine.process(
          objects2D: [leftObstacle],
          groundHazards: [],
          customNow: 1000,
        );
        expect(audio.lastPlayedAsset, equals('sounds/beep_left.wav'));

        final rightObstacle = DetectionResult(
          id: 'obs_right',
          label: 'car',
          vietnameseLabel: 'Ô tô',
          category: 'vehicle',
          score: 0.90,
          bbox: [500, 200, 100, 100],
          centerX: 0.80,
          bottomY: 0.85,
          areaRatio: 0.20,
          direction: DirectionZone.right,
          panValue: 0.60,
          distanceLevel: DistanceLevel.critical,
          approximateDistanceMeters: '< 1.5m',
          isApproaching: true,
        );

        engine.process(
          objects2D: [rightObstacle],
          groundHazards: [],
          customNow: 2000,
        );
        expect(audio.lastPlayedAsset, equals('sounds/beep_right.wav'));

        audio.dispose();
      });
    },
  );
}

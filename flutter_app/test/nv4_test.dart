import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/models/ground_hazard.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';

void main() {
  group('NV4 - Sửa lỗi lặp giọng nói và cắt ngang câu (Lỗi 2)', () {
    test('Đồng hồ giả lập: Trong 5 giây có mối đe dọa liên tục (mỗi 240ms) thì chỉ phát giọng nói <= 2 lần', () {
      final audio = AudioHapticsService(customSpeaker: (text) async {});
      final engine = AlertDecisionEngine(audio: audio);

      final criticalObstacle = DetectionResult(
        id: 'motorcycle_01',
        label: 'motorcycle',
        vietnameseLabel: 'Xe máy',
        category: 'vehicle',
        score: 0.95,
        bbox: [100, 100, 100, 100],
        centerX: 0.50,
        bottomY: 0.90,
        areaRatio: 0.25,
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.critical,
        approximateDistanceMeters: '< 1.5m',
        isApproaching: true,
      );

      // Mô phỏng 5 giây (0ms đến 5000ms), mỗi frame cách nhau 240ms (~21 frames)
      for (int t = 0; t <= 5000; t += 240) {
        engine.process(
          objects2D: [criticalObstacle],
          groundHazards: [],
          customNow: t,
        );
      }

      // Tiêu chí bắt buộc: Trong 5 giây mối đe dọa liên tục chỉ được nói <= 2 lần
      expect(audio.speechInvocationCount, lessThanOrEqualTo(2));
      expect(audio.speechInvocationCount, equals(2)); // Lần 1 ở t=0, lần 2 ở t=3120ms
      expect(audio.spokenHistory.length, equals(2));
      expect(audio.spokenHistory[0], equals('Xe máy đang tới gần!'));
      expect(audio.spokenHistory[1], equals('Xe máy đang tới gần!'));

      audio.dispose();
    });

    test('Mối đe dọa theo ID/loại chỉ nói 1 lần rồi im lặng tối thiểu 3 giây', () {
      final audio = AudioHapticsService(customSpeaker: (text) async {});
      final engine = AlertDecisionEngine(audio: audio);

      final threat = DetectionResult(
        id: 'chair_01',
        label: 'chair',
        vietnameseLabel: 'Ghế quán cóc',
        category: 'obstacle',
        score: 0.88,
        bbox: [100, 100, 80, 80],
        centerX: 0.50,
        bottomY: 0.85,
        areaRatio: 0.15,
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.critical,
        approximateDistanceMeters: '< 1.5m',
      );

      // t = 0ms: Lần đầu tiên phát hiện -> Phải nói
      engine.process(objects2D: [threat], groundHazards: [], customNow: 0);
      expect(audio.speechInvocationCount, equals(1));
      expect(audio.spokenHistory.last, equals('Vật cản trước mặt'));

      // t = 500ms, 1200ms, 2500ms, 2900ms: Chưa quá 3000ms -> Tuyệt đối im lặng
      engine.process(objects2D: [threat], groundHazards: [], customNow: 500);
      engine.process(objects2D: [threat], groundHazards: [], customNow: 1200);
      engine.process(objects2D: [threat], groundHazards: [], customNow: 2500);
      engine.process(objects2D: [threat], groundHazards: [], customNow: 2900);
      expect(audio.speechInvocationCount, equals(1));

      // t = 3100ms: Đã qua 3 giây cooldown -> Được phép nói lần 2
      engine.process(objects2D: [threat], groundHazards: [], customNow: 3100);
      expect(audio.speechInvocationCount, equals(2));

      audio.dispose();
    });

    test('Chỉ ngắt câu khi mối đe dọa mới có mức ưu tiên cao hơn hẳn (Bậc bước xuống ngắt Vật cản thường)', () {
      final audio = AudioHapticsService(customSpeaker: (text) async {});
      final engine = AlertDecisionEngine(audio: audio);

      final normalObstacle = DetectionResult(
        id: 'chair_01',
        label: 'chair',
        vietnameseLabel: 'Ghế quán cóc',
        category: 'obstacle',
        score: 0.80,
        bbox: [100, 100, 50, 50],
        centerX: 0.50,
        bottomY: 0.85,
        areaRatio: 0.10,
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.critical,
        approximateDistanceMeters: '< 1.5m',
      );

      // t = 0ms: Vật cản bình thường trước mặt (Ưu tiên 160)
      engine.process(objects2D: [normalObstacle], groundHazards: [], customNow: 0);
      expect(audio.speechInvocationCount, equals(1));
      expect(audio.spokenHistory.last, equals('Vật cản trước mặt'));

      // t = 1000ms: Bậc bước xuống cực kỳ nguy hiểm xuất hiện (Ưu tiên 250 > 160 + 40)
      final stepDownHazard = GroundHazard(
        type: GroundHazardType.stepDown,
        vietnameseName: 'Bậc đi xuống / Mép lề',
        normalizedY: 0.85,
        confidence: 0.90,
        distanceLevel: DistanceLevel.critical,
        distanceMeters: '< 1.2m',
        isNegativeObstacle: true,
      );

      // Phải lập tức ngắt câu cũ và phát câu cảnh báo bậc bước xuống
      engine.process(objects2D: [], groundHazards: [stepDownHazard], customNow: 1000);
      expect(audio.speechInvocationCount, equals(2));
      expect(audio.spokenHistory.last, equals('Chú ý: bậc đi xuống!'));

      // t = 1500ms: Một vật cản bậc bước lên (Ưu tiên 120 < 250) xuất hiện
      final stepUpHazard = GroundHazard(
        type: GroundHazardType.stepUp,
        vietnameseName: 'Bậc tam cấp bước lên',
        normalizedY: 0.70,
        confidence: 0.80,
        distanceLevel: DistanceLevel.near,
        distanceMeters: '1.5m - 2.5m',
        isNegativeObstacle: false,
      );

      // Ưu tiên thấp hơn bậc bước xuống -> KHÔNG được phép ngắt câu
      engine.process(objects2D: [], groundHazards: [stepUpHazard], customNow: 1500);
      expect(audio.speechInvocationCount, equals(2)); // Vẫn là 2, không nói thêm

      audio.dispose();
    });
  });
}

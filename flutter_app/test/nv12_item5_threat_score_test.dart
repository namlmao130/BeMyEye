import 'package:flutter_test/flutter_test.dart';
import 'package:be_my_eye_vn/models/detection_result.dart';
import 'package:be_my_eye_vn/models/ground_hazard.dart';
import 'package:be_my_eye_vn/services/alert_decision_engine.dart';
import 'package:be_my_eye_vn/services/audio_haptics_service.dart';

void main() {
  group(
      'NV12.5 - calculateThreatScore: ground_hazard trung bình không vượt xe/người ở mức near',
      () {
    late AudioHapticsService audio;
    late AlertDecisionEngine engine;

    setUp(() {
      audio = AudioHapticsService(customSpeaker: (t) async {});
      engine = AlertDecisionEngine(audio: audio);
    });

    tearDown(() {
      audio.dispose();
    });

    test(
        'calculateThreatScore: Xe ở mức near có điểm cao hơn ground_hazard độ tin cậy trung bình',
        () {
      final vehicleNear = AlertCandidate(
        id: 'car_1',
        label: 'car',
        vietnameseLabel: 'Ô tô',
        category: 'vehicle',
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.near,
        approximateDistanceMeters: '1.5m - 3.0m',
      );

      final groundMedium = AlertCandidate(
        id: 'ground_stepUp_80',
        label: 'stepUp',
        vietnameseLabel: 'Có thể có bậc, hãy dùng gậy kiểm tra',
        category: 'ground_hazard',
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.near,
        approximateDistanceMeters: '1.5m - 2.5m',
        isMediumConfidence: true,
      );

      final scoreVehicle = engine.calculateThreatScore(vehicleNear);
      final scoreGround = engine.calculateThreatScore(groundMedium);

      // Điểm xe: 40 (near) + 50 (center) + 35 (vehicle) = 125
      // Điểm bậc trung bình: 40 (near) + 50 (center) + 10 (medium bonus) = 100
      expect(
        scoreGround,
        lessThan(scoreVehicle),
        reason:
            'Cảnh báo bậc độ tin cậy trung bình tuyệt đối không được vượt xe ở cự ly gần',
      );
      expect(scoreVehicle, equals(125));
      expect(scoreGround, equals(100));
    });

    test(
        'calculateThreatScore: Người ở mức near có điểm cao hơn ground_hazard độ tin cậy trung bình',
        () {
      final pedestrianNear = AlertCandidate(
        id: 'person_1',
        label: 'person',
        vietnameseLabel: 'Người đi bộ',
        category: 'pedestrian',
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.near,
        approximateDistanceMeters: '1.5m - 3.0m',
      );

      final groundMedium = AlertCandidate(
        id: 'ground_stepUp_80',
        label: 'stepUp',
        vietnameseLabel: 'Có thể có bậc, hãy dùng gậy kiểm tra',
        category: 'ground_hazard',
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.near,
        approximateDistanceMeters: '1.5m - 2.5m',
        isMediumConfidence: true,
      );

      final scorePerson = engine.calculateThreatScore(pedestrianNear);
      final scoreGround = engine.calculateThreatScore(groundMedium);

      // Điểm người: 40 (near) + 50 (center) + 15 (pedestrian) = 105
      // Điểm bậc trung bình: 40 (near) + 50 (center) + 10 (medium bonus) = 100
      expect(
        scoreGround,
        lessThan(scorePerson),
        reason:
            'Cảnh báo bậc độ tin cậy trung bình tuyệt đối không được vượt người ở cự ly gần',
      );
      expect(scorePerson, equals(105));
      expect(scoreGround, equals(100));
    });

    test(
        'Engine.process: Khi đồng thời có Xe near và Bậc trung bình, Xe phải được chọn làm mối đe dọa chính',
        () {
      final vehicleObj = DetectionResult(
        id: 'track_car',
        label: 'car',
        vietnameseLabel: 'Ô tô',
        category: 'vehicle',
        score: 0.90,
        bbox: [100, 100, 80, 80],
        centerX: 0.5,
        bottomY: 0.70,
        areaRatio: 0.08,
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.near,
        approximateDistanceMeters: '1.5m - 3.0m',
        isApproaching: false,
      );

      final groundMedium = GroundHazard(
        type: GroundHazardType.stepUp,
        vietnameseName: 'Có thể có bậc, hãy dùng gậy kiểm tra',
        normalizedY: 0.75,
        confidence: 0.60,
        distanceLevel: DistanceLevel.near,
        distanceMeters: '1.5m - 2.5m',
        isNegativeObstacle: false,
      );

      final threat = engine.process(
        objects2D: [vehicleObj],
        groundHazards: [groundMedium],
        genericObstacles: [],
        customNow: 1000,
      );

      expect(threat, isNotNull);
      expect(threat!.category, equals('vehicle'));
      expect(threat.label, equals('car'));
    });

    test(
        'Engine.process: Khi đồng thời có Người near và Bậc trung bình, Người phải được chọn làm mối đe dọa chính',
        () {
      final personObj = DetectionResult(
        id: 'track_person',
        label: 'person',
        vietnameseLabel: 'Người đi bộ',
        category: 'pedestrian',
        score: 0.90,
        bbox: [100, 100, 50, 90],
        centerX: 0.5,
        bottomY: 0.70,
        areaRatio: 0.05,
        direction: DirectionZone.center,
        panValue: 0.0,
        distanceLevel: DistanceLevel.near,
        approximateDistanceMeters: '1.5m - 3.0m',
        isApproaching: false,
      );

      final groundMedium = GroundHazard(
        type: GroundHazardType.stepUp,
        vietnameseName: 'Có thể có bậc, hãy dùng gậy kiểm tra',
        normalizedY: 0.75,
        confidence: 0.60,
        distanceLevel: DistanceLevel.near,
        distanceMeters: '1.5m - 2.5m',
        isNegativeObstacle: false,
      );

      final threat = engine.process(
        objects2D: [personObj],
        groundHazards: [groundMedium],
        genericObstacles: [],
        customNow: 2000,
      );

      expect(threat, isNotNull);
      expect(threat!.category, equals('pedestrian'));
      expect(threat.label, equals('person'));
    });
  });
}

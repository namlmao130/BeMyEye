import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/thresholds.dart';
import '../models/detection_result.dart';

/// audio_haptics_service.dart
/// Quản lý âm thanh định hướng Stereo Pan, giọng nói tiếng Việt ngắn gọn và rung xúc giác
/// Khắc phục Lỗi 7: Sử dụng file PCM Stereo thực tế (beep_left, beep_center, beep_right)
/// và kết hợp cao độ (Pitch mono fallback: 500Hz Trái, 750Hz Giữa, 1000Hz Phải)

enum HapticIntensity { near, critical }

typedef SpeechSpeaker = Future<void> Function(String text);

class AudioHapticsService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final SpeechSpeaker? _customSpeaker;

  int _lastSpeechTime = 0;
  int _currentSpeakingPriority = 0;
  String _currentSpeakingText = '';
  int speechInvocationCount = 0;
  final List<String> spokenHistory = [];

  // Tùy chọn đảo kênh (khi người dùng đeo ngược tai nghe L/R)
  bool isChannelsSwapped = false;
  String lastPlayedAsset = '';

  AudioHapticsService({SpeechSpeaker? customSpeaker}) : _customSpeaker = customSpeaker {
    _initTTS();
  }

  Future<void> _initTTS() async {
    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setSpeechRate(0.65); // Tốc độ nhanh dứt khoát
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // Bỏ qua trên môi trường test không có engine TTS
    }
  }

  /// Phát âm thanh bíp định hướng Stereo Pan tin cậy bằng file PCM vật lý:
  /// - Kênh Trái: 'sounds/beep_left.wav' (500 Hz, Left 100%, Right 0%)
  /// - Kênh Giữa: 'sounds/beep_center.wav' (750 Hz, Cân bằng cả 2 tai)
  /// - Kênh Phải: 'sounds/beep_right.wav' (1000 Hz, Left 0%, Right 100%)
  ///
  /// Mono Fallback: Người dùng đeo 1 tai nghe vẫn phân biệt được hướng
  /// nhờ cao độ khác nhau rõ rệt (Trái: Trầm 500Hz, Giữa: Trung 750Hz, Phải: Thanh 1000Hz)
  Future<void> playDirectionalBeep({
    required double pan,
    required int pitch,
    int durationMs = 60,
    DirectionZone? direction,
  }) async {
    try {
      DirectionZone effectiveDir;
      if (direction != null) {
        effectiveDir = direction;
      } else if (pan < -0.25) {
        effectiveDir = DirectionZone.left;
      } else if (pan > 0.25) {
        effectiveDir = DirectionZone.right;
      } else {
        effectiveDir = DirectionZone.center;
      }

      // Đảo kênh nếu người dùng bật tùy chọn đeo ngược tai nghe
      if (isChannelsSwapped) {
        if (effectiveDir == DirectionZone.left) {
          effectiveDir = DirectionZone.right;
        } else if (effectiveDir == DirectionZone.right) {
          effectiveDir = DirectionZone.left;
        }
      }

      String soundAsset;
      switch (effectiveDir) {
        case DirectionZone.left:
          soundAsset = 'sounds/beep_left.wav';
          break;
        case DirectionZone.right:
          soundAsset = 'sounds/beep_right.wav';
          break;
        case DirectionZone.center:
        default:
          soundAsset = 'sounds/beep_center.wav';
          break;
      }

      lastPlayedAsset = soundAsset;
      await _player.play(AssetSource(soundAsset), volume: 0.90);
    } catch (_) {
      // Tránh crash nếu thiết bị chưa cắm tai nghe hoặc đang bận
    }
  }

  /// Quy trình kiểm tra tai nghe Trái / Giữa / Phải trước khi xuất phát
  Future<void> runEarphoneCheckSequence({void Function(String step)? onStepChange}) async {
    // 1. Kiểm tra tai trái
    onStepChange?.call('left');
    await speakVietnamese('Tai nghe bên trái', force: true, priority: 300);
    await Future.delayed(const Duration(milliseconds: 1000));
    await playDirectionalBeep(pan: -1.0, pitch: 500, direction: DirectionZone.left);

    // 2. Kiểm tra tai giữa
    await Future.delayed(const Duration(milliseconds: 1200));
    onStepChange?.call('center');
    await speakVietnamese('Tai nghe ở giữa', force: true, priority: 300);
    await Future.delayed(const Duration(milliseconds: 1000));
    await playDirectionalBeep(pan: 0.0, pitch: 750, direction: DirectionZone.center);

    // 3. Kiểm tra tai phải
    await Future.delayed(const Duration(milliseconds: 1200));
    onStepChange?.call('right');
    await speakVietnamese('Tai nghe bên phải', force: true, priority: 300);
    await Future.delayed(const Duration(milliseconds: 1000));
    await playDirectionalBeep(pan: 1.0, pitch: 1000, direction: DirectionZone.right);

    // 4. Kết thúc
    await Future.delayed(const Duration(milliseconds: 1200));
    onStepChange?.call('done');
    await speakVietnamese('Hoàn tất kiểm tra tai nghe', force: true, priority: 300);
  }

  /// Phát giọng nói tiếng Việt ngắn gọn (Có cơ chế ngắt câu cũ khi nguy cấp hơn)
  Future<void> speakVietnamese(
    String text, {
    bool force = false,
    int priority = 0,
    int? customNow,
  }) async {
    final int now = customNow ?? DateTime.now().millisecondsSinceEpoch;
    final int elapsed = now - _lastSpeechTime;

    if (elapsed < kSpeechCooldownMs) {
      if (!force || priority <= _currentSpeakingPriority + 40) {
        return;
      }
    }

    if (force && priority > _currentSpeakingPriority) {
      try {
        await _tts.stop();
      } catch (_) {}
    }

    _lastSpeechTime = now;
    _currentSpeakingPriority = priority;
    _currentSpeakingText = text;
    speechInvocationCount++;
    spokenHistory.add(text);

    if (_customSpeaker != null) {
      await _customSpeaker(text);
      return;
    }

    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  /// Rung xúc giác phản hồi
  Future<void> triggerHaptic(HapticIntensity intensity) async {
    try {
      final bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      if (intensity == HapticIntensity.critical) {
        Vibration.vibrate(pattern: [0, 150, 50, 200]);
      } else {
        Vibration.vibrate(duration: 70);
      }
    } catch (_) {}
  }

  /// Nhịp đập giữ liên lạc (Heartbeat Pulse): Rung siêu nhẹ 35ms
  Future<void> triggerHeartbeatHaptic() async {
    try {
      final bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(duration: kHeartbeatDurationMs);
      }
    } catch (_) {}
  }

  void dispose() {
    try {
      _tts.stop();
      _player.dispose();
    } catch (_) {}
  }
}

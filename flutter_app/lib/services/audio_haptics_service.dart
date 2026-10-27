import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/thresholds.dart';

/// audio_haptics_service.dart
/// Quản lý âm thanh định hướng Stereo Pan, giọng nói tiếng Việt ngắn gọn và rung xúc giác
/// Khắc phục Lỗi 2: Tránh lặp giọng nói và cắt ngang câu liên tục.

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

  /// Phát âm thanh bíp định hướng Stereo Pan (-1.0 đến +1.0)
  Future<void> playDirectionalBeep({
    required double pan,
    required int pitch,
    int durationMs = 60,
  }) async {
    try {
      await _player.setBalance(pan.clamp(-1.0, 1.0));
      final double playbackRate = (pitch / 600.0).clamp(0.6, 2.0);
      await _player.setPlaybackRate(playbackRate);
      await _player.play(AssetSource('sounds/beep.wav'), volume: 0.85);
    } catch (_) {
      // Tránh crash nếu thiết bị chưa cắm tai nghe hoặc đang bận
    }
  }

  /// Phát giọng nói tiếng Việt ngắn gọn.
  /// Khắc phục triệt để Lỗi 2: Chỉ ngắt câu khi có mối đe dọa mới có ưu tiên cao hơn hẳn.
  Future<void> speakVietnamese(
    String text, {
    bool force = false,
    int priority = 0,
    int? customNow,
  }) async {
    final int now = customNow ?? DateTime.now().millisecondsSinceEpoch;
    final int elapsed = now - _lastSpeechTime;

    // Nếu câu đang nói chưa hết cooldown (tối thiểu 3 giây)
    if (elapsed < kSpeechCooldownMs) {
      // Chỉ cho phép ngắt câu nếu mối đe dọa mới có mức ưu tiên cao hơn hẳn (chênh lệch >= 40)
      if (!force || priority <= _currentSpeakingPriority + 40) {
        return;
      }
    }

    // Nếu đủ điều kiện ngắt câu cũ để ưu tiên câu khẩn cấp hơn
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

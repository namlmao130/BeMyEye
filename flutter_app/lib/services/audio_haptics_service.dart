import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

/// audio_haptics_service.dart
/// Quản lý âm thanh định hướng Stereo Pan, giọng nói tiếng Việt ngắn gọn và rung xúc giác

enum HapticIntensity { near, critical }

class AudioHapticsService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  int _lastSpeechTime = 0;
  static const int speechCooldownMs = 2800; // Tối đa 1 câu nói mỗi 2.8s

  AudioHapticsService() {
    _initTTS();
  }

  Future<void> _initTTS() async {
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(0.65); // Tốc độ nhanh dứt khoát
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  /// Phát âm thanh bíp định hướng Stereo Pan (-1.0 đến +1.0)
  Future<void> playDirectionalBeep({
    required double pan,
    required int pitch,
    int durationMs = 60,
  }) async {
    try {
      // Đặt vị trí cân bằng âm thanh Stereo (Left / Right)
      await _player.setBalance(pan.clamp(-1.0, 1.0));
      // Tùy chỉnh cao độ phát (Pitch)
      final double playbackRate = (pitch / 600.0).clamp(0.6, 2.0);
      await _player.setPlaybackRate(playbackRate);
      
      // Phát tệp âm thanh bíp ngắn chuẩn hóa trong assets
      await _player.play(AssetSource('sounds/beep.wav'), volume: 0.85);
    } catch (e) {
      // Tránh crash nếu phần cứng âm thanh đang bận
    }
  }

  /// Phát giọng nói tiếng Việt ngắn gọn (Có cơ chế ngắt câu cũ khi nguy cấp)
  Future<void> speakVietnamese(String text, {bool force = false}) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (!force && (now - _lastSpeechTime < speechCooldownMs)) {
      return;
    }

    if (force) {
      await _tts.stop();
    }

    _lastSpeechTime = now;
    await _tts.speak(text);
  }

  /// Rung xúc giác phản hồi
  Future<void> triggerHaptic(HapticIntensity intensity) async {
    final bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;

    if (intensity == HapticIntensity.critical) {
      // Rung dồn dập: rung 150ms, nghỉ 50ms, rung 200ms
      Vibration.vibrate(pattern: [0, 150, 50, 200]);
    } else {
      Vibration.vibrate(duration: 70);
    }
  }

  /// Nhịp đập giữ liên lạc (Heartbeat Pulse): Rung siêu nhẹ 35ms
  Future<void> triggerHeartbeatHaptic() async {
    final bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 35);
    }
  }

  void dispose() {
    _tts.stop();
    _player.dispose();
  }
}

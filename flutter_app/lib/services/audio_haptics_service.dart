import 'dart:async';

import 'package:flutter/foundation.dart';
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
  FlutterTts? _ttsInstance;
  AudioPlayer? _playerInstance;
  FlutterTts get _tts => _ttsInstance ??= FlutterTts();
  AudioPlayer get _player => _playerInstance ??= AudioPlayer();
  final SpeechSpeaker? _customSpeaker;
  final bool _hardwareEnabled;
  bool _disposed = false;
  int _speechGeneration = 0;
  int _beepGeneration = 0;
  Timer? _beepStopTimer;
  Future<void>? _ttsReady;

  int? _lastSpeechTime;
  int _currentSpeakingPriority = 0;
  int speechInvocationCount = 0;
  final List<String> spokenHistory = [];

  // Tùy chọn đảo kênh (khi người dùng đeo ngược tai nghe L/R)
  bool isChannelsSwapped = false;
  String lastPlayedAsset = '';
  int lastPlayedPitch = 0;
  int lastPlayedDurationMs = 0;
  double lastPlayedPlaybackRate = 1.0;
  bool lastIsNegativeObstacle = false;

  // Custom speakers provide an output adapter for tests/previews without
  // initializing native plugins. Hardware can explicitly be enabled alongside it.
  AudioHapticsService({SpeechSpeaker? customSpeaker, bool? hardwareEnabled})
      : _customSpeaker = customSpeaker,
        _hardwareEnabled = hardwareEnabled ?? customSpeaker == null {
    if (_hardwareEnabled) _ttsReady = _initTTS();
  }

  Future<void> _initTTS() async {
    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setSpeechRate(0.65); // Tốc độ nhanh dứt khoát
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('Không thể khởi tạo engine TTS tiếng Việt: $e');
    }
  }

  /// Phát âm thanh bíp định hướng Stereo Pan tin cậy bằng file PCM vật lý:
  /// - Kênh Trái: 'sounds/beep_left.wav' (500 Hz, Left 100%, Right 0%)
  /// - Kênh Giữa: 'sounds/beep_center.wav' (750 Hz, Cân bằng cả 2 tai)
  /// - Kênh Phải: 'sounds/beep_right.wav' (1000 Hz, Left 0%, Right 100%)
  /// - Bậc đi xuống / Vật cản âm: 'sounds/step_down.wav' (Âm trầm trượt dốc 420Hz -> 220Hz đặc thù)
  ///
  /// Mono Fallback: Người dùng đeo 1 tai nghe vẫn phân biệt được hướng
  /// nhờ cao độ khác nhau rõ rệt (Trái: Trầm 500Hz, Giữa: Trung 750Hz, Phải: Thanh 1000Hz).
  /// Tôn trọng pitch và durationMs qua tốc độ phát và lựa chọn file âm thanh phù hợp.
  Future<void> playDirectionalBeep({
    required double pan,
    required int pitch,
    int durationMs = 60,
    DirectionZone? direction,
    bool isNegativeObstacle = false,
  }) async {
    if (_disposed) return;
    final generation = ++_beepGeneration;
    _beepStopTimer?.cancel();
    lastPlayedPitch = pitch;
    lastPlayedDurationMs = durationMs;
    lastIsNegativeObstacle = isNegativeObstacle;

    try {
      String soundAsset;
      double baseFreq;

      // Tiếng "bậc đi xuống" (vật cản âm) chuyên biệt: âm trầm tụt dốc, hoàn toàn khác tiếng bíp thường
      if (isNegativeObstacle || pitch <= 340) {
        soundAsset = 'sounds/step_down.wav';
        baseFreq = 320.0;
      } else {
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

        switch (effectiveDir) {
          case DirectionZone.left:
            soundAsset = 'sounds/beep_left.wav';
            baseFreq = 500.0;
            break;
          case DirectionZone.right:
            soundAsset = 'sounds/beep_right.wav';
            baseFreq = 1000.0;
            break;
          case DirectionZone.center:
            soundAsset = 'sounds/beep_center.wav';
            baseFreq = 750.0;
            break;
        }
      }

      // Tôn trọng pitch bằng cách điều chỉnh tốc độ phát playbackRate
      final double playbackRate = (pitch > 0 && baseFreq > 0)
          ? (pitch / baseFreq).clamp(0.5, 2.0)
          : 1.0;
      lastPlayedPlaybackRate = playbackRate;
      lastPlayedAsset = soundAsset;
      if (!_hardwareEnabled) return;

      try {
        await _player.setPlaybackRate(playbackRate);
      } catch (e) {
        debugPrint('Không thể đặt playback rate cho âm cảnh báo: $e');
      }

      await _player.play(AssetSource(soundAsset), volume: 0.90);
      if (_disposed || generation != _beepGeneration) return;
      _beepStopTimer = Timer(Duration(milliseconds: durationMs), () {
        if (!_disposed && generation == _beepGeneration) {
          unawaited(_stopBeep());
        }
      });
    } catch (e) {
      debugPrint('Không thể phát âm cảnh báo định hướng: $e');
    }
  }

  /// Quy trình kiểm tra tai nghe Trái / Giữa / Phải trước khi xuất phát
  Future<void> runEarphoneCheckSequence({
    void Function(String step)? onStepChange,
  }) async {
    // 1. Kiểm tra tai trái
    onStepChange?.call('left');
    await speakVietnamese('Tai nghe bên trái', force: true, priority: 300);
    await Future.delayed(const Duration(milliseconds: 1000));
    await playDirectionalBeep(
      pan: -1.0,
      pitch: 500,
      direction: DirectionZone.left,
    );

    // 2. Kiểm tra tai giữa
    await Future.delayed(const Duration(milliseconds: 1200));
    onStepChange?.call('center');
    await speakVietnamese('Tai nghe ở giữa', force: true, priority: 300);
    await Future.delayed(const Duration(milliseconds: 1000));
    await playDirectionalBeep(
      pan: 0.0,
      pitch: 750,
      direction: DirectionZone.center,
    );

    // 3. Kiểm tra tai phải
    await Future.delayed(const Duration(milliseconds: 1200));
    onStepChange?.call('right');
    await speakVietnamese('Tai nghe bên phải', force: true, priority: 300);
    await Future.delayed(const Duration(milliseconds: 1000));
    await playDirectionalBeep(
      pan: 1.0,
      pitch: 1000,
      direction: DirectionZone.right,
    );

    // 4. Kết thúc
    await Future.delayed(const Duration(milliseconds: 1200));
    onStepChange?.call('done');
    await speakVietnamese(
      'Hoàn tất kiểm tra tai nghe',
      force: true,
      priority: 300,
    );
  }

  /// Phát giọng nói tiếng Việt ngắn gọn (Có cơ chế ngắt câu cũ khi nguy cấp hơn)
  Future<void> speakVietnamese(
    String text, {
    bool force = false,
    int priority = 0,
    int? customNow,
  }) async {
    if (_disposed) return;
    final int now = customNow ?? DateTime.now().millisecondsSinceEpoch;
    final int elapsed =
        _lastSpeechTime == null ? kSpeechCooldownMs : now - _lastSpeechTime!;

    if (elapsed < kSpeechCooldownMs) {
      if (!force &&
          priority < _currentSpeakingPriority + kSpeechInterruptPriorityDelta) {
        return;
      }
    }

    final interrupt = force ||
        priority >= _currentSpeakingPriority + kSpeechInterruptPriorityDelta;
    final generation = ++_speechGeneration;
    // Reserve synchronously so two callers cannot both pass the cooldown gate.
    _lastSpeechTime = now;
    _currentSpeakingPriority = priority;
    speechInvocationCount++;
    spokenHistory.add(text);
    if (spokenHistory.length > kSpeechHistoryLimit) spokenHistory.removeAt(0);

    final speaker = _customSpeaker;
    if (speaker != null) {
      await speaker(text);
      return;
    }

    if (!_hardwareEnabled) return;
    try {
      await _ttsReady;
      if (_disposed || generation != _speechGeneration) return;
      if (interrupt) await _tts.stop();
      if (_disposed || generation != _speechGeneration) return;
      await _tts.speak(text);
    } catch (e) {
      debugPrint('Không thể phát cảnh báo TTS: $e');
      await triggerHaptic(HapticIntensity.critical);
    }
  }

  /// Rung xúc giác phản hồi
  Future<void> triggerHaptic(HapticIntensity intensity) async {
    if (_disposed || !_hardwareEnabled) return;
    try {
      final bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      if (intensity == HapticIntensity.critical) {
        await Vibration.vibrate(pattern: [0, 150, 50, 200]);
      } else {
        await Vibration.vibrate(duration: 70);
      }
    } catch (e) {
      debugPrint('Không thể phát rung cảnh báo: $e');
    }
  }

  /// Nhịp đập giữ liên lạc (Heartbeat Pulse): Rung siêu nhẹ 35ms
  Future<void> triggerHeartbeatHaptic() async {
    if (_disposed || !_hardwareEnabled) return;
    try {
      final bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        await Vibration.vibrate(duration: kHeartbeatDurationMs);
      }
    } catch (e) {
      debugPrint('Không thể phát heartbeat haptic: $e');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _speechGeneration++;
    _beepGeneration++;
    _beepStopTimer?.cancel();
    unawaited(_disposeAsync());
  }

  Future<void> _stopBeep() async {
    try {
      await _playerInstance?.stop();
    } catch (e) {
      debugPrint('Không thể dừng âm cảnh báo: $e');
    }
  }

  Future<void> _disposeAsync() async {
    try {
      await _ttsInstance?.stop();
    } catch (e) {
      debugPrint('Không thể dừng TTS khi giải phóng: $e');
    }
    try {
      await _playerInstance?.dispose();
    } catch (e) {
      debugPrint('Không thể giải phóng trình phát âm: $e');
    }
  }
}

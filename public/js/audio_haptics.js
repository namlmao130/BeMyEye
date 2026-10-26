/**
 * audio_haptics.js
 * Quản lý phát âm thanh định hướng Stereo Pan, giọng nói tiếng Việt ngắn gọn và rung xúc giác (Haptics)
 * 
 * Bổ sung ở Giai đoạn 3:
 * - Nhịp đập giữ liên lạc (Heartbeat Haptic Pulse) rung nhẹ 35ms mỗi 12 giây yên lặng để người dùng yên tâm.
 */

class AudioHapticsEngine {
  constructor() {
    this.audioCtx = null;
    this.speechSynth = window.speechSynthesis || null;
    this.vietnameseVoice = null;
    this.isMuted = false;
    this.lastSpokenText = '';
    this.lastSpeechTime = 0;
    this.SPEECH_COOLDOWN_MS = 2800; // Giọng nói tối đa 1 lần mỗi 2.8s để chống "nói quá nhiều"
    
    this.initAudioContext();
    this.initVoice();
  }

  initAudioContext() {
    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (AudioContext) {
        this.audioCtx = new AudioContext();
      }
    } catch (e) {
      console.warn('Web Audio API không được hỗ trợ:', e);
    }
  }

  async resumeContextIfNeeded() {
    if (this.audioCtx && this.audioCtx.state === 'suspended') {
      await this.audioCtx.resume();
    }
  }

  initVoice() {
    if (!this.speechSynth) return;

    const findVoice = () => {
      const voices = this.speechSynth.getVoices();
      this.vietnameseVoice = voices.find(v => v.lang.startsWith('vi') || v.lang.includes('VIE')) || null;
    };

    findVoice();
    if (this.speechSynth.onvoiceschanged !== undefined) {
      this.speechSynth.onvoiceschanged = findVoice;
    }
  }

  /**
   * Phát tiếng bíp định hướng (Stereo Panned Beep)
   */
  playDirectionalBeep(panPosition = 0, pitch = 600, durationMs = 60) {
    if (this.isMuted || !this.audioCtx) return;

    this.resumeContextIfNeeded();

    try {
      const osc = this.audioCtx.createOscillator();
      const gain = this.audioCtx.createGain();

      osc.type = 'sine';
      osc.frequency.setValueAtTime(pitch, this.audioCtx.currentTime);

      if (this.audioCtx.createStereoPanner) {
        const panner = this.audioCtx.createStereoPanner();
        panner.pan.value = Math.max(-1, Math.min(1, panPosition));
        osc.connect(gain);
        gain.connect(panner);
        panner.connect(this.audioCtx.destination);
      } else {
        osc.connect(gain);
        gain.connect(this.audioCtx.destination);
      }

      const now = this.audioCtx.currentTime;
      const durationSec = durationMs / 1000;
      gain.gain.setValueAtTime(0.001, now);
      gain.gain.exponentialRampToValueAtTime(0.35, now + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.001, now + durationSec);

      osc.start(now);
      osc.stop(now + durationSec + 0.05);
    } catch (e) {
      console.warn('Lỗi phát âm thanh bíp:', e);
    }
  }

  /**
   * Phát giọng nói tiếng Việt ngắn gọn (Text-to-Speech)
   */
  speakVietnamese(text, force = false) {
    if (this.isMuted || !this.speechSynth) return;

    const now = Date.now();
    if (!force && (now - this.lastSpeechTime < this.SPEECH_COOLDOWN_MS)) {
      return;
    }

    if (this.speechSynth.speaking && !force) {
      return;
    }

    if (force) {
      this.speechSynth.cancel();
    }

    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = 'vi-VN';
    utterance.rate = 1.2;
    utterance.pitch = 1.0;
    if (this.vietnameseVoice) {
      utterance.voice = this.vietnameseVoice;
    }

    this.lastSpokenText = text;
    this.lastSpeechTime = now;
    this.speechSynth.speak(utterance);
  }

  /**
   * Kích hoạt rung (Haptic Feedback)
   */
  triggerHaptic(level = 'near') {
    if (!('vibrate' in navigator)) return;

    try {
      if (level === 'critical') {
        navigator.vibrate([150, 50, 200]);
      } else if (level === 'near') {
        navigator.vibrate(70);
      }
    } catch (e) {
      console.warn('Lỗi kích hoạt rung:', e);
    }
  }

  /**
   * Nhịp đập giữ liên lạc (Heartbeat Pulse): Rung siêu nhẹ 35ms
   * Giúp người khiếm thị biết app vẫn đang chạy khi đường vắng im lặng
   */
  triggerHeartbeatHaptic() {
    if (!('vibrate' in navigator)) return;
    try {
      navigator.vibrate(35);
    } catch (e) {
      console.warn('Lỗi nhịp rung heartbeat:', e);
    }
  }
}

window.AudioHapticsEngine = AudioHapticsEngine;

/**
 * camera.js
 * Quản lý luồng Camera di động (getUserMedia) và phát lại video kiểm thử thực địa.
 */

class CameraManager {
  constructor(videoElement, canvasElement) {
    this.video = videoElement;
    this.canvas = canvasElement;
    this.ctx = canvasElement.getContext('2d');
    this.stream = null;
    this.isRunning = false;
    this.isUsingVideoFile = false;
  }

  /**
   * Khởi động camera sau của điện thoại
   */
  async startCamera() {
    this.stop();

    const constraints = {
      audio: false,
      video: {
        facingMode: { ideal: 'environment' }, // Ưu tiên camera sau
        width: { ideal: 480, max: 640 },
        height: { ideal: 360, max: 480 },
        frameRate: { ideal: 30, max: 60 }
      }
    };

    try {
      this.stream = await navigator.mediaDevices.getUserMedia(constraints);
      this.video.srcObject = this.stream;
      this.isUsingVideoFile = false;

      await new Promise((resolve) => {
        this.video.onloadedmetadata = () => {
          this.video.play();
          this.updateCanvasDimensions();
          this.isRunning = true;
          resolve();
        };
      });

      return true;
    } catch (err) {
      console.error('Không thể truy cập camera:', err);
      // Fallback thử camera bất kỳ nếu camera sau bị lỗi
      if (err.name === 'OverconstrainedError' || err.name === 'ConstraintNotSatisfiedError') {
        const fallbackStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
        this.stream = fallbackStream;
        this.video.srcObject = fallbackStream;
        await this.video.play();
        this.updateCanvasDimensions();
        this.isRunning = true;
        return true;
      }
      throw err;
    }
  }

  /**
   * Tải và phát video kiểm thử thực địa (mp4 / webm)
   * @param {File|string} videoSource - Đối tượng File từ input file hoặc URL
   */
  async loadTestVideo(videoSource) {
    this.stop();

    if (typeof videoSource === 'string') {
      this.video.src = videoSource;
    } else {
      this.video.src = URL.createObjectURL(videoSource);
    }

    this.video.srcObject = null;
    this.video.loop = true;
    this.video.muted = true;
    this.isUsingVideoFile = true;

    await new Promise((resolve) => {
      this.video.onloadedmetadata = () => {
        this.video.play();
        this.updateCanvasDimensions();
        this.isRunning = true;
        resolve();
      };
    });
  }

  updateCanvasDimensions() {
    const w = this.video.videoWidth || 640;
    const h = this.video.videoHeight || 480;
    this.canvas.width = w;
    this.canvas.height = h;
  }

  stop() {
    this.isRunning = false;
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }
    if (this.video.srcObject) {
      this.video.srcObject = null;
    }
    this.video.pause();
  }
}

window.CameraManager = CameraManager;

/**
 * metrics_logger.js
 * Quản lý đo đạc định lượng hiệu năng và độ chính xác:
 * 1. FPS thực tế (Rolling Average).
 * 2. Độ trễ suy luận AI (Latency ms).
 * 3. Ghi lại dữ liệu kiểm thử (Session Recording).
 * 4. Đếm số lần Bỏ sót (False Negatives) và Báo nhầm (False Positives) do người kiểm thử bấm ghi nhận.
 * 5. Xuất báo cáo JSON kiểm thử định lượng.
 */

class MetricsLogger {
  constructor() {
    this.fps = 0;
    this.latency = 0;
    this.frameCount = 0;
    this.lastTime = performance.now();
    this.fpsHistory = [];
    this.latencyHistory = [];

    // Phiên ghi log số liệu
    this.isRecording = false;
    this.sessionStartTime = 0;
    this.recordedFrames = 0;
    this.totalLatencySum = 0;
    this.detectionsByClass = {};
    this.userReportedMisses = 0;      // Số lần bỏ sót (người kiểm thử bấm nút)
    this.userReportedFalseAlarms = 0; // Số lần báo nhầm (người kiểm thử bấm nút)
    this.userReportedGoods = 0;       // Số lần cảnh báo tốt / kịp thời
  }

  /**
   * Cập nhật sau mỗi frame xử lý
   * @param {number} latencyMs - Thời gian từ lúc lấy frame đến khi ra quyết định
   */
  update(latencyMs) {
    const now = performance.now();
    this.frameCount++;

    // Tính FPS tức thời
    const delta = (now - this.lastTime) / 1000;
    if (delta >= 0.5) {
      this.fps = Math.round((this.frameCount / delta) * 10) / 10;
      this.frameCount = 0;
      this.lastTime = now;
      this.fpsHistory.push(this.fps);
      if (this.fpsHistory.length > 30) this.fpsHistory.shift();
    }

    // Lưu độ trễ
    this.latency = Math.round(latencyMs);
    this.latencyHistory.push(this.latency);
    if (this.latencyHistory.length > 30) this.latencyHistory.shift();

    // Nếu đang trong phiên ghi dữ liệu
    if (this.isRecording) {
      this.recordedFrames++;
      this.totalLatencySum += latencyMs;
    }
  }

  recordDetections(analyzedObjects) {
    if (!this.isRecording || !analyzedObjects) return;

    for (const obj of analyzedObjects) {
      this.detectionsByClass[obj.class] = (this.detectionsByClass[obj.class] || 0) + 1;
    }
  }

  startRecording() {
    this.isRecording = true;
    this.sessionStartTime = Date.now();
    this.recordedFrames = 0;
    this.totalLatencySum = 0;
    this.detectionsByClass = {};
    this.userReportedMisses = 0;
    this.userReportedFalseAlarms = 0;
  }

  stopRecording() {
    this.isRecording = false;
    const durationSec = (Date.now() - this.sessionStartTime) / 1000;
    const avgLatency = this.recordedFrames > 0 ? Math.round(this.totalLatencySum / this.recordedFrames) : 0;
    const avgFps = durationSec > 0 ? Math.round((this.recordedFrames / durationSec) * 10) / 10 : 0;

    return {
      durationSeconds: Math.round(durationSec),
      totalFrames: this.recordedFrames,
      averageFPS: avgFps,
      averageLatencyMs: avgLatency,
      detectionsByClass: this.detectionsByClass,
      userReportedMisses: this.userReportedMisses,
      userReportedFalseAlarms: this.userReportedFalseAlarms,
      date: new Date().toISOString()
    };
  }

  markGoodAlert() {
    this.userReportedGoods++;
    return this.userReportedGoods;
  }

  markMissedObstacle() {
    this.userReportedMisses++;
    return this.userReportedMisses;
  }

  markFalseAlarm() {
    this.userReportedFalseAlarms++;
    return this.userReportedFalseAlarms;
  }
}

window.MetricsLogger = MetricsLogger;

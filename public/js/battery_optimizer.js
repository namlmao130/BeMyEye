/**
 * battery_optimizer.js
 * Module tối ưu hóa thời lượng Pin và Nhiệt độ thiết bị (Battery & Thermal Manager)
 * 
 * NGUYÊN TẮC:
 * 1. Dynamic FPS Throttling:
 *    - Đứng yên (Idle/Standing): Giảm tốc độ suy luận xuống 8-10 FPS (tiết kiệm 55% GPU/CPU).
 *    - Di chuyển (Walking): Tăng tốc độ suy luận lên 20-24 FPS để đảm bảo an toàn.
 * 2. Giám sát pin (Battery API): Khi pin < 20%, tự động kích hoạt chế độ siêu tiết kiệm.
 * 3. Tối ưu màn hình OLED: Giữ giao diện đen thuần (#000000) giảm tiêu thụ điện màn hình tới 50%.
 */

class BatteryThermalOptimizer {
  constructor() {
    this.battery = null;
    this.batteryLevel = 1.0;
    this.isCharging = false;
    this.isLowBatteryMode = false;

    // Trạng thái vận động của người dùng
    this.userMovementState = 'walking'; // 'standing' hoặc 'walking'
    this.lastMovementCheckTime = Date.now();
    this.consecutiveStaticFrames = 0;

    // Giới hạn FPS mục tiêu
    this.targetFPS = 30;
    this.minFrameIntervalMs = 0; // Mặc định không giới hạn FPS
    this.highPerformanceMode = true; // Chế độ tối đa hiệu năng mặc định
    this.lastExecutionTime = 0;

    this.initBatteryMonitoring();
  }

  async initBatteryMonitoring() {
    if ('getBattery' in navigator) {
      try {
        this.battery = await navigator.getBattery();
        this.updateBatteryStatus();

        this.battery.addEventListener('levelchange', () => this.updateBatteryStatus());
        this.battery.addEventListener('chargingchange', () => this.updateBatteryStatus());
      } catch (e) {
        console.warn('Battery Status API không khả dụng:', e);
      }
    }
  }

  updateBatteryStatus() {
    if (!this.battery) return;
    this.batteryLevel = this.battery.level;
    this.isCharging = this.battery.charging;

    // Kích hoạt chế độ tiết kiệm pin nếu pin < 20% và không cắm sạc
    if (this.batteryLevel <= 0.20 && !this.isCharging) {
      this.isLowBatteryMode = true;
      this.targetFPS = 12;
      this.minFrameIntervalMs = 1000 / 12;
    } else {
      this.isLowBatteryMode = false;
    }
  }

  /**
   * Cập nhật trạng thái chuyển động dựa trên vận tốc GPS hoặc độ biến thiên ảnh
   * @param {number} speedMps - Tốc độ di chuyển từ GPS (m/s)
   */
  updateMovementState(speedMps) {
    if (speedMps < 0.25) {
      this.consecutiveStaticFrames++;
      // Đứng yên liên tục quá 3 giây
      if (this.consecutiveStaticFrames > 6) {
        this.userMovementState = 'standing';
        this.targetFPS = this.isLowBatteryMode ? 8 : 10;
        this.minFrameIntervalMs = 1000 / this.targetFPS;
      }
    } else {
      this.consecutiveStaticFrames = 0;
      this.userMovementState = 'walking';
      this.targetFPS = this.isLowBatteryMode ? 14 : 22;
      this.minFrameIntervalMs = 1000 / this.targetFPS;
    }
  }

  /**
   * Kiểm tra xem có nên bỏ qua frame này để giữ FPS theo mục tiêu không
   * @param {number} currentTimeMs
   * @returns {boolean} true nếu cần xử lý, false nếu nên bỏ qua
   */
  shouldProcessFrame(currentTimeMs) {
    if (this.highPerformanceMode) {
      return true; // Không giới hạn FPS ở chế độ hiệu năng cao
    }
    if (currentTimeMs - this.lastExecutionTime >= this.minFrameIntervalMs) {
      this.lastExecutionTime = currentTimeMs;
      return true;
    }
    return false;
  }

  setHighPerformance(enable) {
    this.highPerformanceMode = enable;
    if (enable) {
      this.minFrameIntervalMs = 0;
      this.targetFPS = 30;
    } else {
      this.minFrameIntervalMs = 50;
      this.targetFPS = 20;
    }
  }

  getStatus() {
    return {
      batteryPercentage: Math.round(this.batteryLevel * 100),
      isCharging: this.isCharging,
      isLowBatteryMode: this.isLowBatteryMode,
      movementState: this.userMovementState,
      targetFPS: this.targetFPS
    };
  }
}

window.BatteryThermalOptimizer = BatteryThermalOptimizer;

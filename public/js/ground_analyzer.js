/**
 * ground_analyzer.js
 * Module phân đoạn mặt phẳng đường và phát hiện Bậc thềm / Lề đường / Hố sụt (Curb & Step Detection)
 * 
 * NGUYÊN TẮC HOẠT ĐỘNG:
 * 1. Giả định mặt phẳng sàn (Ground Plane Assumption): Với camera nghiêng góc 15-20 độ,
 *    mặt đường phẳng có gradient độ sâu và kết cấu thay đổi tuyến tính từ đáy ảnh lên chân trời.
 * 2. Bậc bước lên (Step Up): Xuất hiện đường biên ngang (Horizontal edge) có độ tương phản cao,
 *    kèm theo bề mặt đứng làm gián đoạn độ dốc sàn.
 * 3. Bậc bước xuống / Lề đường tụt dốc (Step Down / Curb Drop-off):
 *    Hiện tượng đứt gãy kết cấu mặt đất (Texture gradient drop) - Đây là vật cản âm nguy hiểm nhất.
 * 4. Phân đoạn vùng di chuyển an toàn (Free Space Corridor).
 */

class GroundPlaneAnalyzer {
  constructor() {
    // Kích thước canvas xử lý nhỏ để đảm bảo tốc độ cực cao (>= 30 FPS)
    this.PROC_WIDTH = 160;
    this.PROC_HEIGHT = 120;
    
    this.offscreenCanvas = document.createElement('canvas');
    this.offscreenCanvas.width = this.PROC_WIDTH;
    this.offscreenCanvas.height = this.PROC_HEIGHT;
    this.ctx = this.offscreenCanvas.getContext('2d', { willReadFrequently: true });

    // Ngưỡng phát hiện
    this.EDGE_THRESHOLD = 38;             // Ngưỡng biên độ Sobel ngang
    this.MIN_STEP_WIDTH_RATIO = 0.35;      // Bậc thềm phải dài tối thiểu 35% chiều rộng hành lang
    this.GROUND_HORIZON_Y = 0.40;          // Vạch chân trời giả định (40% từ trên xuống)
    
    // Lịch sử phát hiện để chống nhiễu rung lắc bước chân (Temporal Filtering / Hysteresis)
    this.recentHazards = [];
    this.HISTORY_SIZE = 8;
  }

  /**
   * Phân tích khung hình tìm bậc thềm, mép lề đường và vùng đất trống
   * @param {HTMLVideoElement|HTMLCanvasElement} inputElement
   * @returns {Object} { hazards: Array, freeSpacePolygon: Array, groundMask: ImageData }
   */
  analyze(inputElement) {
    if (!inputElement) return { hazards: [], freeSpacePolygon: [] };

    // 1. Vẽ frame thu nhỏ vào offscreen canvas
    this.ctx.drawImage(inputElement, 0, 0, this.PROC_WIDTH, this.PROC_HEIGHT);
    const imgData = this.ctx.getImageData(0, 0, this.PROC_WIDTH, this.PROC_HEIGHT);
    const data = imgData.data;

    // 2. Chuyển sang ảnh xám (Grayscale)
    const gray = new Uint8ClampedArray(this.PROC_WIDTH * this.PROC_HEIGHT);
    for (let i = 0, j = 0; i < data.length; i += 4, j++) {
      // Y = 0.299R + 0.587G + 0.114B
      gray[j] = (data[i] * 77 + data[i + 1] * 150 + data[i + 2] * 29) >> 8;
    }

    // 3. Quét biên ngang Sobel ở nửa dưới khung hình (vùng mặt đất: từ y = 45% đến 95%)
    const startY = Math.floor(this.PROC_HEIGHT * this.GROUND_HORIZON_Y);
    const endY = Math.floor(this.PROC_HEIGHT * 0.95);
    const hazards = [];

    // Ma trận Sobel ngang (Horizontal Kernel) để bắt các cạnh bậc thềm nằm ngang
    // [-1, -2, -1]
    // [ 0,  0,  0]
    // [ 1,  2,  1]
    const rowEdgeStrength = new Float32Array(this.PROC_HEIGHT);

    for (let y = startY + 1; y < endY - 1; y++) {
      let horizontalEdgeSum = 0;
      let edgeCountInRow = 0;

      for (let x = 10; x < this.PROC_WIDTH - 10; x++) {
        const idx = y * this.PROC_WIDTH + x;

        // Sobel Y (Horizontal Edge gradient)
        const gy = 
          -gray[idx - this.PROC_WIDTH - 1] - 2 * gray[idx - this.PROC_WIDTH] - gray[idx - this.PROC_WIDTH + 1] +
           gray[idx + this.PROC_WIDTH - 1] + 2 * gray[idx + this.PROC_WIDTH] + gray[idx + this.PROC_WIDTH + 1];

        const absGy = Math.abs(gy);
        if (absGy > this.EDGE_THRESHOLD * 4) {
          horizontalEdgeSum += absGy;
          edgeCountInRow++;
        }
      }

      // Nếu có đủ số pixel cạnh ngang liên tục tạo thành một đường lề/bậc
      if (edgeCountInRow > this.PROC_WIDTH * this.MIN_STEP_WIDTH_RATIO) {
        rowEdgeStrength[y] = horizontalEdgeSum / edgeCountInRow;
      }
    }

    // 4. Tìm các đỉnh (Peaks) thể hiện gờ bậc thềm / lề đường
    for (let y = startY + 2; y < endY - 2; y++) {
      if (rowEdgeStrength[y] > 180 &&
          rowEdgeStrength[y] > rowEdgeStrength[y - 1] &&
          rowEdgeStrength[y] > rowEdgeStrength[y + 1]) {
        
        // Tính vị trí tương đối
        const normalizedY = y / this.PROC_HEIGHT;
        
        // Phân loại: Dựa trên độ chênh lệch cường độ sáng trước và sau mép
        // Nếu phía trên mép tối hơn phía dưới -> Bậc đi lên (Step Up)
        // Nếu phía trên mép sáng hơn hoặc tụt dốc -> Bậc đi xuống / Lề đường (Step Down / Curb)
        let intensityAbove = 0;
        let intensityBelow = 0;
        const checkRange = 3;

        for (let x = Math.floor(this.PROC_WIDTH * 0.3); x < Math.floor(this.PROC_WIDTH * 0.7); x++) {
          intensityAbove += gray[(y - checkRange) * this.PROC_WIDTH + x];
          intensityBelow += gray[(y + checkRange) * this.PROC_WIDTH + x];
        }

        const isStepDown = (intensityAbove > intensityBelow + 15);
        const type = isStepDown ? 'step_down' : 'step_up';

        // Ước lượng cự ly bậc thềm
        let distanceLevel = 'near';
        let distanceMeters = '1.5m - 2.5m';
        if (normalizedY >= 0.78) {
          distanceLevel = 'critical'; // Rất sát chân người đi bộ (< 1.2m)
          distanceMeters = '< 1.2m';
        } else if (normalizedY < 0.58) {
          distanceLevel = 'far';
          distanceMeters = '> 3.0m';
        }

        hazards.push({
          type: type,
          vietnameseName: isStepDown ? 'Bậc đi xuống / Mép lề' : 'Bậc tam cấp bước lên',
          normalizedY: normalizedY,
          confidence: Math.min(0.95, rowEdgeStrength[y] / 300),
          distanceLevel: distanceLevel,
          distanceMeters: distanceMeters,
          isNegativeObstacle: isStepDown // Cực kỳ nguy hiểm nếu là bậc đi xuống
        });

        // Bỏ qua các dòng kế tiếp để không bị trùng 1 bậc
        y += 6;
      }
    }

    // Lọc chống rung (Temporal filter): Chỉ giữ lại hiểm họa nếu xuất hiện ổn định
    const stableHazards = this.filterTemporalHazards(hazards);

    return {
      hazards: stableHazards,
      procWidth: this.PROC_WIDTH,
      procHeight: this.PROC_HEIGHT
    };
  }

  /**
   * Bộ lọc làm mượt qua thời gian (Temporal Hysteresis) để tránh báo nhầm do rung lắc khi đi bộ
   */
  filterTemporalHazards(currentHazards) {
    this.recentHazards.push(currentHazards);
    if (this.recentHazards.length > this.HISTORY_SIZE) {
      this.recentHazards.shift();
    }

    if (currentHazards.length === 0) return [];

    // Đếm số lần xuất hiện ở độ cao tương tự trong 5 frame gần nhất
    const confirmed = [];
    for (const h of currentHazards) {
      let hitCount = 0;
      for (const pastList of this.recentHazards) {
        if (pastList.some(past => Math.abs(past.normalizedY - h.normalizedY) < 0.08 && past.type === h.type)) {
          hitCount++;
        }
      }

      // Cần xuất hiện ít nhất 3/8 frame để xác nhận không phải nhiễu rung lắc bước chân
      if (hitCount >= 3) {
        confirmed.push(h);
      }
    }

    return confirmed;
  }
}

window.GroundPlaneAnalyzer = GroundPlaneAnalyzer;

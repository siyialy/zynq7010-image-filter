// ============================================================================
// image_rom_src.v —— 图片 ROM 图像源（把一张照片显示到屏幕上）  V1.1
//
// 【作用】
//   把 320x240 的灰度图（存在 BRAM 里）按 3 倍放大显示到 1280x720 的屏上：
//
//     sss  ← 每个源像素显示成 3x3
//
//   960x720 正好占满屏幕高度，左右各留 160 像素黑边（长宽比不变形）。
//
// 【V1.1 改动：地址计算拆成两级流水】
//   V1.0 把「x-160 → ÷3 → ×320 + sx → BRAM 地址」全挤在一拍，
//   实测 WNS = -3.444ns（21 级逻辑、13 个 CARRY4），75MHz 跑不动。
//   拆成"先算 sx/sy 并寄存，再算 sy*320+sx"两级后，每级只有约 6~7ns。
//   总延迟仍是 3 拍（因为坐标本来就延了 3 拍）。
// ============================================================================
`timescale 1ns / 1ps

module image_rom_src #(
    parameter IMG_W   = 320,
    parameter IMG_H   = 240,
    parameter SCALE   = 3,
    parameter DISP_W  = 1280,
    parameter DISP_H  = 720,
    parameter MEM_FILE = "image_gray.mem"
)(
    input  wire        clk,
    input  wire        rst_n,

    // 显示坐标（来自 video_timing_gen）
    input  wire        de,
    input  wire [15:0] x,
    input  wire [15:0] y,

    // 输出（延迟 4 拍，de/x/y/rgb 互相对齐）
    output wire        de_o,
    output wire [15:0] x_o,
    output wire [15:0] y_o,
    output wire [23:0] rgb_o
);

    localparam IMG_PIX    = IMG_W * IMG_H;                // 76800
    localparam DISP_IMG_W = IMG_W * SCALE;                // 放大后的宽
    localparam DISP_IMG_H = IMG_H * SCALE;                // 放大后的高

    // ------------------------------------------------------------------
    // 两种显示模式（自动选择，不需要改代码）：
    //   1) 图比屏小  → 居中显示，四周留黑边（letterbox）
    //   2) 图比屏大  → 居中裁剪，填满屏幕（center crop）
    //
    // 当前配置：320x240 照片 × 4 倍 = 1280x960
    //   宽 1280 == 屏宽  → 水平刚好铺满
    //   高 960  >  屏高 720 → 垂直居中裁掉上下各 120 行（源图各 30 行）
    // ------------------------------------------------------------------
    localparam VIS_W      = (DISP_IMG_W < DISP_W) ? DISP_IMG_W : DISP_W;
    localparam VIS_H      = (DISP_IMG_H < DISP_H) ? DISP_IMG_H : DISP_H;
    localparam X0         = (DISP_W - VIS_W) / 2;         // 可见窗口左上角
    localparam Y0         = (DISP_H - VIS_H) / 2;
    localparam HOFF       = (DISP_IMG_W - VIS_W) / 2;     // 裁剪偏移（居中裁）
    localparam VOFF       = (DISP_IMG_H - VIS_H) / 2;

    // ------------------------------------------------------------------
    // 图像存储：$readmemh 从 .mem 初始化（由 tools/bmp2coe.py 生成）
    // ------------------------------------------------------------------
    (* rom_style = "block" *) reg [7:0] rom [0:IMG_PIX-1];

    initial begin
        $readmemh(MEM_FILE, rom);
    end

    // ==================================================================
    // S0：算源图坐标（除法独立成一级，避免组合路径过长）
    // ==================================================================
    wire        in_win = (x >= X0) && (x < X0 + VIS_W) && (y >= Y0) && (y < Y0 + VIS_H);
    wire [15:0] xr     = x - X0 + HOFF;
    wire [15:0] yr     = y - Y0 + VOFF;

    reg [8:0] sx_r, sy_r;
    reg       win_r;

    always @(posedge clk) begin
        sx_r  <= xr / SCALE;      // 0..319
        sy_r  <= yr / SCALE;      // 裁剪模式下从 30 开始
        win_r <= in_win;
    end

    // ==================================================================
    // S1：乘加得到 BRAM 地址（第二级流水）
    // ==================================================================
    reg [16:0] addr_r;
    reg        de1, win1;
    reg [15:0] x1, y1;

    always @(posedge clk) begin
        addr_r <= sy_r * IMG_W + sx_r;   // 0..76799
        de1    <= de;
        win1   <= win_r;
        x1     <= x;
        y1     <= y;
    end

    // ==================================================================
    // S2：BRAM 同步读出
    // ==================================================================
    reg [7:0]  pix;
    reg        de2, win2;
    reg [15:0] x2, y2;

    always @(posedge clk) begin
        pix  <= rom[addr_r];
        de2  <= de1;
        win2 <= win1;
        x2   <= x1;
        y2   <= y1;
    end

    // ==================================================================
    // S3：坐标再跟一拍，与 pix 对齐后输出
    //   实测 BRAM 读出比"寄存地址"还晚一拍，
    //   否则每个源图列边界处会取到上一列的值（只在边界可见，极难查）。
    // ==================================================================
    reg        de3, win3, de4, win4;
    reg [15:0] x3, y3, x4, y4;

    always @(posedge clk) begin
        de3  <= de2;
        win3 <= win2;
        x3   <= x2;
        y3   <= y2;

        de4  <= de3;
        win4 <= win3;
        x4   <= x3;
        y4   <= y3;
    end

    // 总延迟 4 拍（坐标 4 级、BRAM 数据经 S1 地址 + S2 读出，同拍对齐）
    assign de_o  = de4;
    assign x_o   = x4;
    assign y_o   = y4;
    assign rgb_o = (win4 && de4) ? {pix, pix, pix} : 24'h000000;

endmodule

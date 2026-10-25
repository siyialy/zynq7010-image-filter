// ============================================================================
// image_rom_src.v —— 图像源（从外部缓冲区取像素，放大显示）  V1.2
//
// 【V1.2 改动：ROM 从"内部只读"改成"外部可写缓冲区"】
//   V1.1 内部自己带一个 $readmemh 的 rom；
//   V1.2 把 rom 拿出去，改由 img_buf 提供（PS 可通过 AXI 改写），
//   本模块只输出读地址、接收读数据。
//
//   这样换图不用重新综合，PS 写完 76800 字节立刻生效。
//
// 【标注通道】
//   像素字节 bit7 = 1 表示"病灶标注"，本模块把它分离成 mark_o，
//   同时把 bit[6:0] 左移一位当 8 位灰度输出。
//   红色渲染在流水线末端做（不能在滤波前染色，否则会被 3x3 糊成粉色）。
//
// 【坐标映射】
//   320x240 × 4 倍 = 1280x960，宽正好铺满，高超出 240 行 → 垂直居中裁掉上下各 120 行。
//   即：显示坐标 (x,y) → 源坐标 ((x - X0 + HOFF)/4, (y - Y0 + VOFF)/4)
//
// 【地址计算为什么拆两级】
//   把「÷4 → ×320 → +」全挤在一拍会导致 21 级逻辑、WNS -3.4ns 跑不动 75MHz。
//   拆成"先算 sx/sy 并寄存，再算 sy*320+sx"两级后每级约 6~7ns。
// ============================================================================
`timescale 1ns / 1ps

module image_rom_src #(
    parameter IMG_W     = 320,
    parameter IMG_H     = 240,
    parameter SCALE     = 4,
    parameter DISP_W    = 1280,
    parameter DISP_H    = 720,
    parameter SOFT_BG   = 0      // 32x60 background stored after the 320x240 frame
)(
    input  wire        clk,
    input  wire        rst_n,

    // 显示坐标（来自 video_timing_gen）
    input  wire        de,
    input  wire [15:0] x,
    input  wire [15:0] y,

    // ---- 外部图像缓冲区接口 ----
    output wire [16:0] raddr,      // 给 img_buf 的读地址
    input  wire [7:0]  rdata,      // img_buf 读出的数据

    // ---- 输出（延迟 4 拍，de/x/y/rgb/mark 互相对齐）----
    output wire        de_o,
    output wire [15:0] x_o,
    output wire [15:0] y_o,
    output wire [23:0] rgb_o,
    output wire        mark_o      // 1 = 该像素是病灶标注（末端渲染成红色）
);

    localparam DISP_IMG_W = IMG_W * SCALE;
    localparam DISP_IMG_H = IMG_H * SCALE;

    // 可见窗口与裁剪偏移（图像比屏大时居中裁剪）
    localparam VIS_W = (DISP_IMG_W < DISP_W) ? DISP_IMG_W : DISP_W;
    localparam VIS_H = (DISP_IMG_H < DISP_H) ? DISP_IMG_H : DISP_H;
    localparam X0    = (DISP_W - VIS_W) / 2;
    localparam Y0    = (DISP_H - VIS_H) / 2;
    localparam HOFF  = (DISP_IMG_W - VIS_W) / 2;
    localparam VOFF  = (DISP_IMG_H - VIS_H) / 2;

    // ==================================================================
    // S0：算源图坐标（除法独立成一级）
    // ==================================================================
    wire        in_win = (x >= X0) && (x < X0 + VIS_W) && (y >= Y0) && (y < Y0 + VIS_H);
    wire [15:0] xr     = x - X0 + HOFF;
    wire [15:0] yr     = y - Y0 + VOFF;

    reg [8:0] sx_r, sy_r;
    reg       bg_r;
    wire [7:0] side_x = (x < X0) ? x[7:0] : (x-(X0+VIS_W));

    always @(posedge clk) begin
        if (in_win) begin
            sx_r <= xr / SCALE;
            sy_r <= yr / SCALE;
        end else if (SOFT_BG) begin
            sx_r <= side_x / 10 + ((x < X0) ? 0 : 16);
            sy_r <= y[9:0] / 12;
        end else begin
            sx_r <= 0;
            sy_r <= 0;
        end
        bg_r <= !in_win && SOFT_BG;
    end

    // ==================================================================
    // S1：乘加得到缓冲区地址（第二级流水）
    // ==================================================================
    reg [16:0] addr_r;
    reg        de1, win1;
    reg [15:0] x1, y1;

    always @(posedge clk) begin
        addr_r <= bg_r ? (IMG_W*IMG_H + sy_r*32 + sx_r) : (sy_r * IMG_W + sx_r);
        de1    <= de;
        win1   <= in_win; // same input coordinate as x1/y1/de1 (fix one-cycle window lag)
        x1     <= x;
        y1     <= y;
    end

    // 地址直接送给 img_buf（img_buf 内部同步读，1 拍后出数据）
    assign raddr = addr_r;

    // ==================================================================
    // S2：接收缓冲区读出的数据（img_buf 已经寄存过，这里不再打拍）
    //     只把坐标/有效信号延后一拍，保持与数据对齐
    // ==================================================================
    reg [7:0]  pix;
    reg        de2, win2;
    reg [15:0] x2, y2;

    always @(posedge clk) begin
        pix  <= rdata;
        de2  <= de1;
        win2 <= win1;
        x2   <= x1;
        y2   <= y1;
    end

    // ==================================================================
    // S3：坐标再跟一拍（与 BRAM 读出延迟对齐）
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

    // 像素字节拆成「7 位灰度 + 1 位标注」
    wire [7:0] gray7 = {pix[6:0], 1'b0};     // 0..254

    assign de_o   = de4;
    assign x_o    = x4;
    assign y_o    = y4;
    assign mark_o = win4 && de4 && pix[7];
    assign rgb_o  = (de4 && (win4 || SOFT_BG)) ? {gray7, gray7, gray7} : 24'h000000;

endmodule

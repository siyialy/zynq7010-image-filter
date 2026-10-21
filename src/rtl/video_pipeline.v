// ============================================================================
// video_pipeline.v —— 完整视频流水线（图案/照片 → 3x3 滤波 → 显示）  V1.2
//
// 对外只暴露"给显示器的一套视频信号"，换 HDMI 发送方式时这个文件不用改。
//
//   video_timing_gen
//        ├──▶ test_pattern （彩条）      ──[延迟 3 拍]──┐
//        └──▶ image_rom_src（320x240 照片）──[延迟 3 拍]──┤
//                                                         ├─ src_sel 选择
//                                                         ▼
//                                              img_filter_3x3（3x3 卷积）
//                                                         │
//                                              hs/vs/de ──[延迟 LAT 拍]──▶ 输出
//
// 【V1.2 改动】加入图片 ROM 源 + src_sel 选择
//   src_sel = 0 → 彩条（安全，上电默认）
//   src_sel = 1 → 照片（320x240 灰度，3 倍放大居中显示）
//
// 【为什么 LAT 是 12】
//   滤波器自身 8 拍 + 图像源额外 4 拍 = 12 拍。
//   同步信号必须延迟同样的拍数，否则画面整体左移（见 docs/12 的说明）。
// ============================================================================
`timescale 1ns / 1ps

module video_pipeline #(
    // ---- 视频时序参数（默认 1280x720@60）----
    parameter H_VISIBLE  = 1280,
    parameter H_FP       = 110,
    parameter H_SYNC     = 40,
    parameter H_BP       = 220,
    parameter V_VISIBLE  = 720,
    parameter V_FP       = 5,
    parameter V_SYNC     = 5,
    parameter V_BP       = 20,
    parameter H_SYNC_POL = 1'b0,
    parameter V_SYNC_POL = 1'b0,
    // ---- 滤波器参数 ----
    parameter DEPTH      = 2048,   // 行缓存深度，>= 最大 x
    parameter LAT        = 12,     // 滤波器 8 + 图像源 4
    // ---- 图像源参数 ----
    parameter IMG_W      = 320,
    parameter IMG_H      = 240,
    parameter IMG_SCALE  = 4,     // 4 倍：320x240 -> 1280x960，垂直居中裁到 720 满屏
    parameter MEM_FILE   = "image_gray.mem"
)(
    input  wire        clk_pix,    // 像素时钟（720p60 为 75MHz）
    input  wire        rst_n,
    input  wire [2:0]  mode,       // 0灰度 1均值 2高斯 3Sobel
    input  wire        src_sel,    // 0=彩条  1=照片

    // ---- 对外输出：直接给 HDMI 发送器 ----
    output wire [23:0] rgb_out,
    output wire        hs_out,
    output wire        vs_out,
    output wire        de_out
);

    // ------------------------------------------------------------------
    // 1. 时序发生器
    // ------------------------------------------------------------------
    wire        hs_t, vs_t, de_t, frame_start;
    wire [15:0] x_t, y_t;

    video_timing_gen #(
        .H_VISIBLE (H_VISIBLE), .H_FP (H_FP), .H_SYNC (H_SYNC), .H_BP (H_BP),
        .V_VISIBLE (V_VISIBLE), .V_FP (V_FP), .V_SYNC (V_SYNC), .V_BP (V_BP),
        .H_SYNC_POL(H_SYNC_POL), .V_SYNC_POL(V_SYNC_POL)
    ) u_tim (
        .clk_pix     (clk_pix),
        .rst_n       (rst_n),
        .hsync       (hs_t),
        .vsync       (vs_t),
        .de          (de_t),
        .x           (x_t),
        .y           (y_t),
        .frame_start (frame_start)
    );

    // ------------------------------------------------------------------
    // 2. 图案源（彩条）+ 3 拍延迟，与照片源对齐
    // ------------------------------------------------------------------
    wire [23:0] pat_rgb;

    test_pattern #(.WIDTH(H_VISIBLE), .HEIGHT(V_VISIBLE)) u_pat (
        .clk_pix (clk_pix),
        .rst_n   (rst_n),
        .de      (de_t),
        .x       (x_t),
        .y       (y_t),
        .rgb     (pat_rgb)
    );

    reg        p_de1, p_de2, p_de3, p_de4;
    reg [15:0] p_x1, p_x2, p_x3, p_x4, p_y1, p_y2, p_y3, p_y4;
    reg [23:0] p_rgb1, p_rgb2, p_rgb3, p_rgb4;

    always @(posedge clk_pix) begin
        p_de1 <= de_t;   p_x1 <= x_t;   p_y1 <= y_t;   p_rgb1 <= pat_rgb;
        p_de2 <= p_de1;  p_x2 <= p_x1;  p_y2 <= p_y1;  p_rgb2 <= p_rgb1;
        p_de3 <= p_de2;  p_x3 <= p_x2;  p_y3 <= p_y2;  p_rgb3 <= p_rgb2;
        p_de4 <= p_de3;  p_x4 <= p_x3;  p_y4 <= p_y3;  p_rgb4 <= p_rgb3;
    end

    // ------------------------------------------------------------------
    // 3. 照片源（320x240 灰度，3 倍放大居中）
    // ------------------------------------------------------------------
    wire        r_de;
    wire [15:0] r_x, r_y;
    wire [23:0] r_rgb;

    image_rom_src #(
        .IMG_W    (IMG_W),
        .IMG_H    (IMG_H),
        .SCALE    (IMG_SCALE),
        .DISP_W   (H_VISIBLE),
        .DISP_H   (V_VISIBLE),
        .MEM_FILE (MEM_FILE)
    ) u_img (
        .clk   (clk_pix),
        .rst_n (rst_n),
        .de    (de_t),
        .x     (x_t),
        .y     (y_t),
        .de_o  (r_de),
        .x_o   (r_x),
        .y_o   (r_y),
        .rgb_o (r_rgb)
    );

    // ------------------------------------------------------------------
    // 4. 图像源选择
    // ------------------------------------------------------------------
    wire        src_de  = src_sel ? r_de   : p_de4;
    wire [15:0] src_x   = src_sel ? r_x    : p_x4;
    wire [15:0] src_y   = src_sel ? r_y    : p_y4;
    wire [23:0] src_rgb = src_sel ? r_rgb  : p_rgb4;

    // ------------------------------------------------------------------
    // 5. 3x3 滤波
    // ------------------------------------------------------------------
    wire        f_de;
    wire [15:0] f_x, f_y;
    wire [23:0] f_rgb;

    img_filter_3x3 #(.WIDTH(H_VISIBLE), .DEPTH(DEPTH)) u_flt (
        .clk     (clk_pix),
        .rst_n   (rst_n),
        .mode    (mode),
        .in_de   (src_de),
        .in_x    (src_x),
        .in_y    (src_y),
        .in_rgb  (src_rgb),
        .out_de  (f_de),
        .out_x   (f_x),
        .out_y   (f_y),
        .out_rgb (f_rgb)
    );

    // ------------------------------------------------------------------
    // 6. 同步信号延迟 LAT 拍，与滤波输出对齐
    // ------------------------------------------------------------------
    reg [LAT-1:0] hs_sr, vs_sr, de_sr;

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            hs_sr <= {LAT{1'b1}};
            vs_sr <= {LAT{1'b1}};
            de_sr <= {LAT{1'b0}};
        end
        else begin
            hs_sr <= {hs_sr[LAT-2:0], hs_t};
            vs_sr <= {vs_sr[LAT-2:0], vs_t};
            de_sr <= {de_sr[LAT-2:0], de_t};
        end
    end

    assign hs_out = hs_sr[LAT-1];
    assign vs_out = vs_sr[LAT-1];
    assign de_out = de_sr[LAT-1];

    // ------------------------------------------------------------------
    // 7. 数据输出（消隐期输出黑色）
    // ------------------------------------------------------------------
    assign rgb_out = de_out ? f_rgb : 24'h000000;

endmodule

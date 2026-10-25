// ============================================================================
// video_pipeline.v —— 完整视频流水线（图案/图像缓冲区 → 3x3 滤波 → 标注）  V1.3
//
// 对外只暴露"给显示器的一套视频信号" + "图像缓冲区的读接口"
//
//   video_timing_gen
//        ├──▶ test_pattern （彩条）                 ──[延迟 4 拍]──┐
//        └──▶ image_rom_src（缓冲区取像素，4 倍放大）──[延迟 4 拍]──┤
//                                                                   ├─ src_sel
//                                                                   ▼
//                                                        img_filter_3x3（3x3）
//                                                                   │
//                                        hs/vs/de ──[延迟 LAT 拍]──▶│
//                                                                   ▼
//                                                        【标注染色】──▶ 输出
//
// 【V1.3 改动】
//   1) 图像源改成外部可写缓冲区（raddr/rdata 引出到 system_top 的 img_buf）
//   2) 新增标注通道：图像字节 bit7 = 1 的像素，在【滤波之后】渲染成红色
//
//      为什么必须在滤波之后染色：
//        3x3 卷积会把 1 个红点糊成周围 9 个像素的粉色，
//        框线会变得又粗又虚。所以在滤波输出端，用对齐的 mark 位重新染色。
//
//      mark 的对齐：mark 从图像源出来时已延迟 4 拍，与 src_rgb 同步；
//        再延迟 8 拍（滤波器自身延迟）就与 f_rgb 对齐。
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
    parameter LAT        = 12,     // 图像源 4 + 滤波器 8
    // ---- 图像源参数 ----
    parameter IMG_W      = 320,
    parameter IMG_H      = 240,
    parameter IMG_SCALE  = 4,
    parameter SOFT_BG    = 0,
`ifdef PL_RELEASE_25
    parameter BOX_W=1536, BOX_N=32
`elsif PL_RELEASE_22
    parameter BOX_W=768, BOX_N=16
`else
    parameter BOX_W=384, BOX_N=8
`endif
)(
    input  wire        clk_pix,
    input  wire        rst_n,
    input  wire [2:0]  mode,       // 0灰度 1均值 2高斯 3Sobel
    input  wire        src_sel,    // 0=彩条  1=图像缓冲区

    // ---- 标框配置（像素域影子寄存器，由 cdc_boxes 提供）----
    input  wire [BOX_W-1:0] box_bus,
    input  wire display_hold,

    // ---- 图像缓冲区读接口（接到 system_top 的 img_buf）----
    output wire [16:0] buf_raddr,
    input  wire [7:0]  buf_rdata,

    // ---- 对外输出：直接给 HDMI 发送器 ----
    output wire [23:0] rgb_out,
    output wire        hs_out,
    output wire        vs_out,
    output wire        de_out
);

    localparam FLT_LAT = LAT - 4;   // 滤波器自身延迟 = 8

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
    // 2. 图案源（彩条）+ 4 拍延迟，与图像源对齐
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
    // 3. 图像源（从外部缓冲区取像素，4 倍放大居中裁剪）
    // ------------------------------------------------------------------
    wire        r_de;
    wire [15:0] r_x, r_y;
    wire [23:0] r_rgb;
    wire        r_mark;

    image_rom_src #(
        .IMG_W  (IMG_W),
        .IMG_H  (IMG_H),
        .SCALE  (IMG_SCALE),
        .DISP_W (H_VISIBLE),
        .DISP_H (V_VISIBLE),
        .SOFT_BG(SOFT_BG)
    ) u_img (
        .clk   (clk_pix),
        .rst_n (rst_n),
        .de    (de_t),
        .x     (x_t),
        .y     (y_t),
        .raddr (buf_raddr),
        .rdata (buf_rdata),
        .de_o  (r_de),
        .x_o   (r_x),
        .y_o   (r_y),
        .rgb_o (r_rgb),
        .mark_o(r_mark)
    );

    // ------------------------------------------------------------------
    // 4. 图像源选择（彩条没有标注位，强制 0）
    // ------------------------------------------------------------------
    wire        src_de   = src_sel ? r_de    : p_de4;
    wire [15:0] src_x    = src_sel ? r_x     : p_x4;
    wire [15:0] src_y    = src_sel ? r_y     : p_y4;
    wire [23:0] src_rgb  = src_sel ? r_rgb   : p_rgb4;
    wire        src_mark = src_sel ? r_mark  : 1'b0;

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
    // 6. 标注位延迟 FLT_LAT 拍，与滤波输出对齐
    // ------------------------------------------------------------------
    reg [FLT_LAT-1:0] mark_sr;

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) mark_sr <= {FLT_LAT{1'b0}};
        else        mark_sr <= {mark_sr[FLT_LAT-2:0], src_mark};
    end

    wire f_mark = mark_sr[FLT_LAT-1];

    // ------------------------------------------------------------------
    // 7. 标框叠加：PL 在像素流上用比较器实时画红框（零延迟、零 CPU）
    //    坐标用滤波器输出的 f_x / f_y —— 它们与 f_rgb、de_out 同拍对齐
    // ------------------------------------------------------------------
    wire box_hit;

    box_overlay #(.NB(BOX_N), .TH(3), .CW(11), .W(BOX_W)) u_overlay (
        .bus (box_bus),
        .x   (f_x),
        .y   (f_y),
        .hit (box_hit)
    );

    // ------------------------------------------------------------------
    // 8. 同步信号延迟 LAT 拍，与滤波输出对齐
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
    // 9. 输出：消隐期黑屏；标框或位标注命中 → 红色；其余用滤波结果
    // ------------------------------------------------------------------
    (* ASYNC_REG="TRUE" *) reg hold_m1,hold_m2;
    reg hold_frame;
    always @(posedge clk_pix or negedge rst_n)begin
        if(!rst_n)begin hold_m1<=0;hold_m2<=0;hold_frame<=0;end
        else begin
            hold_m1<=display_hold;hold_m2<=hold_m1;
            if(frame_start)hold_frame<=hold_m2;
        end
    end
    assign rgb_out = de_out ? (hold_frame?24'h606060:((box_hit | f_mark) ? 24'hFF0000 : f_rgb)) : 24'h000000;

endmodule

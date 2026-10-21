// ============================================================================
// video_timing_gen.v —— 视频时序发生器（第 3 个实验，项目地基）
//
// 显示器/HDMI 不认识"图像"，它只认三样东西：
//   1. 像素时钟 pix_clk ：每来一个上升沿，送出一个像素
//   2. 行同步 hsync     ：告诉显示器"这一行结束了"
//   3. 场同步 vsync     ：告诉显示器"这一帧结束了"
//   再加上 de（数据有效），表示"此刻送出的像素要显示"
//
// 时序结构（每一行 / 每一帧都一样）：
//
//   |<----- 可见区 ----->|<- 前肩 FP ->|<- 同步 SYNC ->|<- 后肩 BP ->|
//   |    640 个像素      |   16 像素   |    96 像素    |   48 像素   |
//   |<--------------------- 一行共 800 个像素 --------------------->|
//
//   垂直方向：480 可见行 + 10 前肩 + 2 同步 + 33 后肩 = 525 行
//   帧率 = 像素时钟 / (800 * 525)
//   640x480@60 需要像素时钟 25.175MHz：25.175e6 / 420000 ≈ 59.94Hz
//
// 参数默认值是 640x480@60（VGA 标准）。改成 1280x720@60 只需换参数：
//   H_VISIBLE=1280 H_FP=110 H_SYNC=40 H_BP=220 (共1650)
//   V_VISIBLE=720  V_FP=5   V_SYNC=5  V_BP=20  (共750)
//   像素时钟 74.25MHz，同步极性为正（H_SYNC_POL=1, V_SYNC_POL=1）
// ============================================================================
`timescale 1ns / 1ps

module video_timing_gen #(
    // ---- 水平方向（单位：像素时钟） ----
    parameter H_VISIBLE  = 640,
    parameter H_FP       = 16,
    parameter H_SYNC     = 96,
    parameter H_BP       = 48,
    // ---- 垂直方向（单位：行） ----
    parameter V_VISIBLE  = 480,
    parameter V_FP       = 10,
    parameter V_SYNC     = 2,
    parameter V_BP       = 33,
    // ---- 同步信号极性：0 = 低电平有效（VGA），1 = 高电平有效（720p） ----
    parameter H_SYNC_POL = 1'b0,
    parameter V_SYNC_POL = 1'b0
)(
    input  wire        clk_pix,      // 像素时钟（25.175MHz for 640x480@60）
    input  wire        rst_n,

    output wire        hsync,        // 行同步
    output wire        vsync,        // 场同步
    output wire        de,           // 数据有效：此时 x/y 对应的像素要显示
    output wire [15:0] x,            // 当前像素的列坐标 0..H_VISIBLE-1（消隐期也一直数）
    output wire [15:0] y,            // 当前像素的行坐标 0..V_VISIBLE-1
    output wire        frame_start   // 一帧第一个像素时的高电平（用于帧同步）
);

    localparam H_TOTAL = H_VISIBLE + H_FP + H_SYNC + H_BP;   // 800
    localparam V_TOTAL = V_VISIBLE + V_FP + V_SYNC + V_BP;   // 525

    reg [15:0] h_cnt;
    reg [15:0] v_cnt;

    // ------------------------------------------------------------------
    // 两个计数器：h_cnt 数像素，v_cnt 数行
    // ------------------------------------------------------------------
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 16'd0;
            v_cnt <= 16'd0;
        end
        else if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 16'd0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 16'd0;
            else
                v_cnt <= v_cnt + 1'b1;
        end
        else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // 同步信号：落在各自的同步窗口内时，输出有效电平
    // ------------------------------------------------------------------
    wire h_sync_win = (h_cnt >= H_VISIBLE + H_FP) && (h_cnt < H_VISIBLE + H_FP + H_SYNC);
    wire v_sync_win = (v_cnt >= V_VISIBLE + V_FP) && (v_cnt < V_VISIBLE + V_FP + V_SYNC);

    assign hsync = h_sync_win ? H_SYNC_POL : !H_SYNC_POL;
    assign vsync = v_sync_win ? V_SYNC_POL : !V_SYNC_POL;

    // ------------------------------------------------------------------
    // 数据有效：行、列都在可见区内
    // ------------------------------------------------------------------
    assign de = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    assign x = h_cnt;
    assign y = v_cnt;

    // 一帧的起点：h_cnt=0 且 v_cnt=0（下一级滤波器用它来复位行缓存）
    assign frame_start = (h_cnt == 16'd0) && (v_cnt == 16'd0);

endmodule

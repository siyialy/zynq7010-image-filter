// ============================================================================
// hdmi_top.v —— 完整 HDMI 输出顶层（720p60）
//
// 结构：
//   sys_clk(50MHz) ──▶ clk_wiz_0 ──▶ pixel_clk(75MHz) ─┐
//                                  └▶ pixel_clk_5x(375MHz) ─┐
//                                                           │
//   video_pipeline（彩条 → 3x3 滤波）── rgb/hs/vs/de ──▶ dvi_transmitter_top
//                                                           │
//                                              TMDS 差分对 ──▶ HDMI 接口
//
// 关键参数来自正点原子官方 22_hdmi_colorbar 例程（已核对）：
//   分辨率 1280x720@60，行总长 1650，场总行 750
//   像素时钟 75MHz，5 倍时钟 375MHz（10bit DDR 串行化 → 750Mbps/通道）
//   同步信号低有效
//
// 操作：
//   KEY0 每按一次，切换滤波模式 0→1→2→3→0，LED[1:0] 用二进制显示当前模式
//   （LED0 亮 = bit0，LED1 亮 = bit1）
// ============================================================================
`timescale 1ns / 1ps

module hdmi_top (
    input  wire       sys_clk,       // 50MHz
    input  wire       sys_rst_n,     // 低有效
    input  wire [1:0] key,           // PL KEY0/KEY1

    output wire [1:0] led,           // 显示当前模式

    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n
);

    // ------------------------------------------------------------------
    // 1. 时钟：50MHz → 75MHz（像素）/ 375MHz（5 倍）
    // ------------------------------------------------------------------
    wire pixel_clk;
    wire pixel_clk_5x;
    wire clk_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (sys_clk),
        .clk_out1 (pixel_clk),        // 75MHz
        .clk_out2 (pixel_clk_5x),     // 375MHz
        .reset    (~sys_rst_n),
        .locked   (clk_locked)
    );

    // 等 MMCM 锁定后再放开复位，否则 OSERDES 可能锁死在错误状态
    wire rst_pix_n = sys_rst_n & clk_locked;

    // ------------------------------------------------------------------
    // 2. 按键 → 滤波模式（在像素时钟域里做，避免跨时钟）
    // ------------------------------------------------------------------
    wire key0_state, key0_press;
    wire key1_state, key1_press;

    key_debounce #(
        .CLK_FREQ   (75_000_000),
        .DEBOUNCE_MS(20),
        .ACTIVE_LOW (1)
    ) u_key0 (
        .clk       (pixel_clk),
        .rst_n     (rst_pix_n),
        .key_in    (key[0]),
        .key_state (key0_state),
        .key_press (key0_press)
    );

    key_debounce #(
        .CLK_FREQ   (75_000_000),
        .DEBOUNCE_MS(20),
        .ACTIVE_LOW (1)
    ) u_key1 (
        .clk       (pixel_clk),
        .rst_n     (rst_pix_n),
        .key_in    (key[1]),
        .key_state (key1_state),
        .key_press (key1_press)
    );

    reg [1:0] mode_r;
    reg       src_sel_r;                  // 0=彩条  1=照片

    always @(posedge pixel_clk or negedge rst_pix_n) begin
        if (!rst_pix_n)
            mode_r <= 2'd0;
        else if (key0_press)
            mode_r <= mode_r + 1'b1;      // 0→1→2→3→0 循环
    end

    // KEY1 每按一次切换图像源（彩条 ↔ 照片）
    always @(posedge pixel_clk or negedge rst_pix_n) begin
        if (!rst_pix_n)
            src_sel_r <= 1'b0;            // 上电默认彩条（安全：不依赖 ROM）
        else if (key1_press)
            src_sel_r <= ~src_sel_r;
    end

    assign led = mode_r;                  // LED 二进制显示当前模式

    // ------------------------------------------------------------------
    // 3. 视频流水线：彩条 → 3x3 滤波（1280x720@60）
    // ------------------------------------------------------------------
    wire [23:0] rgb_out;
    wire        hs_out, vs_out, de_out;

    video_pipeline #(
        .H_VISIBLE (1280), .H_FP (110), .H_SYNC (40), .H_BP (220),
        .V_VISIBLE (720),  .V_FP (5),   .V_SYNC (5),  .V_BP (20),
        .H_SYNC_POL(1'b0), .V_SYNC_POL(1'b0),
        .DEPTH     (2048),       // 行缓存深度 >= 1280
        .LAT       (12)          // 滤波器 8 拍 + 图像源 4 拍
    ) u_pipeline (
        .clk_pix (pixel_clk),
        .rst_n   (rst_pix_n),
        .mode    (mode_r),
        .src_sel (src_sel_r),
        .rgb_out (rgb_out),
        .hs_out  (hs_out),
        .vs_out  (vs_out),
        .de_out  (de_out)
    );

    // ------------------------------------------------------------------
    // 4. TMDS 发送（正点原子官方实现：dvi_encoder + serializer_10_to_1）
    // ------------------------------------------------------------------
    dvi_transmitter_top u_dvi_tx (
        .pclk        (pixel_clk),
        .pclk_x5     (pixel_clk_5x),
        .reset_n     (rst_pix_n),

        .video_din   (rgb_out),
        .video_hsync (hs_out),
        .video_vsync (vs_out),
        .video_de    (de_out),

        .tmds_clk_p  (tmds_clk_p),
        .tmds_clk_n  (tmds_clk_n),
        .tmds_data_p (tmds_data_p),
        .tmds_data_n (tmds_data_n),
        .tmds_oen    ()
    );

endmodule

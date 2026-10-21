// ============================================================================
// system_top.v —— 完整系统顶层（PS + PL 协同）
//
// 结构：
//
//   ┌──────────────────────────────────────┐
//   │ Block Design (system_wrapper)        │
//   │  PS7 (ARM + DDR3 512MB + UART0)      │
//   │   └─ M_AXI_GP0 ── AXI Interconnect ──┐│
//   │                          axil_regs ◀─┘│
//   │  输 出：FCLK_CLK0(100M)              │
//   │          mode/threshold/filter_en    │
//   │          ◀── frame_cnt / status      │
//   └──────────────┬───────────────────────┘
//                  │ mode（跨时钟域：100M → 75M）
//                  ▼
//   sys_clk 50M ─▶ clk_wiz ─▶ 75M / 375M
//                  │
//                  ▼
//   video_pipeline（图案/照片 → 3x3 滤波）──▶ dvi_transmitter_top ──▶ HDMI
//
// 跨时钟域：
//   - mode/threshold/filter_en ：cdc_cfg（每位打两拍）
//   - 帧计数                   ：cdc_frame_cnt（脉冲同步 + 本地计数）
// ============================================================================
`timescale 1ns / 1ps

module system_top (
    input  wire        sys_clk,       // 50MHz
    input  wire        sys_rst_n,     // PL 复位键

    input  wire [1:0]  key,           // KEY0: 切模式(本地)  KEY1: 切图源
    output wire [1:0]  led,           // 显示当前模式

    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,

    // ---- Zynq PS 的 DDR3 / MIO（由 PS7 内部定义引脚，XDC 不需要约束）----
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);

    // ------------------------------------------------------------------
    // 1. Block Design（PS + AXI + 寄存器组）
    // ------------------------------------------------------------------
    wire        axi_clk;          // FCLK_CLK0，100MHz
    wire        axi_rst_n;        // peripheral_aresetn

    wire [2:0]  mode_axi;         // PS 写进来的模式
    wire [7:0]  thresh_axi;
    wire        filter_en_axi;
    wire [31:0] frame_cnt_axi;    // PL 数出来的帧数（已同步到 AXI 域）

    system_wrapper u_bd (
        // DDR / MIO
        .DDR_addr        (DDR_addr),
        .DDR_ba          (DDR_ba),
        .DDR_cas_n       (DDR_cas_n),
        .DDR_ck_n        (DDR_ck_n),
        .DDR_ck_p        (DDR_ck_p),
        .DDR_cke         (DDR_cke),
        .DDR_cs_n        (DDR_cs_n),
        .DDR_dm          (DDR_dm),
        .DDR_dq          (DDR_dq),
        .DDR_dqs_n       (DDR_dqs_n),
        .DDR_dqs_p       (DDR_dqs_p),
        .DDR_odt         (DDR_odt),
        .DDR_ras_n       (DDR_ras_n),
        .DDR_reset_n     (DDR_reset_n),
        .DDR_we_n        (DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio    (FIXED_IO_mio),
        .FIXED_IO_ps_clk (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),

        // 时钟/复位
        .axi_clk         (axi_clk),
        .axi_rst_n       (axi_rst_n),

        // 用户寄存器
        .mode            (mode_axi),
        .threshold       (thresh_axi),
        .filter_en       (filter_en_axi),
        .frame_cnt       (frame_cnt_axi),
        .status          (32'd0)
    );

    // ------------------------------------------------------------------
    // 2. 视频时钟：50MHz → 75MHz / 375MHz
    // ------------------------------------------------------------------
    wire pixel_clk, pixel_clk_5x, clk_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (sys_clk),
        .clk_out1 (pixel_clk),
        .clk_out2 (pixel_clk_5x),
        .reset    (~sys_rst_n),
        .locked   (clk_locked)
    );

    wire rst_pix_n = sys_rst_n & clk_locked;

    // ------------------------------------------------------------------
    // 3. 配置信号跨时钟域：AXI(100MHz) → 像素(75MHz)
    // ------------------------------------------------------------------
    wire [2:0] mode_pix;
    wire [7:0] thresh_pix;
    wire       en_pix;

    cdc_cfg #(.W(3)) u_cdc_mode (
        .clk_out(pixel_clk), .rst_out_n(rst_pix_n),
        .d_in(mode_axi), .d_out(mode_pix)
    );

    cdc_cfg #(.W(8)) u_cdc_thr (
        .clk_out(pixel_clk), .rst_out_n(rst_pix_n),
        .d_in(thresh_axi), .d_out(thresh_pix)
    );

    cdc_cfg #(.W(1)) u_cdc_en (
        .clk_out(pixel_clk), .rst_out_n(rst_pix_n),
        .d_in(filter_en_axi), .d_out(en_pix)
    );

    // ================================================================
    // 【诊断用】把两个 LED 借来测 AXI 通路（调试完改回 led = mode_pix[1:0]）
    //   PL_LED0 (led[0]) = AXI 时钟心跳：100MHz / 2^27 ≈ 0.75Hz 闪烁
    //                      → 闪 = PS 的 FCLK_CLK0 活着
    //   PL_LED1 (led[1]) = filter_en 寄存器直连（跨时钟域之前）
    //                      → 亮 = ARM 的 AXI 写真的到了寄存器
    // ================================================================
    // 注意：这里用 rst_pix_n 而不是 axi_rst_n 做复位，
    // 这样即使 AXI 域被复位卡住，只要 axi_clk 在跑，灯就会闪 —— 能区分"没时钟"和"复位卡住"
    reg [26:0] hb_cnt;
    always @(posedge axi_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) hb_cnt <= 27'd0;
        else            hb_cnt <= hb_cnt + 1'b1;
    end
    wire axi_hb = hb_cnt[26];

    // LED1 = mode_pix[1]（像素域看到的模式）
    // LED0 = mode_axi[1]（AXI 寄存器里的模式）
    //   LED0 亮 LED1 灭 → AXI 写进去了，但跨时钟域没传过去
    //   两个都灭       → AXI 寄存器就是 0，MODE 写没生效
    //   两个都亮       → 两边都是 3，那就该是 Sobel 画面了
    assign led = {mode_pix[1], mode_axi[1]};

    // ------------------------------------------------------------------
    // 4. 本地按键：KEY1 切图像源（彩条 ↔ 照片）
    // ------------------------------------------------------------------
    wire key0_state, key0_press;
    wire key1_state, key1_press;
    reg  src_sel_r;

    key_debounce #(.CLK_FREQ(75_000_000), .DEBOUNCE_MS(20), .ACTIVE_LOW(1)) u_k0 (
        .clk(pixel_clk), .rst_n(rst_pix_n), .key_in(key[0]),
        .key_state(key0_state), .key_press(key0_press)
    );

    key_debounce #(.CLK_FREQ(75_000_000), .DEBOUNCE_MS(20), .ACTIVE_LOW(1)) u_k1 (
        .clk(pixel_clk), .rst_n(rst_pix_n), .key_in(key[1]),
        .key_state(key1_state), .key_press(key1_press)
    );

    always @(posedge pixel_clk or negedge rst_pix_n) begin
        if (!rst_pix_n)          src_sel_r <= 1'b0;
        else if (key1_press)     src_sel_r <= ~src_sel_r;
    end

    // KEY0 在 PS 模式下作为"本地强制切模式"的备份（可选，便于脱离 PS 调试）
    // 这里保持简单：模式只由 PS 决定，KEY0 暂不使用
    // （如果 PS 程序没跑，PL 会用 mode=0 灰度显示）

    // ------------------------------------------------------------------
    // 5. 视频流水线
    // ------------------------------------------------------------------
    wire [23:0] rgb_out;
    wire        hs_out, vs_out, de_out;
    wire        frame_start;

    // filter_en = 0 时强制灰度（直通），= 1 时用 PS 指定的模式
    wire [2:0] mode_eff = en_pix ? mode_pix : 3'd0;

    video_pipeline #(
        .H_VISIBLE (1280), .H_FP (110), .H_SYNC (40), .H_BP (220),
        .V_VISIBLE (720),  .V_FP (5),   .V_SYNC (5),  .V_BP (20),
        .H_SYNC_POL(1'b0), .V_SYNC_POL(1'b0),
        .DEPTH     (2048),
        .LAT       (12)
    ) u_pipeline (
        .clk_pix  (pixel_clk),
        .rst_n    (rst_pix_n),
        .mode     (mode_eff),
        .src_sel  (src_sel_r),
        .rgb_out  (rgb_out),
        .hs_out   (hs_out),
        .vs_out   (vs_out),
        .de_out   (de_out)
    );

    // 帧起始：从流水线内部的时序发生器引出（每帧一个脉冲）
    // 注意 video_pipeline 没有暴露 frame_start，这里用 vs_out 的上升沿代替。
    // vs 低有效：上升沿 = 场同步结束 = 新一帧开始。
    reg vs_d;
    always @(posedge pixel_clk or negedge rst_pix_n) begin
        if (!rst_pix_n) vs_d <= 1'b1;
        else            vs_d <= vs_out;
    end
    wire frame_tick = vs_out & ~vs_d;

    // ------------------------------------------------------------------
    // 6. 帧计数：像素域 → AXI 域
    // ------------------------------------------------------------------
    cdc_frame_cnt u_frm (
        .pixel_clk   (pixel_clk),
        .pixel_rst_n (rst_pix_n),
        .frame_start (frame_tick),
        .axi_clk     (axi_clk),
        .axi_rst_n   (axi_rst_n),
        .frame_cnt   (frame_cnt_axi)
    );

    // ------------------------------------------------------------------
    // 7. TMDS 发送
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

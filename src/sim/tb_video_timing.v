// ============================================================================
// tb_video_timing.v —— 视频时序自检 testbench
//
// 检查思路：视频时序是"纯计数"问题，所以全部用**时间长度**来验证，
// 不受一两拍对齐误差影响：
//     行周期   = 800 像素 * 40ns = 32000ns
//     DE 宽度  = 640 像素 * 40ns = 25600ns
//     HSYNC 宽 =  96 像素 * 40ns =  3840ns
//     帧周期   = 800*525 像素 * 40ns = 16800000ns
//
// 时钟这里用 25MHz（周期 40ns）而不是 25.175MHz，
// 因为我们验证的是"像素个数"而不是绝对频率，整数更好算。
// 上板时由 MMCM 产生真正的 25.175MHz。
// ============================================================================
`timescale 1ns / 1ps

module tb_video_timing;

    reg  clk_pix;
    reg  rst_n;

    wire        hsync;
    wire        vsync;
    wire        de;
    wire [15:0] x;
    wire [15:0] y;
    wire        frame_start;
    wire [23:0] rgb;

    localparam CLK_PERIOD = 40;                      // 25MHz
    localparam EXP_LINE   = 800 * CLK_PERIOD;        // 32000 ns
    localparam EXP_DE     = 640 * CLK_PERIOD;        // 25600 ns
    localparam EXP_HS     =  96 * CLK_PERIOD;        //  3840 ns
    localparam EXP_FRAME  = 800 * 525 * CLK_PERIOD;  // 16800000 ns

    integer errors;
    time    t0, t1;

    // ---------- 被测模块 ----------
    video_timing_gen #(
        .H_VISIBLE (640), .H_FP (16), .H_SYNC (96),  .H_BP (48),
        .V_VISIBLE (480), .V_FP (10), .V_SYNC (2),   .V_BP (33),
        .H_SYNC_POL(1'b0), .V_SYNC_POL(1'b0)
    ) tim (
        .clk_pix     (clk_pix),
        .rst_n       (rst_n),
        .hsync       (hsync),
        .vsync       (vsync),
        .de          (de),
        .x           (x),
        .y           (y),
        .frame_start (frame_start)
    );

    test_pattern #(.WIDTH(640), .HEIGHT(480)) pat (
        .clk_pix (clk_pix),
        .rst_n   (rst_n),
        .de      (de),
        .x       (x),
        .y       (y),
        .rgb     (rgb)
    );

    // ---------- 时钟 ----------
    initial clk_pix = 1'b0;
    always #(CLK_PERIOD / 2) clk_pix = ~clk_pix;

    // ---------- 彩条采样 ----------
    task check_color;
        input [15:0] px;
        input [23:0] exp;
        begin
            wait (y == 16'd240 && x == px);
            #1;   // 等组合逻辑稳定（避免和时钟沿的竞争）
            if (rgb !== exp) begin
                $display("FAIL: x=%0d 处颜色应为 %06h，实际 %06h", px, exp, rgb);
                errors = errors + 1;
            end
            else
                $display("PASS: x=%0d 处彩条颜色 = %06h", px, rgb);
        end
    endtask

    // ---------- 主流程 ----------
    initial begin
        errors = 0;
        rst_n  = 1'b0;
        repeat (10) @(posedge clk_pix);
        rst_n = 1'b1;

        $display("=== tb_video_timing start ===");

        // ---- 检查 1：行周期 ----
        @(posedge de);
        t0 = $time;
        @(posedge de);
        t1 = $time;
        if ((t1 - t0) !== EXP_LINE) begin
            $display("FAIL: 行周期应为 %0d ns，实际 %0d ns", EXP_LINE, t1 - t0);
            errors = errors + 1;
        end
        else $display("PASS: 行周期 = %0d ns（800 像素）", t1 - t0);

        // ---- 检查 2：DE 高电平时长 = 640 像素 ----
        @(posedge de);
        t0 = $time;
        @(negedge de);
        t1 = $time;
        if ((t1 - t0) !== EXP_DE) begin
            $display("FAIL: DE 宽度应为 %0d ns，实际 %0d ns", EXP_DE, t1 - t0);
            errors = errors + 1;
        end
        else $display("PASS: DE 宽度 = %0d ns（640 像素）", t1 - t0);

        // ---- 检查 3：HSYNC 低电平时长 = 96 像素 ----
        @(negedge hsync);
        t0 = $time;
        @(posedge hsync);
        t1 = $time;
        if ((t1 - t0) !== EXP_HS) begin
            $display("FAIL: HSYNC 宽度应为 %0d ns，实际 %0d ns", EXP_HS, t1 - t0);
            errors = errors + 1;
        end
        else $display("PASS: HSYNC 低电平宽度 = %0d ns（96 像素）", t1 - t0);

        // ---- 检查 4：帧周期 = 800*525 像素 ----
        @(posedge frame_start);
        t0 = $time;
        @(posedge frame_start);
        t1 = $time;
        if ((t1 - t0) !== EXP_FRAME) begin
            $display("FAIL: 帧周期应为 %0d ns，实际 %0d ns", EXP_FRAME, t1 - t0);
            errors = errors + 1;
        end
        else $display("PASS: 帧周期 = %0d ns（800x525 像素，约 %0d.%02d ms）",
                      t1 - t0, (t1 - t0) / 1000000, ((t1 - t0) / 10000) % 100);

        // ---- 检查 5：彩条颜色（第 240 行，8 条各采一点） ----
        @(posedge frame_start);
        check_color(16'd40,  24'hFFFFFF);   // 白
        check_color(16'd120, 24'hFFFF00);   // 黄
        check_color(16'd200, 24'h00FFFF);   // 青
        check_color(16'd280, 24'h00FF00);   // 绿
        check_color(16'd360, 24'hFF00FF);   // 品红
        check_color(16'd440, 24'hFF0000);   // 红
        check_color(16'd520, 24'h0000FF);   // 蓝
        check_color(16'd600, 24'h000000);   // 黑

        // ---- 汇总 ----
        if (errors == 0)
            $display("RESULT: PASS  全部 12 项检查通过（4 项时序 + 8 项颜色）");
        else
            $display("RESULT: FAIL  有 %0d 项检查失败", errors);

        $finish;
    end

    initial begin
        #100_000_000;   // 100ms 超时
        $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule

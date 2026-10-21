// ============================================================================
// tb_video_pipeline.v —— 顶层流水线自检
//
// 验证三件事：
//   1. 输出时序对不对：行周期 800 像素、DE 宽 640、帧周期 800x525
//   2. 灰度对不对：mode=0 时 8 条彩条转灰度后的值（白255/黄226/青178/绿149/
//      品红105/红76/蓝28/黑0），这能验证 RGB->Y 的权重是否精确
//   3. Sobel 效果对不对：mode=3 时第 240 行应该出现 **7 条竖亮线**，
//      位置正好在 8 条彩条的交界处（x ≈ 80,160,...,560）
//
// 采样用 negedge：时钟下降沿时数据已稳定，避免和上升沿竞争造成 1 拍错位。
// ============================================================================
`timescale 1ns / 1ps

module tb_video_pipeline;

    localparam W    = 640;
    localparam H    = 480;
    localparam NPIX = W * H;
    localparam CLK  = 40;                 // 25MHz

    reg        clk_pix;
    reg        rst_n;
    reg  [2:0] mode;

    wire [23:0] rgb_out;
    wire        hs_out, vs_out, de_out;

    video_pipeline #(
        .H_VISIBLE(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_VISIBLE(480), .V_FP(10), .V_SYNC(2),  .V_BP(33),
        .H_SYNC_POL(1'b0), .V_SYNC_POL(1'b0),
        .DEPTH(1024), .LAT(12)
    ) dut (
        .clk_pix (clk_pix),
        .rst_n   (rst_n),
        .mode    (mode),
        .src_sel (1'b0),
        .rgb_out (rgb_out),
        .hs_out  (hs_out),
        .vs_out  (vs_out),
        .de_out  (de_out)
    );

    initial clk_pix = 1'b0;
    always #(CLK / 2) clk_pix = ~clk_pix;

    // ---------- 帧缓存 ----------
    reg [7:0] cap0 [0:NPIX-1];      // mode 0 的整帧
    reg [7:0] cap3 [0:NPIX-1];      // mode 3 的整帧
    integer   cap_cnt;
    reg       capturing;

    always @(negedge clk_pix) begin
        if (capturing && de_out && cap_cnt < NPIX) begin
            if (mode == 3'd0)      cap0[cap_cnt] = rgb_out[7:0];
            else if (mode == 3'd3) cap3[cap_cnt] = rgb_out[7:0];
            cap_cnt = cap_cnt + 1;
        end
    end

    task capture_frame;
        begin
            @(posedge vs_out);          // 帧同步（VGA vsync 低有效，上升沿=同步结束）
            @(posedge de_out);          // 第一个可见像素
            cap_cnt   = 0;
            capturing = 1'b1;
            wait (cap_cnt >= NPIX);
            capturing = 1'b0;
            repeat (10) @(posedge clk_pix);
        end
    endtask

    // ---------- 检查变量 ----------
    integer errors;
    reg     sim_done;
    time    t0, t1;
    integer i, k, val, run_cnt, run_start, run_end, center;
    integer expect_val [0:7];
    integer expect_pos [0:7];
    integer run_center [0:15];
    reg [7:0] row_val;

    initial begin
        errors = 0;
        sim_done = 1'b0;
        mode   = 3'd0;
        rst_n  = 1'b0;
        capturing = 1'b0;
        cap_cnt   = 0;
        repeat (10) @(posedge clk_pix);
        rst_n = 1'b1;
        repeat (10) @(posedge clk_pix);

        $display("=== tb_video_pipeline start ===");

        // ================= 1. 时序检查 =================
        @(posedge de_out);
        t0 = $time;
        @(posedge de_out);
        t1 = $time;
        if ((t1 - t0) !== 800 * CLK) begin
            $display("FAIL: 行周期 = %0d ns，应为 %0d ns", t1 - t0, 800 * CLK);
            errors = errors + 1;
        end else
            $display("PASS: 行周期 = %0d ns（800 像素）", t1 - t0);

        @(posedge de_out);
        t0 = $time;
        @(negedge de_out);
        t1 = $time;
        if ((t1 - t0) !== 640 * CLK) begin
            $display("FAIL: DE 宽度 = %0d ns，应为 %0d ns", t1 - t0, 640 * CLK);
            errors = errors + 1;
        end else
            $display("PASS: DE 宽度 = %0d ns（640 像素）", t1 - t0);

        @(posedge vs_out);
        t0 = $time;
        @(posedge vs_out);
        t1 = $time;
        if ((t1 - t0) !== 800 * 525 * CLK) begin
            $display("FAIL: 帧周期 = %0d ns，应为 %0d ns", t1 - t0, 800 * 525 * CLK);
            errors = errors + 1;
        end else
            $display("PASS: 帧周期 = %0d ns（800x525 像素）", t1 - t0);

        // ================= 2. mode 0：彩条转灰度 =================
        mode = 3'd0;
        capture_frame;

        expect_pos[0] = 40;  expect_val[0] = 255;   // 白
        expect_pos[1] = 120; expect_val[1] = 226;   // 黄
        expect_pos[2] = 200; expect_val[2] = 178;   // 青
        expect_pos[3] = 280; expect_val[3] = 149;   // 绿
        expect_pos[4] = 360; expect_val[4] = 105;   // 品红
        expect_pos[5] = 440; expect_val[5] = 76;    // 红
        expect_pos[6] = 520; expect_val[6] = 28;    // 蓝
        expect_pos[7] = 600; expect_val[7] = 0;     // 黑

        for (i = 0; i < 8; i = i + 1) begin
            row_val = cap0[240*W + expect_pos[i]];
            if (row_val !== expect_val[i][7:0]) begin
                $display("FAIL: mode0 x=%0d 灰度应为 %0d，实际 %0d",
                         expect_pos[i], expect_val[i], row_val);
                errors = errors + 1;
            end else
                $display("PASS: mode0 x=%0d 灰度 = %0d", expect_pos[i], row_val);
        end

        // ================= 3. mode 3：Sobel 应有 7 条竖线 =================
        mode = 3'd3;
        capture_frame;

        run_cnt = 0;
        i = 0;
        while (i < W) begin
            val = cap3[240*W + i];
            if (val > 64) begin
                run_start = i;
                while (i < W && cap3[240*W + i] > 64) i = i + 1;
                run_end = i - 1;
                center  = (run_start + run_end) / 2;
                run_center[run_cnt] = center;
                $display("  Sobel 亮线 #%0d：x = %0d ~ %0d（中心 %0d）",
                         run_cnt, run_start, run_end, center);
                run_cnt = run_cnt + 1;
            end else begin
                i = i + 1;
            end
        end

        if (run_cnt != 7) begin
            $display("FAIL: Sobel 应出现 7 条竖亮线，实际 %0d 条", run_cnt);
            errors = errors + 1;
        end else begin
            $display("PASS: Sobel 出现 7 条竖亮线（对应 8 条彩条的 7 个交界）");
            for (k = 0; k < 7; k = k + 1) begin
                if (run_center[k] < 80*(k+1) - 6 || run_center[k] > 80*(k+1) + 6) begin
                    $display("FAIL: 第 %0d 条亮线中心 %0d，应在 %0d 附近",
                             k, run_center[k], 80*(k+1));
                    errors = errors + 1;
                end
            end
            if (errors == 0)
                $display("PASS: 7 条亮线位置全部正确（80,160,240,320,400,480,560 附近）");
        end

        // ================= 汇总 =================
        sim_done = 1'b1;
        if (errors == 0)
            $display("RESULT: PASS  顶层流水线全部检查通过");
        else
            $display("RESULT: FAIL  共 %0d 项失败", errors);

        $finish;
    end

    initial begin
        #400_000_000;
        $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule

// ============================================================================
// tb_key_debounce.v —— 按键消抖的测试激励
//
// 测试思路（这是关键，以后你自己写 tb 也照这个套路）：
//   1. 正常情况：依次喂"抖动 -> 稳定按下"、"抖动 -> 稳定松开"
//   2. 检查输出：状态要对、脉冲只能出现 1 次、抖动期间不能误触发
//
// 为了仿真快，这里把 DEBOUNCE_MS 设为 1（1ms），真实板子上用 20（20ms）。
// 抖动频率设为每 5us 翻转一次，远快于消抖窗口，正好模拟机械抖动。
// ============================================================================
`timescale 1ns / 1ps

module tb_key_debounce;

    reg  clk;
    reg  rst_n;
    reg  key_in;
    wire key_state;
    wire key_press;

    localparam CLK_PERIOD = 20;   // 50MHz
    integer press_cnt;
    integer i;
    integer errors;

    // ---------- 例化被测模块 ----------
    key_debounce #(
        .CLK_FREQ    (50_000_000),
        .DEBOUNCE_MS (1),        // 仿真用 1ms
        .ACTIVE_LOW  (1)
    ) u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .key_in    (key_in),
        .key_state (key_state),
        .key_press (key_press)
    );

    // ---------- 时钟 ----------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ---------- 统计按下脉冲 ----------
    initial press_cnt = 0;
    always @(posedge key_press) press_cnt = press_cnt + 1;

    // ---------- 主流程 ----------
    initial begin
        errors  = 0;
        rst_n   = 1'b0;
        key_in  = 1'b1;      // 初始：按键松开（高电平）
        press_cnt = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        $display("=== tb_key_debounce start ===");

        // ================= 场景 1：按下（带抖动） =================
        for (i = 0; i < 20; i = i + 1) begin
            key_in = ~key_in;
            #5_000;                       // 每 5us 抖一次，共 100us
        end
        key_in = 1'b0;                    // 最终稳定为"按下"
        #2_000_000;                       // 等 2ms，远超 1ms 消抖窗口

        if (key_state !== 1'b0) begin
            $display("FAIL: 按下后 key_state 应为 0，实际 = %b", key_state); errors = errors + 1;
        end else $display("PASS: 按下后 key_state = 0（已消抖）");

        if (press_cnt !== 1) begin
            $display("FAIL: 按下应产生 1 次脉冲，实际 = %0d", press_cnt); errors = errors + 1;
        end else $display("PASS: 按下脉冲 = 1 次（抖动没有误触发）");

        // ================= 场景 2：保持按下（不应再产生脉冲） =================
        #2_000_000;
        if (press_cnt !== 1) begin
            $display("FAIL: 持续按住不应产生新脉冲，实际 = %0d", press_cnt); errors = errors + 1;
        end else $display("PASS: 按住期间无多余脉冲");

        // ================= 场景 3：松开（带抖动） =================
        for (i = 0; i < 20; i = i + 1) begin
            key_in = ~key_in;
            #5_000;
        end
        key_in = 1'b1;                    // 最终稳定为"松开"
        #2_000_000;

        if (key_state !== 1'b1) begin
            $display("FAIL: 松开后 key_state 应为 1，实际 = %b", key_state); errors = errors + 1;
        end else $display("PASS: 松开后 key_state = 1");

        if (press_cnt !== 1) begin
            $display("FAIL: 松开不应产生按下脉冲，实际 = %0d", press_cnt); errors = errors + 1;
        end else $display("PASS: 松开未误触发按下脉冲");

        // ================= 汇总 =================
        if (errors == 0)
            $display("RESULT: PASS  全部 5 项检查通过");
        else
            $display("RESULT: FAIL  有 %0d 项检查失败", errors);

        $finish;
    end

    initial begin
        #20_000_000;
        $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule

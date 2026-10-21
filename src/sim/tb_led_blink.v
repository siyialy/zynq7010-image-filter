// ============================================================================
// tb_led_blink.v  ——  测试激励（testbench）
//
// testbench 不是要上板的电路，它只在电脑上"模拟"给被测模块喂信号，
// 让你在波形窗口里看模块行为对不对。
//
// 它做 3 件事：
//   1. 产生 50MHz 时钟（周期 20ns）
//   2. 先给一段复位，再放开
//   3. 等足够长时间，数 LED 翻转了几次，打印 PASS / FAIL
//
// 注意：这里把 BLINK_HZ 改成 1000（而不是 1），让 LED 每 0.5ms 翻转一次。
// 否则仿真要跑 1 秒 = 5000 万个时钟周期，会等非常久。
// 上板时用默认的 BLINK_HZ = 1 即可。
// ============================================================================
`timescale 1ns / 1ps

module tb_led_blink;

    // ---------- 1. 给被测模块的输入"接线" ----------
    reg  clk;        // 时钟，由 testbench 驱动，所以是 reg
    reg  rst_n;      // 复位，由 testbench 驱动
    wire led;        // LED 是被测模块的输出，testbench 只能"看"，所以是 wire

    localparam CLK_PERIOD = 20;   // 50MHz -> 20ns 一个周期

    // ---------- 2. 例化被测模块（把黑盒接上线） ----------
    led_blink #(
        .CLK_FREQ (50_000_000),
        .BLINK_HZ (1000)          // 为了仿真快，加速 1000 倍
    ) u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .led      (led)
    );

    // ---------- 3. 产生时钟：每 10ns 翻转一次，得到 20ns 周期 ----------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ---------- 4. 统计 LED 上升沿次数 ----------
    integer rise_cnt;
    initial rise_cnt = 0;
    always @(posedge led) rise_cnt = rise_cnt + 1;

    // ---------- 5. 主流程 ----------
    initial begin
        $display("=== tb_led_blink start ===");

        // 复位保持 10 个时钟
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        $display("[%0t ns] reset released", $time);

        // BLINK_HZ=1000 -> 周期 1ms -> 3ms 里应该翻转 3 次
        #3_000_000;   // 3000us = 3ms

        $display("[%0t ns] rise_cnt = %0d", $time, rise_cnt);

        if (rise_cnt >= 3)
            $display("RESULT: PASS  (LED 正常翻转 %0d 次)", rise_cnt);
        else
            $display("RESULT: FAIL  (LED 只翻转 %0d 次，检查计数器逻辑)", rise_cnt);

        $finish;
    end

    // 10ms 还没结束就强制停止，避免仿真挂死
    initial begin
        #10_000_000;
        $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule

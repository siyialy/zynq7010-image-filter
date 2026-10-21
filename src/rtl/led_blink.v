// ============================================================================
// led_blink.v  ——  第 1 个 Verilog 模块：LED 闪烁
//
// 作用：用 50MHz 时钟分频，产生 1Hz 的 LED 翻转信号。
//
// 这个模块要教你的 3 件事：
//   1. module ... endmodule ：一个模块就是一个黑盒，端口写在括号里。
//   2. always @(posedge clk) ：里面描述的是"触发器"，每个时钟上升沿执行一次。
//   3. 计数器分频 ：数到 N 个时钟就翻转一次输出，这是最基础的时序逻辑。
//
// 上板时把 CLK_FREQ 设成板子实际晶振频率（以原理图为准；正点原子多数板卡 PL 晶振为 50MHz）。
// ============================================================================
`timescale 1ns / 1ps

module led_blink #(
    parameter CLK_FREQ = 50_000_000,   // 输入时钟频率，单位 Hz
    parameter BLINK_HZ = 1             // 想要的闪烁频率，单位 Hz
)(
    input  wire clk,      // 时钟输入
    input  wire rst_n,    // 复位，低有效（板子上按键按下为低）
    output reg  led       // LED 输出，1 亮 0 灭
);

    // 半个周期要数多少个时钟：1Hz 闪烁 = 每 0.5 秒翻转一次
    // 50_000_000 / (2*1) = 25_000_000
    localparam CNT_MAX = CLK_FREQ / (2 * BLINK_HZ);   // = 25000000

    reg [31:0] cnt;   // 32 位计数器，最大可数到 42 亿，够用

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时：计数器清零，LED 熄灭
            cnt <= 32'd0;
            led <= 1'b0;
        end
        else if (cnt == CNT_MAX - 1) begin
            // 数到目标值：计数器归零，LED 翻转
            cnt <= 32'd0;
            led <= ~led;
        end
        else begin
            // 其它情况：计数器 +1
            cnt <= cnt + 1'b1;
        end
    end

endmodule

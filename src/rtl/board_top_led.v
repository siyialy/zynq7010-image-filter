// ============================================================================
// board_top_led.v —— 上板点灯（第一个真实硬件工程）
//
// 这是你第一次让板子"动起来"。它同时验证四件事：
//   1. 时钟通了        —— led[0] 以 1Hz 闪烁（50MHz 分频出来）
//   2. 复位正常        —— 按下 RESET 键，LED 立刻回到初始状态
//   3. 输入通了        —— 按住 KEY1，led[0] 闪烁变成 4 倍快
//   4. 消抖 + 边沿检测  —— 每按一次 KEY0，led[1] 翻转一次（松手不会连跳）
//
// 引脚（正点原子启明星 ZYNQ7010 V2）：
//   sys_clk   U18  50MHz
//   sys_rst_n N16  低有效
//   key[0]    L14  PL KEY0
//   key[1]    K16  PL KEY1
//   led[0]    H15  PL LED0（高电平点亮）
//   led[1]    L15  PL LED1
// ============================================================================
`timescale 1ns / 1ps

module board_top_led (
    input  wire       sys_clk,      // 50MHz
    input  wire       sys_rst_n,    // 低有效复位
    input  wire [1:0] key,          // 按键，未按下为高
    output reg  [1:0] led           // 高电平点亮
);

    // ------------------------------------------------------------------
    // 按键消抖（复用第 2 个实验的模块）
    // ------------------------------------------------------------------
    wire key0_state, key0_press;
    wire key1_state, key1_press;

    key_debounce #(
        .CLK_FREQ   (50_000_000),
        .DEBOUNCE_MS(20),
        .ACTIVE_LOW (1)
    ) u_key0 (
        .clk       (sys_clk),
        .rst_n     (sys_rst_n),
        .key_in    (key[0]),
        .key_state (key0_state),
        .key_press (key0_press)
    );

    key_debounce #(
        .CLK_FREQ   (50_000_000),
        .DEBOUNCE_MS(20),
        .ACTIVE_LOW (1)
    ) u_key1 (
        .clk       (sys_clk),
        .rst_n     (sys_rst_n),
        .key_in    (key[1]),
        .key_state (key1_state),
        .key_press (key1_press)
    );

    // ------------------------------------------------------------------
    // 1Hz 心跳计数器（KEY1 按住时加速 4 倍）
    //   50MHz / 25_000_000 = 每 0.5 秒翻转一次 = 1Hz 闪烁
    // ------------------------------------------------------------------
    reg [24:0] cnt;
    wire [24:0] cnt_max = key1_state ? 25'd6_249_999     // 按住 KEY1：4Hz
                                     : 25'd24_999_999;   // 松开：1Hz

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cnt <= 25'd0;
            led[0] <= 1'b0;
        end
        else if (cnt >= cnt_max) begin
            cnt <= 25'd0;
            led[0] <= ~led[0];
        end
        else begin
            cnt <= cnt + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // led[1]：每按一次 KEY0 翻转一次（验证消抖 + 单周期脉冲）
    // ------------------------------------------------------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            led[1] <= 1'b0;
        else if (key0_press)
            led[1] <= ~led[1];
    end

endmodule

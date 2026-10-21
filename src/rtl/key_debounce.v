// ============================================================================
// key_debounce.v —— 按键消抖（第 2 个实验）
//
// 为什么需要消抖：
//   机械按键在按下/松开的瞬间，触点会在几毫秒内快速通断几十次，
//   FPGA 的 50MHz 时钟能把这些"抖动"全部采到，你会看到按一下却触发几十次。
//
// 本模块做三件事：
//   1. 两级同步器：把异步的按键信号同步到 clk 时钟域（消除亚稳态）
//   2. 计时消抖：电平稳定超过 DEBOUNCE_MS 毫秒才认账
//   3. 边沿检测：输出一个单周期脉冲 key_press，表示"刚被按下"
//
// 板子上的 PL_KEY0 未按下是高电平、按下是低电平，所以 ACTIVE_LOW = 1。
// ============================================================================
`timescale 1ns / 1ps

module key_debounce #(
    parameter CLK_FREQ    = 50_000_000,  // 时钟频率 Hz
    parameter DEBOUNCE_MS = 20,          // 消抖时间（毫秒），20ms 是常用值
    parameter ACTIVE_LOW  = 1            // 1: 按键按下为低电平
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,      // 原始按键输入（有抖动、与时钟异步）
    output reg  key_state,   // 消抖后的稳定电平（1=松开, 0=按下）
    output reg  key_press    // 按下瞬间的单周期脉冲
);

    localparam CNT_MAX = CLK_FREQ / 1000 * DEBOUNCE_MS;  // 20ms @50MHz = 1,000,000

    // ---------------------------------------------------------------
    // 第 1 步：两级同步器
    //   key_in 是外部信号，和 clk 没有任何相位关系，直接采样可能产生亚稳态。
    //   打两拍之后，信号就"属于" clk 时钟域了。
    // ---------------------------------------------------------------
    reg key_sync0, key_sync1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_sync0 <= 1'b1;
            key_sync1 <= 1'b1;
        end
        else begin
            key_sync0 <= key_in;
            key_sync1 <= key_sync0;
        end
    end

    // ---------------------------------------------------------------
    // 第 2 步：消抖 + 边沿检测
    //   拿同步后的信号和"当前已确认的稳定值"比较：
    //     不一样  -> 计数器 +1，直到数满 DEBOUNCE_MS 才更新稳定值
    //     一样    -> 说明是抖动/噪声，计数器清零
    // ---------------------------------------------------------------
    reg [23:0] cnt;        // 24 位计数器，最大 1677 万，够数 335ms@50MHz
    reg        key_state_d; // 上一拍的稳定值，用于检测边沿

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt         <= 24'd0;
            key_state   <= 1'b1;
            key_state_d <= 1'b1;
            key_press   <= 1'b0;
        end
        else begin
            // --- 消抖计时 ---
            if (key_sync1 != key_state) begin
                if (cnt >= CNT_MAX - 1) begin
                    key_state <= key_sync1;   // 稳定够久，认账
                    cnt       <= 24'd0;
                end
                else begin
                    cnt <= cnt + 1'b1;
                end
            end
            else begin
                cnt <= 24'd0;                 // 抖动，作废重来
            end

            // --- 边沿检测：产生单周期脉冲 ---
            key_state_d <= key_state;
            if (ACTIVE_LOW)
                key_press <= key_state_d & ~key_state;   // 1 -> 0，按下
            else
                key_press <= ~key_state_d & key_state;   // 0 -> 1，按下
        end
    end

endmodule

// ============================================================================
// cdc_cfg.v —— 配置信号跨时钟域同步（AXI 100MHz → 像素 75MHz）
//
// 【为什么需要】
//   PS 通过 AXI 总线写进来的 mode/threshold/filter_en 是在 AXI 时钟域，
//   而视频流水线跑在像素时钟域（75MHz）。两个时钟完全异步，
//   直接连会带来亚稳态（信号在跳变瞬间被采样，值随机）。
//
// 【做法】每个 bit 打两拍（两级触发器链）
//   这是慢速变化配置位的标准做法。mode 是 3 bit，理论上可能在切换瞬间
//   出现"混合值"（比如 1→2 的瞬间采到 3），但：
//     - 配置由人按键/菜单触发，重复写不会连发
//     - 最坏情况是某一帧用错模式，下一帧就恢复
//   对图像显示无实际影响。若要求严格，应改用握手或格雷码。
// ============================================================================
`timescale 1ns / 1ps

module cdc_cfg #(
    parameter W = 1
)(
    input  wire         clk_out,      // 目的时钟（像素时钟）
    input  wire         rst_out_n,    // 目的时钟域复位
    input  wire [W-1:0] d_in,         // 源时钟域数据（AXI）
    output wire [W-1:0] d_out         // 目的时钟域数据
);

    // ASYNC_REG 告诉工具：这是同步器寄存器，不要优化/搬移
    (* ASYNC_REG = "TRUE" *) reg [W-1:0] meta, sync;

    always @(posedge clk_out or negedge rst_out_n) begin
        if (!rst_out_n) begin
            meta <= {W{1'b0}};
            sync <= {W{1'b0}};
        end
        else begin
            meta <= d_in;      // 第一级：可能进入亚稳态
            sync <= meta;      // 第二级：稳定输出
        end
    end

    assign d_out = sync;

endmodule

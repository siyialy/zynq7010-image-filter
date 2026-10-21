// ============================================================================
// cdc_frame_cnt.v —— 帧计数器（像素 75MHz → AXI 100MHz）
//
// 【为什么不能直接数】
//   帧起始信号在像素时钟域，计数器要给 AXI 域读。如果直接把 32 位计数器
//   跨域读，可能读到"正在进位"的中间值（比如 0x0FFF → 0x1000 读到 0x1FFF）。
//
// 【做法：脉冲同步 + 本地计数】
//   1. 像素域：每来一个 frame_start，翻转一个 toggle 标志
//   2. 用两级触发器把 toggle 同步到 AXI 域
//   3. AXI 域检测 toggle 的边沿，产生一个单周期脉冲
//   4. 计数器完全在 AXI 域递增 —— 永远不会有中间值问题
//
//   这个方法对"事件计数"最稳，代价是延迟 2~3 个 AXI 时钟（10~30ns）。
// ============================================================================
`timescale 1ns / 1ps

module cdc_frame_cnt (
    // ---- 像素时钟域 ----
    input  wire        pixel_clk,
    input  wire        pixel_rst_n,
    input  wire        frame_start,     // 每帧一个脉冲

    // ---- AXI 时钟域 ----
    input  wire        axi_clk,
    input  wire        axi_rst_n,

    output reg  [31:0] frame_cnt        // 在 AXI 域递增
);

    // ---------------------------------------------------------------
    // 像素域：翻转标志
    // ---------------------------------------------------------------
    reg tog_pix;

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n)
            tog_pix <= 1'b0;
        else if (frame_start)
            tog_pix <= ~tog_pix;
    end

    // ---------------------------------------------------------------
    // 同步到 AXI 域（两级）
    // ---------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [2:0] tog_sync;

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n)
            tog_sync <= 3'b000;
        else
            tog_sync <= {tog_sync[1:0], tog_pix};
    end

    wire tick = tog_sync[2] ^ tog_sync[1];   // 边沿检测：一个 AXI 周期脉冲

    // ---------------------------------------------------------------
    // AXI 域计数
    // ---------------------------------------------------------------
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n)
            frame_cnt <= 32'd0;
        else if (tick)
            frame_cnt <= frame_cnt + 1'b1;
    end

endmodule

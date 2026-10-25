// ============================================================================
// cdc_boxes.v —— 标框配置的跨时钟域同步（AXI 100MHz → 像素 75MHz）  V1.0
//
// 【为什么需要它】
//   PS 在 AXI 时钟域写好 8 个框的坐标，但真正画框的是像素时钟域的比较器。
//   直接接过去会出问题：352 位宽的坐标总线不可能保证"同时到达"，
//   某一拍可能一半是新值一半是旧值 → 屏幕上出现一个错误的框（撕裂）。
//
// 【方案：先稳定数据，再用一位触发器发"提交"信号】
//   1. PS 先写完全部框坐标（数据在 AXI 域已稳定）
//   2. PS 再写一次 0x70 寄存器，硬件把 commit_tog 取反
//   3. 本模块把 commit_tog 打两拍同步到像素域（单比特，安全）
//   4. 检测到电平变化时，把整条总线一次性锁进影子寄存器
//
//   因为第 1 步早就完成了，锁存时数据一定是稳定的整组新值 → 不会撕裂。
//   这是多比特跨时钟域的标准做法（"数据 + 握手位"），比给每根线打两拍可靠。
// ============================================================================
`timescale 1ns / 1ps

module cdc_boxes #(
    parameter W = 384,
    parameter FRAME_LATCH = 0
)(
    // ---- AXI 域（源）----
    input  wire           clk_axi,
    input  wire           rst_axi_n,
    input  wire [W-1:0]   bus_in,
    input  wire           commit_tog,

    // ---- 像素域（目的）----
    input  wire           clk_pix,
    input  wire           rst_pix_n,
    input wire frame_tick,
    output reg  [W-1:0]   bus_out
);

    // ------------------------------------------------------------------
    // 三级同步链：前两级防亚稳态，第三级用于边沿检测
    // ------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg tog_m1, tog_m2, tog_m3;

    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            tog_m1 <= 1'b0;
            tog_m2 <= 1'b0;
            tog_m3 <= 1'b0;
        end
        else begin
            tog_m1 <= commit_tog;
            tog_m2 <= tog_m1;
            tog_m3 <= tog_m2;
        end
    end

    wire commit_pulse = tog_m2 ^ tog_m3;    // 变化的那一拍

    // ------------------------------------------------------------------
    // 锁存：拿到提交脉冲时把整组数据搬进影子寄存器
    // ------------------------------------------------------------------
    reg [W-1:0] pending_bus;
    reg pending;
    always @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin bus_out <= 0; pending_bus <= 0; pending <= 0; end
        else if (FRAME_LATCH == 0) begin
            if (commit_pulse) bus_out <= bus_in;
        end else begin
            if (commit_pulse) begin pending_bus <= bus_in; pending <= 1; end
            if (frame_tick && (pending || commit_pulse)) begin
                bus_out <= commit_pulse ? bus_in : pending_bus;
                pending <= 0;
            end
        end
    end

endmodule

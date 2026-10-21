// ============================================================================
// test_pattern.v —— 彩条测试图案（第 3 个实验的配套模块）
//
// 为什么先做彩条，而不是先接摄像头：
//   显示器出图这一环最容易出问题（黑屏、花屏、颜色错、闪烁）。
//   先用"已知正确"的彩条把显示链路打通，问题就只可能在时序/HDMI，
//   不会和摄像头的 I2C、时钟、引脚混在一起，排查快 10 倍。
//
// 8 条竖彩条，颜色顺序是标准的 SMPTE 彩条顺序：
//   白 黄 青 绿 品红 红 蓝 黑
//
// 竖彩条有"垂直硬边"，正好用来检验后面的 Sobel 边缘检测：
//   滤波后应该只看到 7 条竖向亮边，其他区域全黑。
// ============================================================================
`timescale 1ns / 1ps

module test_pattern #(
    parameter WIDTH  = 640,
    parameter HEIGHT = 480
)(
    input  wire        clk_pix,
    input  wire        rst_n,
    input  wire        de,
    input  wire [15:0] x,
    input  wire [15:0] y,
    output reg  [23:0] rgb      // {R[7:0], G[7:0], B[7:0]}
);

    localparam BW = WIDTH / 8;   // 每条彩条的宽度：640/8 = 80

    // ---- 判断当前 x 落在第几条彩条 ----
    reg [2:0] bar;
    always @(*) begin
        if      (x < BW * 1) bar = 3'd0;
        else if (x < BW * 2) bar = 3'd1;
        else if (x < BW * 3) bar = 3'd2;
        else if (x < BW * 4) bar = 3'd3;
        else if (x < BW * 5) bar = 3'd4;
        else if (x < BW * 6) bar = 3'd5;
        else if (x < BW * 7) bar = 3'd6;
        else                 bar = 3'd7;
    end

    // ---- 按彩条编号输出颜色 ----
    always @(*) begin
        if (!de)
            rgb = 24'h000000;         // 消隐期输出黑色
        else case (bar)
            3'd0: rgb = 24'hFFFFFF;   // 白
            3'd1: rgb = 24'hFFFF00;   // 黄
            3'd2: rgb = 24'h00FFFF;   // 青
            3'd3: rgb = 24'h00FF00;   // 绿
            3'd4: rgb = 24'hFF00FF;   // 品红
            3'd5: rgb = 24'hFF0000;   // 红
            3'd6: rgb = 24'h0000FF;   // 蓝
            default: rgb = 24'h000000; // 黑
        endcase
    end

endmodule

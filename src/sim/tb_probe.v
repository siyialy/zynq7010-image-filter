// ============================================================================
// tb_probe.v —— 临时诊断：图像内容 = 列号，用来量出流水线的真实偏移
// ============================================================================
`timescale 1ns / 1ps

module tb_probe;
    localparam W = 32;
    localparam H = 8;

    reg clk, rst_n;
    reg [2:0] mode;
    reg in_de;
    reg [15:0] in_x, in_y;
    reg [23:0] in_rgb;
    wire out_de;
    wire [15:0] out_x, out_y;
    wire [23:0] out_rgb;

    img_filter_3x3 #(.WIDTH(W), .DEPTH(1024)) dut (
        .clk(clk), .rst_n(rst_n), .mode(mode),
        .in_de(in_de), .in_x(in_x), .in_y(in_y), .in_rgb(in_rgb),
        .out_de(out_de), .out_x(out_x), .out_y(out_y), .out_rgb(out_rgb)
    );

    initial clk = 1'b0;
    always #20 clk = ~clk;

    integer yy, xx, k;

    always @(posedge clk) begin
        if (out_de) begin
            $display("T=%0t out_x=%0d val=%0d | x_s2=%0d row_cur=%0d c_a=%0d m_a=%0d",
                     $time, out_x, out_rgb[7:0],
                     dut.x_s2, dut.row_cur, dut.c_a, dut.m_a);
        end
    end

    initial begin
        rst_n = 1'b0; in_de = 1'b0; in_x = 0; in_y = 0; in_rgb = 0; mode = 3'd0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        for (yy = -1; yy < H + 1; yy = yy + 1) begin
            for (xx = 0; xx < W + 4; xx = xx + 1) begin
                if (xx < W && yy >= 0 && yy < H) begin
                    in_de = 1'b1; in_x = xx; in_y = yy;
                    // 灰度 = (77R + 150G + 29B) >> 8，而 77+150+29 = 256，
                    // 所以 R=G=B=xx 时灰度正好等于 xx，可以直接读出"值来自第几列"
                    in_rgb = {xx[7:0], xx[7:0], xx[7:0]};
                end else begin
                    in_de = 1'b0; in_x = 0; in_y = 0; in_rgb = 0;
                end
                @(posedge clk);
            end
        end
        repeat (10) @(posedge clk);
        $finish;
    end
endmodule

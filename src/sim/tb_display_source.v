`timescale 1ns/1ps
module display_source_check #(parameter SCALE=3, parameter SOFT_BG=0)(
    input wire clk, rst_n, de,
    input wire [15:0] x,y,
    output reg [31:0] checked=0
);
    wire [16:0] addr;
    reg [7:0] data;
    wire de_o, mark;
    wire [15:0] xo,yo;
    wire [23:0] rgb;
    localparam MAIN=320*240;
    localparam IMG_DW=320*SCALE;
    localparam IMG_DH=240*SCALE;
    localparam VIS_W=(IMG_DW<1280)?IMG_DW:1280;
    localparam VIS_H=(IMG_DH<720)?IMG_DH:720;
    localparam X0=(1280-VIS_W)/2;
    localparam Y0=(720-VIS_H)/2;
    localparam HOFF=(IMG_DW-VIS_W)/2;
    localparam VOFF=(IMG_DH-VIS_H)/2;
    function [7:0] memory_value;
        input integer a;
        begin
            memory_value=(a*13+a/320)%128;
            if (a<MAIN && a%37==0) memory_value=memory_value|8'h80;
        end
    endfunction
    always @(posedge clk) begin
        if (rst_n && addr >= MAIN+(SOFT_BG?1920:0))
            $fatal(1,"Out-of-range RAM address %0d scale=%0d bg=%0d",addr,SCALE,SOFT_BG);
        data <= memory_value(addr);
    end
    image_rom_src #(.SCALE(SCALE),.SOFT_BG(SOFT_BG)) dut(
        .clk(clk),.rst_n(rst_n),.de(de),.x(x),.y(y),.raddr(addr),.rdata(data),
        .de_o(de_o),.x_o(xo),.y_o(yo),.rgb_o(rgb),.mark_o(mark)
    );
    integer expected_addr, sx, sy;
    reg in_window;
    reg [7:0] value,grey;
    reg [23:0] expected_rgb;
    reg expected_mark;
    always @(negedge clk) if (rst_n && de_o) begin
        in_window=(xo>=X0 && xo<X0+VIS_W && yo>=Y0 && yo<Y0+VIS_H);
        expected_rgb=0; expected_mark=0;
        if (in_window) begin
            sx=(xo-X0+HOFF)/SCALE;sy=(yo-Y0+VOFF)/SCALE;
            expected_addr=sy*320+sx;
        end else if (SOFT_BG) begin
            sx=(xo<X0)?(xo/10):((xo-(X0+VIS_W))/10+16);
            sy=yo/12;expected_addr=MAIN+sy*32+sx;
        end else expected_addr=0;
        value=memory_value(expected_addr);grey={value[6:0],1'b0};
        if (in_window || SOFT_BG) expected_rgb={grey,grey,grey};
        expected_mark=in_window && value[7];
        if (rgb !== expected_rgb || mark !== expected_mark)
            $fatal(1,"Pixel alignment mismatch x=%0d y=%0d scale=%0d bg=%0d got=%h expected=%h mark=%b/%b",xo,yo,SCALE,SOFT_BG,rgb,expected_rgb,mark,expected_mark);
        checked<=checked+1;
    end
endmodule

module tb_display_source;
    reg clk=0,rst_n=0,de=0;
    reg [15:0] x=0,y=0;
    wire [31:0] c0,c1,c2;
    integer xx,yy;
    always #5 clk=~clk;
    display_source_check #(.SCALE(3),.SOFT_BG(0)) legacy3(clk,rst_n,de,x,y,c0);
    display_source_check #(.SCALE(4),.SOFT_BG(0)) legacy4(clk,rst_n,de,x,y,c1);
    display_source_check #(.SCALE(3),.SOFT_BG(1)) soft3(clk,rst_n,de,x,y,c2);
    initial begin
        repeat(8) @(negedge clk);
        rst_n=1;
        repeat(8) @(negedge clk);
        for(yy=0;yy<720;yy=yy+1) begin
            for(xx=0;xx<1280;xx=xx+1) begin
                @(negedge clk);de=1;x=xx;y=yy;
            end
            @(negedge clk);de=0;x=0;
            repeat(16) @(negedge clk);
        end
        repeat(16) @(negedge clk);
        if(c0!==921600 || c1!==921600 || c2!==921600)
            $fatal(1,"Incomplete frame checks: %0d %0d %0d",c0,c1,c2);
        $display("PASS: 2764800 pixels checked, source/border alignment, main/background addresses and mark isolation.");
        $finish;
    end
endmodule

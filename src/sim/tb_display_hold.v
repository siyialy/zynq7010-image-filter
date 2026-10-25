`timescale 1ns/1ps
module tb_display_hold;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,hold=0;
    wire [23:0] rgb;wire de,hs,vs;wire [16:0] addr;
    video_pipeline #(.H_VISIBLE(64),.H_FP(4),.H_SYNC(4),.H_BP(4),
        .V_VISIBLE(48),.V_FP(2),.V_SYNC(2),.V_BP(2),.DEPTH(128),
        .IMG_W(8),.IMG_H(8),.IMG_SCALE(1)) dut(
        .clk_pix(clk),.rst_n(rst_n),.mode(3'd0),.src_sel(1'b0),
        .box_bus(384'd0),.display_hold(hold),.buf_raddr(addr),.buf_rdata(8'd64),
        .rgb_out(rgb),.hs_out(hs),.vs_out(vs),.de_out(de));
    reg previous_hold=0,at_boundary=0;
    integer ticks=0,grey_pixels=0,changes=0;
    always @(posedge clk)at_boundary=dut.frame_start;
    always @(negedge clk)if(rst_n)begin
        ticks=ticks+1;
        if(dut.hold_frame!==previous_hold)begin
            if(!at_boundary)$fatal(1,"Hold changed inside a frame");
            changes=changes+1;
        end
        if(de && dut.hold_frame)begin
            if(rgb!==24'h606060)$fatal(1,"Image/box leaked through hold");
            grey_pixels=grey_pixels+1;
        end
        previous_hold=dut.hold_frame;
        if(ticks>25000)$fatal(1,"Display hold timeout");
    end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        repeat(100)@(negedge clk);#2 hold=1;
        wait(dut.hold_frame===1);repeat(5000)@(negedge clk);#2 hold=0;
        wait(dut.hold_frame===0);repeat(100)@(negedge clk);
        if(changes!=2 || grey_pixels<2000)$fatal(1,"Hold coverage incomplete");
        $display("PASS: asynchronous hold synchronizes and changes only at frame boundary; held pixels stay grey");$finish;
    end
endmodule

`timescale 1ns/1ps
module tb_cdc_boxes_frame;
    reg ca=0,cp=0,ra=0,rp=0,toggle=0,frame=0;
    always #5 ca=~ca;
    always #7 cp=~cp;
    reg [383:0] value=0;wire [383:0] result;
    cdc_boxes #(.W(384),.FRAME_LATCH(1)) dut(
        .clk_axi(ca),.rst_axi_n(ra),.bus_in(value),.commit_tog(toggle),
        .clk_pix(cp),.rst_pix_n(rp),.frame_tick(frame),.bus_out(result));
    initial begin
        repeat(4)@(negedge cp);ra=1;rp=1;
        @(negedge ca);value=384'h123456789;toggle=~toggle;
        repeat(6)@(negedge cp);
        if(result!==0)$fatal(1,"Coordinates changed during active frame");
        frame=1;@(negedge cp);frame=0;
        if(result!==384'h123456789)$fatal(1,"Missing frame-boundary commit");
        @(negedge ca);value=384'h987654321;toggle=~toggle;
        repeat(6)@(negedge cp);
        if(result!==384'h123456789)$fatal(1,"Second coordinates changed mid-frame");
        frame=1;@(negedge cp);frame=0;
        if(result!==384'h987654321)$fatal(1,"Second frame commit failed");
        $display("PASS: PL boxes remain stable inside a frame and update at frame boundaries");$finish;
    end
endmodule

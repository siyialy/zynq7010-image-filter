`timescale 1ns/1ps
module tb_pl_many_boxes;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,we=0;reg [16:0] addr=0;reg [7:0] data=0;
    wire [31:0] status;wire [767:0] boxes;
    pl_pest_detector #(.W(64),.H(64),.RADIUS(3)) dut(.clk(clk),.rst_n(rst_n),.upload_we(we),
        .upload_addr(addr),.upload_data(data),.overlay_enable(1'b1),.box_bus(boxes),.commit_toggle(),.detector_active(),.status(status));
    reg [767:0] overlay_bus=0;reg [15:0] x=0,y=0;wire hit;
    box_overlay #(.NB(16),.W(768)) overlay(.bus(overlay_bus),.x(x),.y(y),.hit(hit));
    reg [23:0] rgb[0:4095];reg [31:0] expected[0:80];integer p,b,base,tick;
    task byte_write;input [16:0] a;input [7:0] d;begin
        @(negedge clk);we=1;addr=a;data=d;@(negedge clk);we=0;
    end endtask
    task cmd;input [7:0] op;begin byte_write(80004,6);byte_write(80005,0);byte_write(80006,0);byte_write(80007,op);end endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        $readmemh("rgb_0.mem",rgb);$readmemh("expected_0.mem",expected);cmd(1);
        for(p=0;p<4096;p=p+1)begin
            byte_write(80000,rgb[p][7:0]);byte_write(80001,rgb[p][15:8]);byte_write(80002,rgb[p][23:16]);byte_write(80003,0);
        end
        cmd(2);tick=0;
        while(!status[1]&&!status[2]&&tick<5000000)begin @(negedge clk);tick=tick+1;end
        if(!status[1]||status[2]||status[12:8]!=16)$fatal(1,"Expected all 16 boxes, status=%h",status);
        for(b=0;b<16;b=b+1)begin
            base=1+b*5;
            if(dut.bx0[b]!==expected[base]||dut.by0[b]!==expected[base+1]||dut.bx1[b]!==expected[base+2]||dut.by1[b]!==expected[base+3]||dut.box_area[b]!==expected[base+4])$fatal(1,"Box %0d mismatch",b);
        end
        overlay_bus[0]=1;overlay_bus[5:1]=16;
        overlay_bus[8+15*44+:44]={11'd110,11'd110,11'd100,11'd100};x=100;y=105;#1;
        if(!hit)$fatal(1,"Sixteenth overlay box missing");
        overlay_bus[5:1]=8;#1;if(hit)$fatal(1,"Disabled sixteenth box still visible");
        $display("PASS: 16 retained boxes, coordinates, score order and sixteenth red overlay");$finish;
    end
endmodule

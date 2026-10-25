`timescale 1ns/1ps
module tb_pl_pest_detector;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,we=0;reg [16:0] addr=0;reg [7:0] data=0;
    wire [767:0] boxes;wire toggle;wire [31:0] status;
    pl_pest_detector #(.W(32),.H(32),.RADIUS(3),.CROP_Y(0),.CROP_H(32)) dut(
        .clk(clk),.rst_n(rst_n),.upload_we(we),.upload_addr(addr),.upload_data(data),
        .overlay_enable(1'b1),.box_bus(boxes),.commit_toggle(toggle),.status(status));
    reg fault_enable=0;
    wire [31:0] overflow_status;
    pl_pest_detector #(.W(32),.H(32),.RADIUS(3),.CROP_Y(0),.CROP_H(32),.FIFO_DEPTH(8)) limited(
        .clk(clk),.rst_n(rst_n),.upload_we(we&&fault_enable),.upload_addr(addr),.upload_data(data),
        .overlay_enable(1'b1),.box_bus(),.commit_toggle(),.detector_active(),.status(overflow_status));
    reg [1:0] masks[0:1023];
    reg [23:0] rgb[0:1023];reg [31:0] expected[0:80];
    reg [1023:0] file_rgb,file_expected,file_masks;
    integer c,p,b,tick,base,checked;
    task byte_write;input [16:0] a;input [7:0] d;begin
        @(negedge clk);we=1;addr=a;data=d;
        @(negedge clk);we=0;
    end endtask
    task command;input [7:0] cmd;begin
        byte_write(80004,6);byte_write(80005,0);byte_write(80006,0);byte_write(80007,cmd);
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        if(status[31:24]!==8'hD2)$fatal(1,"Bad detector ID");
        command(2);if(!status[2])$fatal(1,"Incomplete frame was not rejected");
        command(3);
        for(c=0;c<8;c=c+1)begin
            $sformat(file_rgb,"rgb_%0d.mem",c);$sformat(file_expected,"expected_%0d.mem",c);
            $sformat(file_masks,"masks_%0d.mem",c);$readmemh(file_masks,masks);
            $readmemh(file_rgb,rgb);$readmemh(file_expected,expected);
            fault_enable=c==1;
            command(1);
            for(p=0;p<1024;p=p+1)begin
                byte_write(80000,rgb[p][7:0]);byte_write(80001,rgb[p][15:8]);byte_write(80002,rgb[p][23:16]);byte_write(80003,0);
            end
            command(2);tick=0;checked=0;
            while(!status[1]&&!status[2]&&tick<2000000)begin
                @(negedge clk);tick=tick+1;
                if(!checked && dut.state==16 && dut.index==0 && !dut.leaf_select && dut.op==9)begin
                    for(p=0;p<1024;p=p+1)begin
                        if({dut.temp_mem[p][5],dut.temp_mem[p][6]}!==masks[p])
                            $fatal(1,"Case %0d mask pixel %0d RTL=%b%b Python=%b",c,p,dut.temp_mem[p][5],dut.temp_mem[p][6],masks[p]);
                    end
                    checked=1;
                end
            end
            if(!checked)$fatal(1,"Mask checkpoint missed");
            if(!status[1]||status[2])$fatal(1,"Case %0d failed/status=%h state=%d",c,status,dut.state);
            if(status[dut.CNT_W+7:8]!==expected[0])$fatal(1,"Case %0d count: RTL=%0d Python=%0d",c,status[dut.CNT_W+7:8],expected[0]);
            for(b=0;b<expected[0];b=b+1)begin
                base=1+b*5;
                if(dut.bx0[b]!==expected[base] || dut.by0[b]!==expected[base+1] || dut.bx1[b]!==expected[base+2] || dut.by1[b]!==expected[base+3] || dut.box_area[b]!==expected[base+4])
                    $fatal(1,"Case %0d box %0d mismatch RTL=(%d,%d,%d,%d) area=%d",c,b,dut.bx0[b],dut.by0[b],dut.bx1[b],dut.by1[b],dut.box_area[b]);
            end
            if(c==1 && (!overflow_status[2] || overflow_status[0] || overflow_status[dut.CNT_W+7:8]!=0))
                $fatal(1,"Flood frontier overflow was not reported safely");
            $display("PASS case %0d boxes=%0d cycles=%0d",c,status[dut.CNT_W+7:8],tick);
        end
        $display("PASS: Python/RTL masks, components, box coordinates, repeated frames, input guard and frontier overflow");$finish;
    end
endmodule

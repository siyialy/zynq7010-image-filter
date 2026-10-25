`timescale 1ns/1ps
module tb_pl_detector_full;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,we=0;reg [16:0] addr=0;reg [7:0] data=0;
    wire [31:0] status;
    pl_pest_detector dut(.clk(clk),.rst_n(rst_n),.upload_we(we),.upload_addr(addr),.upload_data(data),
        .overlay_enable(1'b1),.box_bus(),.commit_toggle(),.detector_active(),.status(status));
    reg [23:0] rgb[0:65535];reg [4:0] contrast[0:65535];reg [1:0] masks[0:65535];
    reg [31:0] expected[0:80];reg [1023:0] filename;
    integer c,p,b,tick,base,checked_contrast,checked_mask;
    task byte_write;input [16:0] a;input [7:0] d;begin
        @(negedge clk);we=1;addr=a;data=d;@(negedge clk);we=0;
    end endtask
    task command;input [7:0] cmd;begin
        byte_write(80004,6);byte_write(80005,0);byte_write(80006,0);byte_write(80007,cmd);
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(c=0;c<2;c=c+1)begin
            $sformat(filename,"rgb_%0d.mem",c);$readmemh(filename,rgb);
            $sformat(filename,"contrast_%0d.mem",c);$readmemh(filename,contrast);
            $sformat(filename,"masks_%0d.mem",c);$readmemh(filename,masks);
            $sformat(filename,"expected_%0d.mem",c);$readmemh(filename,expected);
            command(1);
            for(p=0;p<65536;p=p+1)begin
                byte_write(80000,rgb[p][7:0]);byte_write(80001,rgb[p][15:8]);byte_write(80002,rgb[p][23:16]);byte_write(80003,0);
            end
            command(2);tick=0;checked_contrast=0;checked_mask=0;
            while(!status[1]&&!status[2]&&tick<50000000)begin
                @(negedge clk);tick=tick+1;
                if(!checked_contrast && dut.state==2 && dut.op==6 && dut.index==0)begin
                    for(p=0;p<65536;p=p+1)if(dut.meta_mem[p][4:0]!==contrast[p])
                        $fatal(1,"Full case %0d contrast pixel %0d: RTL=%d Python=%d",c,p,dut.meta_mem[p][4:0],contrast[p]);
                    checked_contrast=1;$display("PASS full case %0d: exact 31x31 closing/contrast at every pixel",c);
                end
                if(!checked_mask && dut.state==16 && dut.index==0 && !dut.leaf_select && dut.op==9)begin
                    for(p=0;p<65536;p=p+1)if({dut.temp_mem[p][5],dut.temp_mem[p][6]}!==masks[p])
                        $fatal(1,"Full case %0d mask pixel %0d",c,p);
                    checked_mask=1;
                end
            end
            if(!checked_contrast || !checked_mask || !status[1] || status[2])$fatal(1,"Full frame failed: %h",status);
            if(status[dut.CNT_W+7:8]!==expected[0])$fatal(1,"Full case %0d count mismatch",c);
            for(b=0;b<expected[0];b=b+1)begin
                base=1+b*5;
                if(dut.bx0[b]!==expected[base] || dut.by0[b]!==expected[base+1] || dut.bx1[b]!==expected[base+2] || dut.by1[b]!==expected[base+3] || dut.box_area[b]!==expected[base+4])
                    $fatal(1,"Full case %0d box %0d mismatch",c,b);
            end
            $display("PASS full case %0d: masks, boxes and areas; cycles=%0d",c,tick);
        end
        $display("PASS: full-size exact closing, borders, in-place read/write, masks and boxes");$finish;
    end
endmodule

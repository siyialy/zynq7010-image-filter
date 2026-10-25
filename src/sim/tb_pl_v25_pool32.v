`timescale 1ns/1ps
module tb_pl_v25_pool32;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,we=0;reg [16:0] addr=0;reg [7:0] data=0;reg [5:0] qi=0;
    wire [5:0] count;wire [95:0] qr;wire busy,done,error;
    pl_pest_engine_v25 #(.W(128),.H(128)) dut(.clk(clk),.rst_n(rst),.upload_we(we),.upload_addr(addr),.upload_data(data),
        .overlay_enable(1'b1),.profile_mode(2'd3),.query_index(qi),.query_record(qr),.pool_count(count),
        .engine_busy(busy),.engine_done(done),.engine_error(error),.parent_valid(),.parent_bbox(),
        .box_bus(),.commit_toggle(),.display_hold(),.detector_active(),.status());
    reg [23:0] rgb[0:16383];reg [95:0] expected[0:31];integer p,t;
    task wr;input [16:0] a;input [7:0] d;begin
        @(negedge clk);we=1;addr=a;data=d;@(negedge clk);we=0;
    end endtask
    task command;input [7:0] c;begin wr(80004,6);wr(80005,0);wr(80006,0);wr(80007,c);end endtask
    initial begin
        $readmemh("pool_rgb.mem",rgb);$readmemh("pool_expected.mem",expected);
        repeat(4)@(negedge clk);rst=1;command(1);
        for(p=0;p<16384;p=p+1)begin wr(80000,rgb[p][7:0]);wr(80001,rgb[p][15:8]);wr(80002,rgb[p][23:16]);wr(80003,0);end
        command(2);t=0;
        while(!done&&!error&&t<15000000)begin
            @(negedge clk);t=t+1;
            if(dut.state==15 && dut.ram_addr!==dut.rd_addr)$fatal(1,"synthetic neighbour address mismatch");
        end
        if(error||!done||count!==32)$fatal(1,"synthetic pool error/count %0d",count);
        for(p=0;p<32;p=p+1)begin qi=p;#1;if(qr[84:0]!==expected[p][84:0])$fatal(1,"synthetic pool order/record %0d",p);end
        $display("PASS: v25 pool32 40 components, late insertion at full capacity, exact source/area/score/order and aligned RAM write address");$finish;
    end
endmodule

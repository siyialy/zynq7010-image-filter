`timescale 1ns/1ps
module tb_pl_v26_full;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,we=0;reg [16:0] addr=0;reg [7:0] data=0;
    wire [31:0] status;
    pl_detector_v25 dut(.clk(clk),.rst_n(rst),.upload_we(we),.upload_addr(addr),.upload_data(data),
        .overlay_enable(1'b1),.box_bus(),.commit_toggle(),.display_hold(),.detector_active(),.status(status));
    reg [23:0] rgb[0:65535];reg [4:0] contrast[0:65535];reg [1:0] mask[0:65535];
    reg [95:0] pool[0:32],expected[0:32];reg [31:0] disp[0:63];
    reg [1023:0] name;
    integer testidx,c,m,p,b,t,cc,mc,ec;
    task byte_write;input [16:0] a;input [7:0] d;begin
        @(negedge clk);we=1;addr=a;data=d;@(negedge clk);we=0;
    end endtask
    task command;input [7:0] op,sel;begin
        byte_write(80004,6);byte_write(80005,sel);byte_write(80006,0);byte_write(80007,op);
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;command(4,3);if(status!==32'h00020006)$fatal(1,"v26 feature mismatch");
        for(testidx=0;testidx<4;testidx=testidx+1)begin
            c=testidx==0?12:(testidx==1?20:(testidx==2?22:9));
            $sformat(name,"rgb_%0d.mem",c);$readmemh(name,rgb);
            for(m=0;m<4;m=m+1)begin
                $sformat(name,"contrast_%0d_%0d.mem",c,m);$readmemh(name,contrast);
                $sformat(name,"mask_%0d_%0d.mem",c,m);$readmemh(name,mask);
                $sformat(name,"pool_%0d_%0d.mem",c,m);$readmemh(name,pool);
                command(7,m);command(3,0);command(1,0);
                for(p=0;p<65536;p=p+1)begin
                    byte_write(80000,rgb[p][7:0]);byte_write(80001,rgb[p][15:8]);byte_write(80002,rgb[p][23:16]);byte_write(80003,0);
                end
                command(4,2);if(status!==65536)$fatal(1,"received count");
                command(2,0);t=0;cc=0;mc=0;ec=0;
                while(!status[1]&&!status[2]&&t<60000000)begin
                    @(negedge clk);t=t+1;
                    if(dut.engine.state==15 && dut.engine.ram_addr!==dut.engine.rd_addr)
                        $fatal(1,"registered neighbour address misaligned sample %0d mode %0d",c+1,m);
                    // v26 commits the final contrast write in CENTER_WAIT;
                    // inspect on the first morphology read, after that commit.
                    if(!cc && dut.engine.state==54 && dut.engine.op==6 && dut.engine.morph_line==0 && dut.engine.morph_t==-1 && !dut.engine.morph_vertical)begin
                        for(p=0;p<65536;p=p+1)if(dut.engine.meta_mem[p][4:0]!==contrast[p])$fatal(1,"contrast sample %0d mode %0d pixel %0d",c+1,m,p);
                        cc=1;
                    end
                    if(!mc && dut.engine.state==16 && dut.engine.index==0 && !dut.engine.leaf_select && dut.engine.op==(m==0?9:11))begin
                        for(p=0;p<65536;p=p+1)if({dut.engine.temp_mem[p][5],dut.engine.temp_mem[p][6]}!==mask[p])$fatal(1,"mask sample %0d mode %0d pixel %0d RTL=%h expected=%h",c+1,m,p,{dut.engine.temp_mem[p][5],dut.engine.temp_mem[p][6]},mask[p]);
                        mc=1;
                    end
                    if(!ec && dut.ed)begin
                        if(dut.pc!==pool[0])$fatal(1,"engine pool count sample %0d mode %0d RTL=%0d expected=%0d",c+1,m,dut.pc,pool[0]);
                        for(b=0;b<dut.pc;b=b+1)begin
                            if(dut.engine.candidates[b][84:0]!==pool[b+1][84:0])
                                $fatal(1,"pool sample %0d mode %0d box %0d",c+1,m,b);
                        end
                        ec=1;
                    end
                end
                if(!cc||!mc||!ec||status[2]||!status[1])$fatal(1,"pass failed sample %0d mode %0d status=%h checked=%d%d%d",c+1,m,status,cc,mc,ec);
                $display("PASS sample %0d mode %0d: all 65536 contrast/mask pixels and pool records, cycles %0d",c+1,m,t);
                command(4,4);if(status[1])m=4;
            end
            $sformat(name,"final_%0d.mem",c);$readmemh(name,expected);
            $sformat(name,"display_%0d.mem",c);$readmemh(name,disp);
            command(4,0);if(status[13:8]!==expected[0])$fatal(1,"final count");
            for(b=0;b<expected[0];b=b+1)begin
                command(4,16+2*b);if(status!==disp[2*b])$fatal(1,"display low");
                command(4,17+2*b);if(status!==disp[2*b+1])$fatal(1,"display high");
                command(4,80+2*b);if(status!=={7'd0,expected[b+1][17:9],7'd0,expected[b+1][8:0]})$fatal(1,"source low");
                command(4,81+2*b);if(status!=={7'd0,expected[b+1][35:27],7'd0,expected[b+1][26:18]})$fatal(1,"source high");
                command(4,144+b);if(status!==expected[b+1][52:36])$fatal(1,"area");
            end
            $display("PASS full sample %0d final %0d boxes via PS readback protocol",c+1,expected[0]);
        end
        $display("PASS: v26 full engine and fusion");$finish;
    end
endmodule

`timescale 1ns/1ps
module tb_pl_v25_fusion;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,begin_frame=0,start=0,pv=0;
    reg [1:0] mode=0;reg [35:0] pb=0;
    reg [5:0] qi=0,pc=0;wire [5:0] pi,count;
    reg [95:0] pool[0:32],expected[0:32];reg [35:0] parents[0:32];
    reg [31:0] disp[0:63];reg corner=0;
    wire [95:0] qr;wire [31:0] qd;
    wire busy,done,ready,publish,error;wire [1535:0] bus;
    pl_candidate_fusion dut(.clk(clk),.rst_n(rst),.begin_frame(begin_frame),.abort_work(1'b0),.start_pass(start),
        .mode(mode),.pool_count(pc),.pool_index(pi),.pool_record(pool[pi+1]),.parent_valid(pv),.parent_bbox(pb),
        .query_index(qi),.query_record(qr),.query_corner(corner),.query_display(qd),.busy(busy),.pass_done(done),
        .final_ready(ready),.publish(publish),.error(error),.count(count),.box_bus(bus),.overlay_enable(1'b1));
    // Last overlay slot verifies that 32 is represented, rather than truncated to 0.
    reg [1535:0] overlay_bus=0;reg [15:0] ox=123,oy=234;wire overlay_hit;
    box_overlay #(.NB(32),.W(1536)) overlay(.bus(overlay_bus),.x(ox),.y(oy),.hit(overlay_hit));
    integer c,m,p,t;reg [1023:0] name;
    function [95:0] make_record;
        input [8:0] x,y,size;
        input [16:0] area;
        input [31:0] score;
        reg [8:0] x1,y1;
        begin x1=x+size;y1=y+size;make_record={11'd0,score,area,y1,x1,y,x};end
    endfunction
    initial begin
        repeat(4)@(negedge clk);rst=1;
        overlay_bus[0]=1;overlay_bus[6:1]=32;overlay_bus[8+31*44+:44]={11'd250,11'd150,11'd234,11'd123};
        #1;if(!overlay_hit)$fatal(1,"slot 31/count 32 overlay failed");
        for(c=0;c<24;c=c+1)begin
            @(negedge clk);begin_frame=1;mode=0;@(negedge clk);begin_frame=0;
            $sformat(name,"parents_%0d.mem",c);$readmemh(name,parents);
            for(p=0;p<parents[0];p=p+1)begin
                @(negedge clk);pv=1;pb=parents[p+1];
            end
            @(negedge clk);pv=0;
            for(m=0;m<4;m=m+1)begin
                mode=m;$sformat(name,"pool_%0d_%0d.mem",c,m);$readmemh(name,pool);pc=pool[0];
                @(negedge clk);start=1;@(negedge clk);start=0;t=0;
                while(!done&&!error&&t<1000000)begin @(negedge clk);t=t+1;end
                if(error||!done)$fatal(1,"fusion error/timeout sample %0d mode %0d",c+1,m);
                if(ready)m=4;
            end
            if(!ready)$fatal(1,"no final publish");
            $sformat(name,"final_%0d.mem",c);$readmemh(name,expected);
            $sformat(name,"display_%0d.mem",c);$readmemh(name,disp);
            if(count!==expected[0])$fatal(1,"fusion sample %0d count %0d expected %0d",c+1,count,expected[0]);
            for(p=0;p<count;p=p+1)begin
                qi=p;corner=0;repeat(2)@(negedge clk);#1;
                if(qr[84:0]!==expected[p+1][84:0])$fatal(1,"fusion sample %0d box %0d RTL=%h expected=%h",c+1,p,qr,expected[p+1]);
                if(qd!==disp[2*p])$fatal(1,"display low mismatch");
                corner=1;#1;if(qd!==disp[2*p+1])$fatal(1,"display high mismatch");
                if(bus[8+44*p+:11]!==disp[2*p][8:0]*3+160 ||
                   bus[19+44*p+:11]!==disp[2*p][24:16]*3 ||
                   bus[30+44*p+:11]!==disp[2*p+1][8:0]*3+162 ||
                   bus[41+44*p+:11]!==disp[2*p+1][24:16]*3+2)$fatal(1,"HDMI bus mapping mismatch");
            end
            $display("PASS fusion sample %0d: %0d exact boxes, source/display/area/score",c+1,count);
        end
        // Independent synthetic case reaches the real final-store capacity:
        // sixteen baseline boxes plus sixteen separated refinement boxes.
        @(negedge clk);begin_frame=1;mode=0;@(negedge clk);begin_frame=0;
        pv=1;pb={9'd256,9'd256,9'd0,9'd0};@(negedge clk);pv=0;
        for(m=0;m<4;m=m+1)begin
            mode=m;pc=16;
            for(p=0;p<16;p=p+1)begin
                if(m==0)pool[p+1]=make_record(10+(p%4)*24,10+(p/4)*24,8,64,200-p);
                else pool[p+1]=make_record(130+(p%4)*24,130+(p/4)*24,5,25,100-p);
            end
            @(negedge clk);start=1;@(negedge clk);start=0;t=0;
            while(!done&&!error&&t<1000000)begin @(negedge clk);t=t+1;end
            if(error||!done)$fatal(1,"synthetic capacity case failed");
        end
        if(!ready || count!==32 || bus[6:1]!==32)$fatal(1,"final capacity count truncated");
        qi=31;corner=0;repeat(2)@(negedge clk);#1;if(qr[8:0]!==199 || qr[17:9]!==199 || qr[26:18]!==210 || qr[35:27]!==210)$fatal(1,"last refinement source box");
        overlay_bus=bus;ox=bus[8+44*31+:11];oy=bus[19+44*31+:11];#1;
        if(!overlay_hit)$fatal(1,"real final slot 31 is not drawn");
        $display("PASS independent synthetic 32 final boxes, global branch de-duplication and real HDMI slot 31");
        @(negedge clk);begin_frame=1;mode=0;@(negedge clk);begin_frame=0;
        for(p=0;p<33;p=p+1)begin @(negedge clk);pv=1;pb=p;end
        @(negedge clk);pv=0;#1;if(!error)$fatal(1,"parent capacity overflow must fail explicitly");
        @(negedge clk);begin_frame=1;@(negedge clk);begin_frame=0;#1;
        if(error||ready||count!=0)$fatal(1,"new frame failed to clear error/result");
        $display("PASS: v25 fusion all 24 and overlay slot 31; bounded parent overflow/reset");$finish;
    end
endmodule

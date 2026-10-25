// PS uploads smoothed RGB; all colour decisions, morphology, connected
// components, ranking and screen boxes are computed here, in the AXI clock.
// Two 9-bit frame memories and a bounded flood frontier fit Zynq-7010 BRAM.
`timescale 1ns/1ps
module pl_pest_engine_v25 #(
    parameter W=256, H=256, RADIUS=15, CROP_Y=32, CROP_H=192,
    parameter FIFO_DEPTH=2048, FAST_LOCAL=1,
`ifdef PL_RELEASE_24
    parameter FAST_MORPH=1,
`else
    parameter FAST_MORPH=0,
`endif
`ifdef PL_RELEASE_23
    parameter RECALL=1,
`else
    parameter RECALL=0,
`endif
`ifdef PL_RELEASE_22
    parameter PRECISION=1, NB=32, BUS_W=1536, CNT_W=6
`else
    parameter PRECISION=0, NB=8, BUS_W=384, CNT_W=4
`endif
)(
    input wire clk, rst_n,
    input wire upload_we,
    input wire [16:0] upload_addr,
    input wire [7:0] upload_data,
    input wire overlay_enable,
    input wire [1:0] profile_mode,
    input wire [5:0] query_index,
    output wire [95:0] query_record,
    output wire [5:0] pool_count,
    output wire engine_busy, engine_done, engine_error,
    output reg parent_valid,
    output reg [35:0] parent_bbox,
    output wire [BUS_W-1:0] box_bus,
    output reg commit_toggle,
    output reg display_hold,
    output wire detector_active,
    output reg [31:0] status
);
    localparam N=W*H, RGB_BASE=80000, CMD_BASE=80004;
    localparam IDLE=0, LOAD=1, CENTER_WAIT=2, CENTER_USE=3,
        NEIGH_WAIT=4, NEIGH_USE=5, WRITE_PIXEL=6, ZERO_WORK=7,
        BORDER_WAIT=8, BORDER_USE=9, POP_WAIT=10, POP_USE=11,
        FLOOD_CENTER_WAIT=12, FLOOD_CENTER_USE=13,
        FLOOD_NEIGH_WAIT=14, FLOOD_NEIGH_USE=15,
        FIND_WAIT=16, FIND_USE=17, COMPONENT_END=18,
        RING_SETUP=19, RING_WAIT=20, RING_USE=21,
        DIV_START=22, DIV_STEP=23, RING_SAVE=24,
        ACCEPT=25, MAP_BOX=26, DUP_CHECK=27, DUP_REMOVE=28,
        INSERT_FIND=29, INSERT_BOX=30, FINISH=31, FAILED=32,
        DUP_DIMS=33,DUP_MULT=34,DUP_SCALE=35,DUP_DECIDE=36,
        GEOM_MULT=37,GEOM_SCALE=38,GEOM_FILTER=39,
        CENTER_DELAY=40,NEIGH_DELAY=41,BORDER_DELAY=42,FLOOD_CENTER_DELAY=43,
        FLOOD_NEIGH_DELAY=44,FIND_DELAY=45,RING_DELAY=46,
        STREAM_WAIT=47,STREAM_DELAY=48,STREAM_USE=49,STREAM_WRITE=50,STREAM_TREE1=51,STREAM_TREE2=52,EVIDENCE=53,
        MORPH_WAIT=54,MORPH_DELAY=55,MORPH_USE=56,MORPH_WRITE=57,MORPH_DONE=58,SHIFT_DELETE=59,SHIFT_INSERT=60,DUP_READ=61;
    reg [5:0] state;
    // Exact separable binary 3x3, reading one pixel ahead of each in-place
    // write. Two prior bits retain overwritten input; flags follow the centre.
    reg morph_vertical,morph_prev0,morph_prev1,morph_value;
    reg [8:0] morph_line,morph_flags,morph_center;
    reg signed [9:0] morph_t;
    reg [3:0] op;
    // meta: {green,tissue,leaf_seed,colour_candidate,luma[4:0]}.
    // temp: {unused,scratch,work,leaf,dilation[4:0]}.
    (* ram_style="block" *) reg [8:0] meta_mem[0:N-1];
    (* ram_style="block" *) reg [8:0] temp_mem[0:N-1];
    (* ram_style="block" *) reg [15:0] fifo[0:FIFO_DEPTH-1];
    reg [8:0] meta_q,temp_q,center_meta,center_temp;
    reg [15:0] fifo_q;
    reg [15:0] rd_addr,wr_addr,ram_addr;
    reg meta_we,temp_we,fifo_we;
    reg [8:0] meta_wdata,temp_wdata;
    reg [15:0] fifo_wdata;
    reg [10:0] qhead,qtail,fifo_waddr;
    reg [11:0] qcount;
    reg [16:0] received,index;
    reg [15:0] current;
    reg signed [5:0] dx,dy;
    reg [2:0] k;
    reg signed [9:0] nx,ny;
    reg [8:0] px,py;
    integer rad;
    reg [4:0] extreme;
    reg bit_acc;
    reg outside_flood;
    reg [7:0] red,green,blue,brown_cut,selector;
    reg active,busy,done,error;
    assign detector_active=active;
    reg [31:0] cycles;
    wire [15:0] lum_sum=red*16'd77+green*16'd150+upload_data*16'd29;
    wire signed [9:0] rg=$signed({1'b0,red})-$signed({1'b0,green});
    wire signed [9:0] rb=$signed({1'b0,red})-$signed({1'b0,upload_data});
    wire signed [9:0] gb=$signed({1'b0,green})-$signed({1'b0,upload_data});
    wire [7:0] hi_rg=red>green?red:green;
    wire [7:0] lo_rg=red<green?red:green;
    wire [7:0] hi=hi_rg>upload_data?hi_rg:upload_data;
    wire [7:0] lo=lo_rg<upload_data?lo_rg:upload_data;
    wire colour_brown=rg>$signed({1'b0,brown_cut}) && rb>5 && rg*100>rb*45;
    wire colour_neutral=red*100>=green*80 && upload_data*100>=green*90;
    wire seed=((gb>12 || rb>25) && hi-lo>20) || (profile_mode==1 && rg>=3 && gb>=3 && rb>=8);
    wire tissue=gb>10 && green*100>red*70;
    wire green_tissue=$signed({1'b0,green})-$signed({1'b0,red})>8 && gb>8;
    reg [8:0] pixel_meta;
    reg [16:0] area,strong,core_count,classic_count,best_leaf_area;
    reg [15:0] root_seed,best_leaf_seed;
    reg [1:0] leaf_stage;
    reg leaf_select,leaf_rebuild;
    reg [24:0] core100,classic100,area30,score3,score4,score6;
`ifdef PL_RELEASE_26
    reg [5:0] evidence;
`else
    reg [4:0] evidence;
`endif
    reg ring_enclosed,compact_enclosed;
    reg pixel_weak;
    wire olive_core=rg>=3 && gb>10 && lum_sum[15:11]<18;
    wire classic_core=colour_brown||colour_neutral;
    wire loose_colour=red*100>=green*80 && upload_data*100>=green*65;
    wire component_hit=leaf_select?(temp_q[5]&&!temp_q[6]):temp_q[6];
    reg [31:0] score;
    reg [8:0] x0,y0,x1,y1;
    integer ring,rx0,ry0,rx1,ry1,rx,ry;
    reg [15:0] ring_count,tissue_count,green_count,halo_count,halo_sum,halo_percent;
    reg [15:0] tissue_sum,green_sum;
    reg [2:0] tissue_sides;
    reg [1:0] div_kind;
    reg [17:0] div_num;
    reg [15:0] div_den,div_quot;
    reg [18:0] div_rem;
    reg [4:0] div_step;
    wire [18:0] shifted_rem={div_rem[17:0],div_num[17]};
    wire [15:0] next_quot={div_quot[14:0],shifted_rem>={3'b0,div_den}};
    reg [15:0] tissue_percent,green_percent;
    // {display y1,x1,y0,x0,score,area,source y1,x1,y0,x0}.
    (* ram_style="distributed" *) reg [120:0] candidates[0:NB-1];
    reg [CNT_W-1:0] count,slot,move_index;
    wire [CNT_W-1:0] candidate_read=busy?
        (state==SHIFT_DELETE?move_index+1'b1:(state==SHIFT_INSERT?move_index-1'b1:slot)):query_index;
    wire [120:0] old_candidate=candidates[candidate_read];
`ifdef PL_RELEASE_26
    reg [35:0] duplicate_display;
    wire [8:0] old_x0=duplicate_display[8:0],old_y0=duplicate_display[17:9];
    wire [8:0] old_x1=duplicate_display[26:18],old_y1=duplicate_display[35:27];
    localparam DUP_NEXT=DUP_READ;
    reg [15:0] write_addr_pipe;
    reg [8:0] meta_data_pipe,temp_data_pipe;
    reg meta_we_pipe,temp_we_pipe;
    // A write can commit one cycle later: every read uses WAIT/DELAY/USE,
    // so flags are committed before the next neighbour or pixel is sampled.
    always @(posedge clk)begin
        if(!rst_n)begin
            write_addr_pipe<=0;meta_data_pipe<=0;temp_data_pipe<=0;
            meta_we_pipe<=0;temp_we_pipe<=0;
        end else begin
            write_addr_pipe<=wr_addr;meta_data_pipe<=meta_wdata;temp_data_pipe<=temp_wdata;
            meta_we_pipe<=meta_we;temp_we_pipe<=temp_we;
        end
    end
`else
    wire [8:0] old_x0=old_candidate[93:85],old_y0=old_candidate[102:94];
    wire [8:0] old_x1=old_candidate[111:103],old_y1=old_candidate[120:112];
    localparam DUP_NEXT=DUP_DIMS;
`endif
    wire [31:0] old_score=old_candidate[84:53];
    wire candidate_we=(state==SHIFT_DELETE && move_index+1<count) ||
        (state==SHIFT_INSERT && move_index>slot) || (state==INSERT_BOX && slot<pool_limit);
    wire [CNT_W-1:0] candidate_write=state==INSERT_BOX?slot:move_index;
    wire [120:0] candidate_data=state==INSERT_BOX?
        {new_y1,new_x1,new_y0,new_x0,score,area,bound9(y1+1,0,H),bound9(x1+1,0,W),y0,x0}:old_candidate;
    always @(posedge clk)if(candidate_we)candidates[candidate_write]<=candidate_data;
    reg [1:0] erosion_left;
    wire [5:0] pool_limit=profile_mode==0?6'd16:6'd32;
    assign pool_count=count;
    assign engine_busy=busy;
    assign engine_done=done;
    assign engine_error=error;
    assign query_record=query_index<count?{11'd0,old_candidate[84:0]}:96'd0;
    reg [8:0] new_x0,new_y0,new_x1,new_y1;
    integer j;
    function integer bound;
        input integer a,lo_b,hi_b;
        begin bound=a<lo_b?lo_b:(a>hi_b?hi_b:a);end
    endfunction
    function [8:0] bound9;
        input integer a,l,h;
        begin bound9=bound(a,l,h);end
    endfunction
    function integer neighbour_x;
        input integer n;
        begin
            if(outside_flood) case(n) 0:neighbour_x=-1;1:neighbour_x=1;default:neighbour_x=0;endcase
            else case(n) 0,3,5:neighbour_x=-1;2,4,7:neighbour_x=1;default:neighbour_x=0;endcase
        end
    endfunction
    function integer neighbour_y;
        input integer n;
        begin
            if(outside_flood) case(n) 2:neighbour_y=-1;3:neighbour_y=1;default:neighbour_y=0;endcase
            else case(n) 0,1,2:neighbour_y=-1;5,6,7:neighbour_y=1;default:neighbour_y=0;endcase
        end
    endfunction
    reg duplicate_remove;
    reg [8:0] old_w,old_h,new_w,new_h,inter_w,inter_h;
    reg [17:0] old_size,new_size,intersection;
    reg [24:0] duplicate_left,duplicate_right;
    reg [8:0] component_w,component_h;
    reg [17:0] component_rect;
    reg [24:0] component_fill,component_area100;
    wire [8:0] intersect_x0=old_x0>new_x0?old_x0:new_x0;
    wire [8:0] intersect_y0=old_y0>new_y0?old_y0:new_y0;
    wire [8:0] intersect_x1=old_x1<new_x1?old_x1:new_x1;
    wire [8:0] intersect_y1=old_y1<new_y1?old_y1:new_y1;
    wire morph_state=state>=MORPH_WAIT && state<=MORPH_WRITE;
    wire morph_and=op==1 || op==6 || op==9 || op==11;
    wire morph_input=morph_vertical?temp_q[7]:
        (op==0?meta_q[6]:((op==7 || op==9)?temp_q[7]:temp_q[6]));
    wire [8:0] morph_length=morph_vertical?H:W;
    wire [8:0] morph_lines=morph_vertical?W:H;
    wire enclosed_gray=RECALL && ring_enclosed && compact_enclosed &&
        core_count!=0 && green_sum>=340 && score>=score3;
    wire neighbour_valid=nx>=0 && nx<W && ny>=0 && ny<H;
    wire flood_hit=neighbour_valid && (leaf_select?(temp_q[5]&&!temp_q[6]):(outside_flood?(!temp_q[5]&&!temp_q[6]):temp_q[6]));
    wire border_pixel=(index%W==0 || index%W==W-1 || index/W==0 || index/W==H-1);
    // Exact separable square closing: max-H, max-V, min-H, min-V.
    // Each in-place pass reads R samples ahead of its write location; the
    // trailing window retains every old sample that is overwritten behind it.
    // Replicated-edge padding matches the previous 2D neighbourhood scans.
    reg [1:0] stream_pass;
    reg [8:0] stream_line;
    reg signed [9:0] stream_t;
    reg [8:0] stream_window[0:29];
    reg [4:0] stream_tree[0:62];
    reg [8:0] stream_sample_reg;
    reg [4:0] stream_middle[0:NB-1];
    reg [4:0] stream_reduce[0:14];
    reg [4:0] stream_result;
    reg [3:0] stream_flags;
    reg [8:0] stream_meta;
    reg [15:0] stream_input_addr,stream_output_addr;
    reg [15:0] meta_rd_addr,meta_ram_addr;
    wire stream_state=state>=STREAM_WAIT && state<=STREAM_TREE2;
    wire [8:0] stream_length=stream_pass[0]?H:W;
    wire [8:0] stream_lines=stream_pass[0]?W:H;
    wire [8:0] stream_sample={temp_q[8:5],stream_pass==0?meta_q[4:0]:temp_q[4:0]};
    integer si,sr;
    always @* begin
        if(stream_pass[0])begin
            stream_input_addr=bound(stream_t,0,H-1)*W+stream_line;
            stream_output_addr=bound(stream_t-RADIUS,0,H-1)*W+stream_line;
        end else begin
            stream_input_addr=stream_line*W+bound(stream_t,0,W-1);
            stream_output_addr=stream_line*W+bound(stream_t-RADIUS,0,W-1);
        end
        for(si=0;si<32;si=si+1)begin
            if(si==0)stream_tree[31+si]=stream_sample_reg[4:0];
            else if(si<=2*RADIUS)stream_tree[31+si]=stream_window[si-1][4:0];
            else stream_tree[31+si]=stream_pass[1]?5'd31:5'd0;
        end
        // Balanced comparison tree: five levels rather than a serial chain.
        for(si=30;si>=0;si=si-1)begin
            if(stream_pass[1])stream_tree[si]=stream_tree[2*si+1]<stream_tree[2*si+2]?stream_tree[2*si+1]:stream_tree[2*si+2];
            else stream_tree[si]=stream_tree[2*si+1]>stream_tree[2*si+2]?stream_tree[2*si+1]:stream_tree[2*si+2];
        end
    end
    always @* begin
        for(sr=0;sr<8;sr=sr+1)stream_reduce[7+sr]=stream_middle[sr];
        for(sr=6;sr>=0;sr=sr-1)begin
            if(stream_pass[1])stream_reduce[sr]=stream_reduce[2*sr+1]<stream_reduce[2*sr+2]?stream_reduce[2*sr+1]:stream_reduce[2*sr+2];
            else stream_reduce[sr]=stream_reduce[2*sr+1]>stream_reduce[2*sr+2]?stream_reduce[2*sr+1]:stream_reduce[2*sr+2];
        end
    end
    // The write enables are combinational; each RAM has one synchronous read
    // and one synchronous write port, with no asynchronous frame-memory reads.
    always @* begin
        px=index%W;py=index/W;rad=(op==4 || op==5)?RADIUS:1;
        nx=current%W+neighbour_x(k);ny=current/W+neighbour_y(k);
        rd_addr=index[15:0];
        if(state==NEIGH_WAIT || state==NEIGH_DELAY || state==NEIGH_USE)
            rd_addr=bound($signed({1'b0,py})+dy,0,H-1)*W+bound($signed({1'b0,px})+dx,0,W-1);
        if(state==FLOOD_CENTER_WAIT || state==FLOOD_CENTER_DELAY || state==FLOOD_CENTER_USE)rd_addr=current;
        if(state==FLOOD_NEIGH_WAIT || state==FLOOD_NEIGH_DELAY || state==FLOOD_NEIGH_USE)
            rd_addr=bound(ny,0,H-1)*W+bound(nx,0,W-1);
        if(state==RING_WAIT || state==RING_DELAY || state==RING_USE)rd_addr=ry*W+rx;
        meta_rd_addr=rd_addr;
        if(stream_state)begin
            rd_addr=stream_input_addr;
            meta_rd_addr=stream_pass==3?stream_output_addr:stream_input_addr;
        end
        if(morph_state)begin
            rd_addr=morph_vertical?bound(morph_t,0,H-1)*W+morph_line:
                morph_line*W+bound(morph_t,0,W-1);
            meta_rd_addr=rd_addr;
        end
        meta_we=0;temp_we=0;fifo_we=0;wr_addr=index[15:0];
        meta_wdata=0;temp_wdata=center_temp;fifo_wdata=rd_addr;fifo_waddr=qtail;
        if(state==LOAD && upload_we && upload_addr==RGB_BASE+3 && received<N)begin
            meta_we=1;temp_we=1;wr_addr=received[15:0];
            meta_wdata=pixel_meta;
            temp_wdata=0;temp_wdata[8]=PRECISION?pixel_weak:1'b0;
        end
        if(state==WRITE_PIXEL)begin
            temp_we=1;
            case(op)
                0:temp_wdata[6]=bit_acc;
                1,3:temp_wdata[5]=bit_acc;
                10:begin temp_wdata[5]=center_temp[6];temp_wdata[6]=0;end
                4:temp_wdata[4:0]=extreme;
                5:begin
                    temp_wdata[6]=center_temp[5] && (profile_mode!=0?(center_meta[5]&&!center_temp[8]):(center_meta[5] || (PRECISION&&center_temp[8]))) && center_meta[4:0]>=(PRECISION?0:4) &&
                        center_meta[4:0]<18 &&
                        ({1'b0,extreme}>={1'b0,center_meta[4:0]}+2 ||
                         (RECALL && center_meta[5] && !center_temp[8] && center_meta[4:0]<=9 &&
                          {1'b0,extreme}>={1'b0,center_meta[4:0]}+1));
                    meta_we=1;meta_wdata={center_meta[8:5],extreme-center_meta[4:0]};
                end
                6,8:temp_wdata[7]=bit_acc;
                7:temp_wdata[6]=bit_acc;
                9:temp_wdata[6]=bit_acc && center_temp[5];
                default:;
            endcase
        end
        if(state==STREAM_WRITE && stream_t>=RADIUS)begin
            temp_we=1;wr_addr=stream_output_addr;
            temp_wdata={stream_flags,stream_result};
            if(stream_pass==3)begin
                temp_wdata[6]=stream_flags[0] && (profile_mode!=0?(stream_meta[5]&&!stream_flags[3]):(stream_meta[5] || (PRECISION&&stream_flags[3]))) && stream_meta[4:0]>=(PRECISION?0:4) &&
                    stream_meta[4:0]<18 &&
                    ({1'b0,stream_result}>={1'b0,stream_meta[4:0]}+2 ||
                     (RECALL && stream_meta[5] && !stream_flags[3] && stream_meta[4:0]<=9 &&
                      {1'b0,stream_result}>={1'b0,stream_meta[4:0]}+1));
                meta_we=1;meta_wdata={stream_meta[8:5],stream_result-stream_meta[4:0]};
            end
        end
        if(state==ZERO_WORK)begin temp_we=1;temp_wdata=center_temp;temp_wdata[6]=0;end
        if(state==MORPH_WRITE && morph_t>=1)begin
            temp_we=1;
            wr_addr=morph_vertical?(morph_t-1)*W+morph_line:morph_line*W+morph_t-1;
            temp_wdata=morph_center;
            if(!morph_vertical || op==6 || op==8)temp_wdata[7]=morph_value;
            else if(op==1)temp_wdata[5]=morph_value;
            else temp_wdata[6]=morph_value && (op!=9 || morph_center[5]);
        end
        if(state==BORDER_USE && border_pixel && !temp_q[5] && !temp_q[6] && qcount<FIFO_DEPTH)begin
            temp_we=1;temp_wdata=temp_q;temp_wdata[6]=1;fifo_we=1;fifo_wdata=index[15:0];
        end
        if(state==FIND_USE && component_hit)begin
            temp_we=1;temp_wdata=temp_q;temp_wdata[6]=leaf_select;fifo_we=1;fifo_wdata=index[15:0];fifo_waddr=0;
        end
        // The neighbour address is already registered for the synchronous read.
        // Keep it independent of RAM output/flood_hit, avoiding a RAM-Q ->
        // write-address feedback path even on the inactive metadata write port.
        if(state==FLOOD_NEIGH_USE)wr_addr=ram_addr;
        if(state==FLOOD_NEIGH_USE && flood_hit && qcount<FIFO_DEPTH)begin
            temp_we=1;temp_wdata=temp_q;
            temp_wdata[6]=outside_flood||leaf_select;fifo_we=1;fifo_wdata=ram_addr;
        end
    end
    always @(posedge clk)begin
        ram_addr<=rd_addr;meta_ram_addr<=meta_rd_addr;
        meta_q<=meta_mem[meta_ram_addr];temp_q<=temp_mem[ram_addr];fifo_q<=fifo[qhead];
`ifdef PL_RELEASE_26
        if(rst_n && meta_we_pipe)meta_mem[write_addr_pipe]<=meta_data_pipe;
        if(rst_n && temp_we_pipe)temp_mem[write_addr_pipe]<=temp_data_pipe;
`else
        if(meta_we)meta_mem[wr_addr]<=meta_wdata;
        if(temp_we)temp_mem[wr_addr]<=temp_wdata;
`endif
        if(fifo_we)fifo[fifo_waddr]<=fifo_wdata;
    end
    // Internal engine has no display bus; final wrapper performs publication.
    assign box_bus=0;
    always @* status={15'd0,received};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            stream_sample_reg<=0;
            for(j=0;j<8;j=j+1)stream_middle[j]<=0;
            stream_pass<=0;stream_line<=0;stream_t<=0;stream_result<=0;stream_flags<=0;stream_meta<=0;
            for(j=0;j<30;j=j+1)stream_window[j]<=0;
            state<=IDLE;op<=0;received<=0;index<=0;current<=0;dx<=0;dy<=0;k<=0;
            red<=0;green<=0;blue<=0;pixel_meta<=0;brown_cut<=6;selector<=0;
            active<=0;busy<=0;done<=0;error<=0;cycles<=0;commit_toggle<=0;
            parent_valid<=0;parent_bbox<=0;erosion_left<=0;count<=0;slot<=0;qhead<=0;qtail<=0;qcount<=0;outside_flood<=0;
`ifdef PL_RELEASE_26
            duplicate_display<=0;
`endif
            extreme<=0;bit_acc<=0;center_meta<=0;center_temp<=0;
            core_count<=0;classic_count<=0;best_leaf_area<=0;root_seed<=0;best_leaf_seed<=0;
            leaf_stage<=0;leaf_select<=0;leaf_rebuild<=0;core100<=0;classic100<=0;area30<=0;score3<=0;score4<=0;score6<=0;evidence<=0;pixel_weak<=0;
            halo_count<=0;halo_sum<=0;halo_percent<=0;
            area<=0;strong<=0;score<=0;x0<=0;y0<=0;x1<=0;y1<=0;
            tissue_sum<=0;green_sum<=0;tissue_sides<=0;ring<=0;
            rx0<=0;ry0<=0;rx1<=0;ry1<=0;rx<=0;ry<=0;
            ring_count<=0;tissue_count<=0;green_count<=0;div_kind<=0;
            ring_enclosed<=0;compact_enclosed<=0;
            morph_vertical<=0;morph_prev0<=0;morph_prev1<=0;morph_value<=0;
            morph_line<=0;morph_flags<=0;morph_center<=0;morph_t<=-1;
            display_hold<=0;
            div_num<=0;div_den<=1;div_quot<=0;div_rem<=0;div_step<=0;
            tissue_percent<=0;green_percent<=0;
            duplicate_remove<=0;old_w<=0;old_h<=0;new_w<=0;new_h<=0;inter_w<=0;inter_h<=0;
            old_size<=0;new_size<=0;intersection<=0;duplicate_left<=0;duplicate_right<=0;
            component_w<=0;component_h<=0;component_rect<=0;component_fill<=0;component_area100<=0;
            new_x0<=0;new_x1<=0;new_y0<=0;new_y1<=0;move_index<=0;

        end else begin
            parent_valid<=0;
            if(busy)cycles<=cycles+1;
            if(upload_we && upload_addr==CMD_BASE)brown_cut<=upload_data;
            if(upload_we && upload_addr==CMD_BASE+1)selector<=upload_data;
            if(upload_we && upload_addr==RGB_BASE)red<=upload_data;
            if(upload_we && upload_addr==RGB_BASE+1)green<=upload_data;
            if(upload_we && upload_addr==RGB_BASE+2)blue<=upload_data;
            case(state)
                IDLE,FAILED:;
                LOAD:begin
                    if(upload_we && upload_addr==RGB_BASE+2)
                        begin
                        pixel_meta<={green_tissue,tissue,seed,(classic_core||(PRECISION&&olive_core)),lum_sum[15:11]};
                        pixel_weak<=!classic_core&&(olive_core||loose_colour);
                    end
                    if(upload_we && upload_addr==RGB_BASE+3)begin
                    if(received<N)received<=received+1;else begin error<=1;state<=FAILED;end
                    end
                end
                CENTER_WAIT:begin
                    state<=CENTER_DELAY;
                    if(FAST_MORPH && index==0 && (op==0 || op==1 || op==6 || op==7 || op==8 || op==9 || op==11))begin
                        morph_vertical<=0;morph_line<=0;morph_t<=-1;state<=MORPH_WAIT;
                    end
                end
                CENTER_DELAY:state<=CENTER_USE;
                CENTER_USE:begin
                    center_meta<=meta_q;center_temp<=temp_q;dx<=-rad;dy<=-rad;
                    extreme<=op==5?31:0;bit_acc<=op==1||op==3||op==6||op==9;
                    state<=NEIGH_WAIT;
                    if(PRECISION && op==3)begin bit_acc<=!temp_q[6];state<=WRITE_PIXEL;end
                    if(PRECISION && op==10)state<=WRITE_PIXEL;
                end
                NEIGH_WAIT:state<=NEIGH_DELAY;
                NEIGH_DELAY:state<=NEIGH_USE;
                NEIGH_USE:begin
                    case(op)
                        0:bit_acc<=bit_acc|meta_q[6];
                        1,6:bit_acc<=bit_acc&temp_q[6];
                        3:bit_acc<=bit_acc&!temp_q[6];
                        4:if(meta_q[4:0]>extreme)extreme<=meta_q[4:0];
                        5:if(temp_q[4:0]<extreme)extreme<=temp_q[4:0];
                        7:bit_acc<=bit_acc|temp_q[7];
                        8:bit_acc<=bit_acc|temp_q[6];
                        9:bit_acc<=bit_acc&temp_q[7];
                        default:;
                    endcase
                    if(dx==rad)begin dx<=-rad;if(dy==rad)state<=WRITE_PIXEL;else begin dy<=dy+1;state<=NEIGH_WAIT;end end
                    else begin dx<=dx+1;state<=NEIGH_WAIT;end
                end
                WRITE_PIXEL:begin
                    if(index==N-1)begin
                        index<=0;
                        if(op==1)begin op<=2;state<=CENTER_WAIT;end
                        else if(op==3 && FAST_LOCAL)begin
                            stream_pass<=0;stream_line<=0;stream_t<=-RADIUS;state<=STREAM_WAIT;
                        end
                        else if(PRECISION&&op==10)begin
                            leaf_select<=0;leaf_stage<=0;outside_flood<=1;qhead<=0;qtail<=0;qcount<=0;state<=BORDER_WAIT;
                        end
                        else if(op==9 && profile_mode!=0)begin
                        op<=11;erosion_left<=profile_mode==3?2:3;state<=CENTER_WAIT;
                    end else if(op==11 && erosion_left>1)begin
                        erosion_left<=erosion_left-1;state<=CENTER_WAIT;
                    end else if(op==9 || op==11)begin outside_flood<=0;state<=FIND_WAIT;end
                        else begin op<=op+1;state<=CENTER_WAIT;end
                    end else begin index<=index+1;state<=CENTER_WAIT;end
                end
                MORPH_WAIT:state<=MORPH_DELAY;
                MORPH_DELAY:state<=MORPH_USE;
                MORPH_USE:begin
                    morph_center<=morph_flags;
                    morph_flags<=temp_q;
                    morph_prev1<=morph_prev0;morph_prev0<=morph_input;
                    morph_value<=morph_and?(morph_prev1&morph_prev0&morph_input):
                        (morph_prev1|morph_prev0|morph_input);
                    if(morph_t==-1)begin
                        morph_prev1<=morph_input;morph_prev0<=morph_input;
                    end
                    state<=MORPH_WRITE;
                end
                MORPH_WRITE:begin
                    if(morph_t==morph_length)begin
                        morph_t<=-1;
                        if(morph_line==morph_lines-1)begin
                            morph_line<=0;
                            if(morph_vertical)state<=MORPH_DONE;
                            else begin morph_vertical<=1;state<=MORPH_WAIT;end
                        end else begin morph_line<=morph_line+1;state<=MORPH_WAIT;end
                    end else begin morph_t<=morph_t+1;state<=MORPH_WAIT;end
                end
                MORPH_DONE:begin
                    index<=0;
                    if(op==9 && profile_mode!=0)begin
                        op<=11;erosion_left<=profile_mode==3?2:3;state<=CENTER_WAIT;
                    end else if(op==11 && erosion_left>1)begin
                        erosion_left<=erosion_left-1;state<=CENTER_WAIT;
                    end else if(op==9 || op==11)begin outside_flood<=0;state<=FIND_WAIT;end
                    else begin op<=op+1;state<=CENTER_WAIT;end
                end
                STREAM_WAIT:state<=STREAM_DELAY;
                STREAM_DELAY:state<=STREAM_USE;
                STREAM_USE:begin
                    stream_sample_reg<=stream_sample;stream_flags<=stream_window[RADIUS-1][8:5];stream_meta<=meta_q;
                    state<=STREAM_TREE1;
                end
                STREAM_TREE1:begin
                    for(j=0;j<8;j=j+1)stream_middle[j]<=stream_tree[7+j];
                    stream_window[0]<=stream_sample_reg;
                    for(j=1;j<30;j=j+1)stream_window[j]<=stream_window[j-1];
                    state<=STREAM_TREE2;
                end
                STREAM_TREE2:begin stream_result<=stream_reduce[0];state<=STREAM_WRITE;end
                STREAM_WRITE:begin
                    if(stream_t==stream_length+RADIUS-1)begin
                        stream_t<=-RADIUS;
                        if(stream_line==stream_lines-1)begin
                            stream_line<=0;
                            if(stream_pass==3)begin op<=6;index<=0;state<=CENTER_WAIT;end
                            else begin stream_pass<=stream_pass+1;state<=STREAM_WAIT;end
                        end else begin stream_line<=stream_line+1;state<=STREAM_WAIT;end
                    end else begin stream_t<=stream_t+1;state<=STREAM_WAIT;end
                end
                ZERO_WORK:begin
                    if(index==N-1)begin
                        index<=0;qhead<=0;qtail<=0;qcount<=0;
                        if(PRECISION&&leaf_stage!=0)begin
                            leaf_select<=1;outside_flood<=0;leaf_rebuild<=leaf_stage==2;
                            if(leaf_stage==2)index<={1'b0,best_leaf_seed};
                            leaf_stage<=0;state<=FIND_WAIT;
                        end else begin outside_flood<=1;state<=BORDER_WAIT;end
                    end
                    else begin index<=index+1;state<=CENTER_WAIT;end
                end
                BORDER_WAIT:state<=BORDER_DELAY;
                BORDER_DELAY:state<=BORDER_USE;
                BORDER_USE:begin
                    if(border_pixel && !temp_q[5] && !temp_q[6])begin
                        if(qcount==FIFO_DEPTH)begin error<=1;state<=FAILED;busy<=0;end
                        else begin qtail<=qtail+1;qcount<=qcount+1;end
                    end
                    if(!(border_pixel && !temp_q[5] && !temp_q[6] && qcount==FIFO_DEPTH))begin
                        if(index==N-1)state<=POP_WAIT;else begin index<=index+1;state<=BORDER_WAIT;end
                    end
                end
                POP_WAIT:begin
                    if(qcount==0)begin
                        if(leaf_select)begin
                            if(leaf_rebuild)begin op<=10;index<=0;state<=CENTER_WAIT;end
                            else state<=COMPONENT_END;
                        end
                        else if(outside_flood)begin op<=3;index<=0;state<=CENTER_WAIT;end
                        else state<=COMPONENT_END;
                    end else state<=POP_USE;
                end
                POP_USE:begin
                    current<=fifo_q;qhead<=qhead+1;qcount<=qcount-1;
                    if(outside_flood)begin k<=0;state<=FLOOD_NEIGH_WAIT;end
                    else state<=FLOOD_CENTER_WAIT;
                end
                FLOOD_CENTER_WAIT:state<=FLOOD_CENTER_DELAY;
                FLOOD_CENTER_DELAY:state<=FLOOD_CENTER_USE;
                FLOOD_CENTER_USE:begin
                    area<=area+1;score<=score+meta_q[4:0];
                    if(meta_q[5])core_count<=core_count+1;
                    if(meta_q[5]&&!temp_q[8])classic_count<=classic_count+1;
                    if(meta_q[6]&&!meta_q[8])strong<=strong+1;
                    if(current%W<x0)x0<=current%W;if(current%W>x1)x1<=current%W;
                    if(current/W<y0)y0<=current/W;if(current/W>y1)y1<=current/W;
                    k<=0;state<=FLOOD_NEIGH_WAIT;
                end
                FLOOD_NEIGH_WAIT:state<=FLOOD_NEIGH_DELAY;
                FLOOD_NEIGH_DELAY:state<=FLOOD_NEIGH_USE;
                FLOOD_NEIGH_USE:begin
                    if(flood_hit)begin
                        if(qcount==FIFO_DEPTH)begin error<=1;busy<=0;count<=0;commit_toggle<=~commit_toggle;state<=FAILED;end
                        else begin qtail<=qtail+1;qcount<=qcount+1;end
                    end
                    if(!(flood_hit && qcount==FIFO_DEPTH))begin
                        if(k==(outside_flood?3:7))state<=POP_WAIT;
                        else begin k<=k+1;state<=FLOOD_NEIGH_WAIT;end
                    end
                end
                FIND_WAIT:begin
                    if(index==N)begin
                        if(leaf_select)begin
                            index<=0;op<=best_leaf_area==0?10:2;
                            leaf_stage<=best_leaf_area==0?0:2;leaf_select<=0;state<=CENTER_WAIT;
                        end else state<=FINISH;
                    end else state<=FIND_DELAY;
                end
                FIND_DELAY:state<=FIND_USE;
                FIND_USE:begin
                    if(component_hit)begin
                        root_seed<=index[15:0];core_count<=0;classic_count<=0;
                        qhead<=0;qtail<=1;qcount<=1;area<=0;strong<=0;score<=0;
                        x0<=W-1;y0<=H-1;x1<=0;y1<=0;state<=POP_WAIT;
                    end else begin index<=index+1;state<=FIND_WAIT;end
                end
                COMPONENT_END:begin
                    if(leaf_select)begin
                        if(area>best_leaf_area)begin best_leaf_area<=area;best_leaf_seed<=root_seed;end
                        index<=index+1;state<=FIND_WAIT;
                    end else begin component_w<=x1-x0+1;component_h<=y1-y0+1;state<=GEOM_MULT;end
                end
                GEOM_MULT:begin
                    component_rect<=component_w*component_h;
                    component_area100<=area*100;core100<=core_count*100;classic100<=classic_count*100;
                    area30<=area*30;score3<=area*3;score4<=area*4;score6<=area*6;state<=GEOM_SCALE;
                end
                GEOM_SCALE:begin component_fill<=component_rect*25;state<=GEOM_FILTER;end
                GEOM_FILTER:begin
                    compact_enclosed<=area>=9 && area<=256 && component_w<=2*component_h &&
                        component_h<=2*component_w && component_area100>=component_fill*2;
                    if(area<(RECALL?9:10) || component_w<3 || component_h<3 || component_w>4*component_h ||
                        component_h>4*component_w || component_area100<component_fill ||
                        (!PRECISION&&(component_w>65 || component_h>65 || y1<CROP_Y || y0>=CROP_Y+CROP_H)))begin index<=index+1;state<=FIND_WAIT;end
                    else begin
                        if(profile_mode==0 && area>=400 && component_rect>=1500)begin
                            parent_valid<=1;
                            parent_bbox<={bound9(y1+13,0,H),bound9(x1+13,0,W),bound9(y0-12,0,H),bound9(x0-12,0,W)};
                        end
                        ring<=0;tissue_sum<=0;green_sum<=0;halo_sum<=0;tissue_sides<=0;ring_enclosed<=1;state<=RING_SETUP;end
                end
                RING_SETUP:begin
                    case(ring)
                        0:begin rx0<=bound(x0-2,0,W);rx1<=bound(x1+3,0,W);ry0<=bound(y0-5,0,H);ry1<=y0;rx<=bound(x0-2,0,W);ry<=bound(y0-5,0,H);end
                        1:begin rx0<=bound(x0-2,0,W);rx1<=bound(x1+3,0,W);ry0<=bound(y1+1,0,H);ry1<=bound(y1+6,0,H);rx<=bound(x0-2,0,W);ry<=bound(y1+1,0,H);end
                        2:begin rx0<=bound(x0-5,0,W);rx1<=x0;ry0<=y0;ry1<=y1+1;rx<=bound(x0-5,0,W);ry<=y0;end
                        3:begin rx0<=bound(x1+1,0,W);rx1<=bound(x1+6,0,W);ry0<=y0;ry1<=y1+1;rx<=bound(x1+1,0,W);ry<=y0;end
                    endcase
                    ring_count<=0;tissue_count<=0;green_count<=0;halo_count<=0;state<=RING_WAIT;
                end
                RING_WAIT:begin
                    if(rx0>=rx1 || ry0>=ry1)begin tissue_percent<=0;green_percent<=0;halo_percent<=0;state<=RING_SAVE;end
                    else state<=RING_DELAY;
                end
                RING_DELAY:state<=RING_USE;
                RING_USE:begin
                    ring_count<=ring_count+1;tissue_count<=tissue_count+meta_q[7];green_count<=green_count+meta_q[8];
                    if(meta_q[5]&&meta_q[7]&&!meta_q[8])halo_count<=halo_count+1;
                    if(rx==rx1-1)begin
                        rx<=rx0;
                        if(ry==ry1-1)begin div_kind<=0;state<=DIV_START;end
                        else begin ry<=ry+1;state<=RING_WAIT;end
                    end else begin rx<=rx+1;state<=RING_WAIT;end
                end
                DIV_START:begin
                    div_num<=(div_kind==0?tissue_count:(div_kind==1?green_count:halo_count))*100;div_den<=ring_count;
                    div_quot<=0;div_rem<=0;div_step<=0;state<=DIV_STEP;
                end
                DIV_STEP:begin
                    div_num<={div_num[16:0],1'b0};div_quot<=next_quot;
                    div_rem<=shifted_rem>={3'b0,div_den}?shifted_rem-div_den:shifted_rem;
                    if(div_step==17)begin
                        if(div_kind==2)begin halo_percent<=next_quot;state<=RING_SAVE;end
                        else if(div_kind==1)begin
                            green_percent<=next_quot;
                            if(PRECISION)begin div_kind<=2;state<=DIV_START;end
                            else state<=RING_SAVE;
                        end else begin tissue_percent<=next_quot;div_kind<=1;state<=DIV_START;end
                    end else div_step<=div_step+1;
                end
                RING_SAVE:begin
                    tissue_sum<=tissue_sum+tissue_percent;green_sum<=green_sum+green_percent;halo_sum<=halo_sum+halo_percent;
                    if(tissue_percent<75 || green_percent<75)ring_enclosed<=0;
                    if(tissue_percent>25)tissue_sides<=tissue_sides+1;
                    if(ring==3)state<=ACCEPT;else begin ring<=ring+1;state<=RING_SETUP;end
                end
                ACCEPT:begin
`ifdef PL_RELEASE_26
                    // Compact olive-only regions need green leaf support.
                    // Keep the existing <=64 edge tier and >256 cluster path.
                    evidence[5]<=!(classic_count==0 && area>64 && area<=256 && green_sum<120);
`endif
                    evidence[0]<=tissue_sides>=3 && tissue_sum>=180;
                    evidence[1]<=!PRECISION || core100>=area30 || enclosed_gray;
                    evidence[2]<=!PRECISION || green_sum+halo_sum>=120;
                    evidence[3]<=!PRECISION || classic100>=area30 || enclosed_gray ||
                        (tissue_sides==4 && tissue_sum>=290 && (green_sum>=120 || halo_sum>=160)) ||
                        (area>=100 && (score>=score6 || (component_area100>=component_fill*2 && score>=score4))) ||
                        (area<=64 && component_area100>=component_fill*2 && green_sum>=100 && halo_sum>=60 && score>=score3);
                    evidence[4]<=strong*2>=area || green_sum>=180 ||
                        (area>=20 && tissue_sides==4 && tissue_sum>=290 && green_sum>=60 && score>=area*2);
                    state<=EVIDENCE;
                end
                EVIDENCE:begin
                    if(&evidence)state<=MAP_BOX;
                    else begin index<=index+1;state<=FIND_WAIT;end
                end
                MAP_BOX:begin
                    if(PRECISION)begin
                        new_x0<=bound((x0*15+15)/16+38,40,279);new_x1<=bound(((x1+1)*15+15)/16+41,40,279);
                        new_y0<=bound((y0*15+15)/16-2,0,239);new_y1<=bound(((y1+1)*15+15)/16+1,0,239);
                    end else begin
                    new_x0<=bound((x0*5+3)/4-2,0,319);new_x1<=bound(((x1+1)*5+3)/4+1,0,319);
                    new_y0<=bound(((bound(y0,CROP_Y,CROP_Y+CROP_H-1)-CROP_Y)*5+3)/4-2,0,239);
                    new_y1<=bound(((bound(y1,CROP_Y,CROP_Y+CROP_H-1)-CROP_Y+1)*5+3)/4+1,0,239);
                    end
                    slot<=0;state<=DUP_CHECK;
                end
                DUP_CHECK:begin
                    if(slot==count)begin slot<=0;state<=DUP_REMOVE;end
                    else begin duplicate_remove<=0;state<=DUP_NEXT;end
                end
                DUP_REMOVE:begin
                    if(slot==count)begin slot<=0;state<=INSERT_FIND;end
                    else begin duplicate_remove<=1;state<=DUP_NEXT;end
                end
`ifdef PL_RELEASE_26
                DUP_READ:begin duplicate_display<=old_candidate[120:85];state<=DUP_DIMS;end
`endif
                DUP_DIMS:begin
                    inter_w<=intersect_x1>=intersect_x0?intersect_x1-intersect_x0+1:0;
                    inter_h<=intersect_y1>=intersect_y0?intersect_y1-intersect_y0+1:0;
                    old_w<=old_x1-old_x0+1;old_h<=old_y1-old_y0+1;
                    new_w<=new_x1-new_x0+1;new_h<=new_y1-new_y0+1;state<=DUP_MULT;
                end
                DUP_MULT:begin
                    intersection<=inter_w*inter_h;old_size<=old_w*old_h;new_size<=new_w*new_h;
                    state<=DUP_SCALE;
                end
                DUP_SCALE:begin
                    duplicate_left<=intersection*100;
                    duplicate_right<=(old_size<new_size?old_size:new_size)*60;state<=DUP_DECIDE;
                end
                DUP_DECIDE:begin
                    if(!duplicate_remove)begin
                        if(duplicate_left>duplicate_right && old_score>=score)begin index<=index+1;state<=FIND_WAIT;end
                        else begin slot<=slot+1;state<=DUP_CHECK;end
                    end else begin
                        if(duplicate_left>duplicate_right)begin
                            move_index<=slot;state<=SHIFT_DELETE;
                        end else begin slot<=slot+1;state<=DUP_REMOVE;end
                    end
                end
                SHIFT_DELETE:begin
                    if(move_index+1>=count)begin count<=count-1;state<=DUP_REMOVE;end
                    else move_index<=move_index+1;
                end
                INSERT_FIND:begin
                    if(slot==count || slot==NB || old_score<score)begin
                        move_index<=count<pool_limit?count:pool_limit-1'b1;state<=SHIFT_INSERT;
                    end else slot<=slot+1;
                end
                SHIFT_INSERT:begin
                    if(move_index<=slot)state<=INSERT_BOX;
                    else move_index<=move_index-1;
                end
                INSERT_BOX:begin
                    if(slot<pool_limit && count<pool_limit)count<=count+1;
                    index<=index+1;state<=FIND_WAIT;
                end
                FINISH:begin busy<=0;done<=1;commit_toggle<=~commit_toggle;state<=IDLE;end
                default:state<=FAILED;
            endcase
            // Clear-work uses the same synchronous center read as other passes.
            if(state==CENTER_USE && op==2)state<=ZERO_WORK;
            // A command word is {opcode, reserved, read-selector, brown-cut}.
            // Opcode 4 only changes the read selector and never restarts work.
            if(upload_we && upload_addr==CMD_BASE+3)begin
                if(FAST_MORPH && upload_data==5)display_hold<=1;
                if(FAST_MORPH && upload_data==6)display_hold<=0;
                if(upload_data==1 && !busy)begin
                    active<=1;busy<=0;done<=0;error<=0;received<=0;count<=0;
                    state<=LOAD;commit_toggle<=~commit_toggle;cycles<=0;
                end
                if(upload_data==2 && !busy)begin
                    if(state==LOAD && received==N)begin busy<=1;done<=0;op<=0;index<=0;leaf_stage<=PRECISION?1:0;leaf_select<=0;leaf_rebuild<=0;best_leaf_area<=0;state<=CENTER_WAIT;end
                    else begin error<=1;count<=0;state<=FAILED;end
                end
                if(upload_data==3)begin active<=0;busy<=0;done<=0;error<=0;state<=IDLE;count<=0;commit_toggle<=~commit_toggle;end
            end
        end
    end
endmodule

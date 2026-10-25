// v2.5 annotation-free refinement. Half-open source boxes, integer ratios.
// Bounded candidate stores use distributed RAM; no additional frame BRAM.
`timescale 1ns/1ps
module pl_candidate_fusion(
    input wire clk,rst_n,begin_frame,abort_work,start_pass,
    input wire [1:0] mode,
    input wire [5:0] pool_count,
    output reg [5:0] pool_index,
    input wire [95:0] pool_record,
    input wire parent_valid,
    input wire [35:0] parent_bbox,
    input wire [5:0] query_index,
    output wire [95:0] query_record,
    input wire query_corner,
    output wire [31:0] query_display,
    output reg busy,pass_done,final_ready,publish,error,
    output reg [5:0] count,
    output wire [1535:0] box_bus,
    input wire overlay_enable
);
    (* ram_style="distributed" *) reg [95:0] kept[0:31];
    (* ram_style="distributed" *) reg [95:0] extras[0:95];
    (* ram_style="distributed" *) reg [35:0] parents[0:31];
    reg [5:0] nk,np;
    reg [6:0] ne,scan,i,j,shift_idx,sort_end;
    reg [95:0] a,b,swap_record;
    reg [95:0] query_latched;
    reg [7:0] state,return_state;
    reg [2:0] compare_kind;
    reg [8:0] aw,ah,bw,bh,iw,ih,gx,gy;
    reg [17:0] aa,ba,ia;
    reg [24:0] lhs,rhs;
    reg hit;
    reg [10:0] dx0[0:31],dy0[0:31],dx1[0:31],dy1[0:31];
    reg [8:0] mapped_x0,mapped_y0,mapped_x1,mapped_y1;
    localparam IDLE=0,POOL=1,BASE=2,BRANCH=3,PARENT=4,PARENT_TEST=5,
        KDUP=6,KTEST=7,UNIQUE=8,UTEST=9,STORE=10,NEXT=11,
        MERGE_I=12,MERGE_J=13,MERGE_TEST=14,MERGE_WRITE=15,
        SHIFT=16,SORT_INIT=17,SORT_PAIR=18,SORT_WRITE=19,SORT_SECOND=20,
        APPEND=21,APPEND_SCAN=22,APPEND_TEST=23,APPEND_STORE=24,
        PUB_READ=25,PUB_WRITE=26,COMP_DIMS=27,COMP_MULT=28,COMP_SCALE=29,COMP_RESULT=30,
        PASS_END=31,PUB_MAP=32;
    function [8:0] min9;input [8:0] x,y;begin min9=x<y?x:y;end endfunction
    function [8:0] max9;input [8:0] x,y;begin max9=x>y?x:y;end endfunction
    function [8:0] padlow;input [8:0] x;begin padlow=x<3?0:x-3;end endfunction
    function [8:0] padhigh;input [8:0] x;begin padhigh=x>253?256:x+3;end endfunction
    function [8:0] mapx;input [8:0] x;reg [12:0] v;begin v=x*15+8;mapx=40+(v>>4);end endfunction
    function [8:0] mapy;input [8:0] x;reg [12:0] v;begin v=x*15+8;mapy=v>>4;end endfunction
    wire [5:0] kept_read=busy?scan[5:0]:query_index;
    wire [95:0] kr=kept[kept_read];
    wire [95:0] er=extras[scan];
    wire [35:0] pr=parents[scan[4:0]];
    reg ew,kw;
    reg [6:0] ewa;
    reg [4:0] kwa;
    reg [95:0] ewd,kwd;
    wire swap_needed=a[86:85]>er[86:85] || (a[86:85]==er[86:85] && a[84:53]<er[84:53]);
    wire base_keep=a[26:18]-a[8:0]<85 && a[35:27]-a[17:9]<85 &&
        !(a[52:36]>=200 && a[84:53]<a[52:36]*3);
    // Explicit single write port: prevents replication for each FSM write site.
    always @*begin
        ew=0;ewa=0;ewd=0;kw=0;kwa=nk[4:0];kwd=a;
        case(state)
            BASE:kw=base_keep;
            APPEND_SCAN:kw=scan==nk;
            STORE:begin ew=ne<96;ewa=ne;ewd=a;end
            MERGE_TEST:begin
                ew=hit;ewa=i;
                ewd={a[95:85],(a[84:53]>b[84:53]?a[84:53]:b[84:53]),a[52:36],
                    max9(a[35:27],b[35:27]),max9(a[26:18],b[26:18]),min9(a[17:9],b[17:9]),min9(a[8:0],b[8:0])};
            end
            SHIFT:begin ew=shift_idx+1<ne;ewa=shift_idx;ewd=er;end
            SORT_WRITE:begin ew=swap_needed;ewa=scan-1;ewd=er;end
            SORT_SECOND:begin ew=1;ewa=scan;ewd=swap_record;end
            default:;
        endcase
    end
    always @(posedge clk)begin
        if(ew)extras[ewa]<=ewd;
        if(kw)kept[kwa]<=kwd;
    end
    assign query_record=query_latched;
    wire [8:0] qx0=mapx(query_latched[8:0])>279?279:mapx(query_latched[8:0]);
    wire [8:0] qy0=mapy(query_latched[17:9])>239?239:mapy(query_latched[17:9]);
    wire [8:0] qx1=mapx(query_latched[26:18])>qx0?mapx(query_latched[26:18])-1:qx0;
    wire [8:0] qy1=mapy(query_latched[35:27])>qy0?mapy(query_latched[35:27])-1:qy0;
    assign query_display=query_index>=count?32'd0:(query_corner?
        {7'd0,qy1,7'd0,qx1}:{7'd0,qy0,7'd0,qx0});
    wire [8:0] ax0=mapx(a[8:0])>279?279:mapx(a[8:0]);
    wire [8:0] ay0=mapy(a[17:9])>239?239:mapy(a[17:9]);
    wire [8:0] ax1=mapx(a[26:18])>ax0?mapx(a[26:18])-1:ax0;
    wire [8:0] ay1=mapy(a[35:27])>ay0?mapy(a[35:27])-1:ay0;
    wire [8:0] ix0=max9(a[8:0],b[8:0]),iy0=max9(a[17:9],b[17:9]);
    wire [8:0] ix1=min9(a[26:18],b[26:18]),iy1=min9(a[35:27],b[35:27]);
    wire [8:0] gapx=ix0>ix1?ix0-ix1:0,gapy=iy0>iy1?iy0-iy1:0;
    wire [17:0] small_area=aa<ba?aa:ba;
    genvar g;
    generate for(g=0;g<32;g=g+1)begin:boxes
        assign box_bus[8+44*g+:44]={dy1[g],dx1[g],dy0[g],dx0[g]};
    end endgenerate
    assign box_bus[0]=overlay_enable;
    assign box_bus[6:1]=count;
    assign box_bus[7]=0;
    assign box_bus[1535:1416]=0;
    integer n;
    always @(posedge clk)begin
        if(!rst_n)begin
            nk<=0;np<=0;ne<=0;count<=0;busy<=0;pass_done<=0;final_ready<=0;publish<=0;error<=0;
            state<=IDLE;pool_index<=0;scan<=0;i<=0;j<=0;shift_idx<=0;sort_end<=0;
            a<=0;b<=0;swap_record<=0;return_state<=0;compare_kind<=0;hit<=0;
            query_latched<=0;
            aw<=0;ah<=0;bw<=0;bh<=0;iw<=0;ih<=0;gx<=0;gy<=0;aa<=0;ba<=0;ia<=0;lhs<=0;rhs<=0;
            mapped_x0<=0;mapped_y0<=0;mapped_x1<=0;mapped_y1<=0;
            for(n=0;n<32;n=n+1)begin dx0[n]<=0;dy0[n]<=0;dx1[n]<=0;dy1[n]<=0;end
        end else begin
            publish<=0;pass_done<=0;
            if(!busy)query_latched<=query_index<count?kr:96'd0;
            if(parent_valid && mode==0 && !error)begin
                if(np<32)begin parents[np[4:0]]<=parent_bbox;np<=np+1;end
                else error<=1;
            end
            case(state)
                IDLE:if(start_pass && !error)begin busy<=1;pool_index<=0;state<=POOL;end
                POOL:begin
                    if(pool_index==pool_count)state<=PASS_END;
                    else begin a<=pool_record;state<=mode==0?BASE:BRANCH;end
                end
                BASE:begin
                    if(base_keep)begin
                        nk<=nk+1;
                    end
                    state<=NEXT;
                end
                BRANCH:begin
                    if(a[52:36]<20 || a[8:0]==0 || a[17:9]==0 || a[26:18]>=256 || a[35:27]>=256)state<=NEXT;
                    else begin
                        a[35:0]<={padhigh(a[35:27]),padhigh(a[26:18]),padlow(a[17:9]),padlow(a[8:0])};
                        a[86:85]<=mode-1'b1;scan<=0;state<=PARENT;
                    end
                end
                PARENT:begin
                    if(scan==np)state<=NEXT;
                    else begin b<={60'd0,pr};compare_kind<=0;return_state<=PARENT_TEST;state<=COMP_DIMS;end
                end
                PARENT_TEST:if(hit)begin scan<=0;state<=KDUP;end else begin scan<=scan+1;state<=PARENT;end
                KDUP:begin
                    if(scan==nk)begin scan<=0;state<=UNIQUE;end
                    else begin b<=kr;compare_kind<=1;return_state<=KTEST;state<=COMP_DIMS;end
                end
                KTEST:if(hit)state<=NEXT;else begin scan<=scan+1;state<=KDUP;end
                UNIQUE:begin
                    if(scan==ne)state<=STORE;
                    else begin b<=er;compare_kind<=2;return_state<=UTEST;state<=COMP_DIMS;end
                end
                UTEST:if(hit)state<=NEXT;else begin scan<=scan+1;state<=UNIQUE;end
                STORE:begin
                    if(ne<96)begin ne<=ne+1;end else error<=1;
                    state<=NEXT;
                end
                NEXT:begin pool_index<=pool_index+1;state<=POOL;end
                PASS_END:begin
                    if(mode==3)begin i<=0;state<=MERGE_I;end
                    else if(mode==0 && np==0)begin scan<=0;state<=PUB_READ;end
                    else begin busy<=0;pass_done<=1;state<=IDLE;end
                end
                MERGE_I:begin
                    if(i>=ne)state<=SORT_INIT;
                    else begin scan<=i;state<=MERGE_J;j<=i+1;end
                end
                MERGE_J:begin
                    if(j>=ne)begin i<=i+1;state<=MERGE_I;end
                    else begin a<=er;scan<=j;state<=MERGE_WRITE;end
                end
                // Load the second operand after the single asynchronous extra read changes.
                MERGE_WRITE:begin b<=er;compare_kind<=3;return_state<=MERGE_TEST;state<=COMP_DIMS;end
                MERGE_TEST:begin
                    if(hit)begin
                        shift_idx<=j;scan<=j+1;state<=SHIFT;
                    end else begin j<=j+1;scan<=i;state<=MERGE_J;end
                end
                SHIFT:begin
                    if(shift_idx+1>=ne)begin ne<=ne-1;i<=0;state<=MERGE_I;end
                    else begin shift_idx<=shift_idx+1;scan<=scan+1;end
                end
                SORT_INIT:begin sort_end<=ne;scan<=0;state<=SORT_PAIR;end
                SORT_PAIR:begin
                    if(sort_end<=1)begin i<=0;state<=APPEND;end
                    else if(scan+1>=sort_end)begin sort_end<=sort_end-1;scan<=0;end
                    else begin a<=er;scan<=scan+1;state<=SORT_WRITE;end
                end
                SORT_WRITE:begin
                    if(swap_needed)begin
                        swap_record<=a;state<=SORT_SECOND;
                    end else state<=SORT_PAIR;
                end
                SORT_SECOND:begin state<=SORT_PAIR;end
                APPEND:begin
                    if(i>=ne || nk==32)begin scan<=0;state<=PUB_READ;end
                    else begin scan<=i;state<=APPEND_STORE;end
                end
                APPEND_STORE:begin a<=er;scan<=0;state<=APPEND_SCAN;end
                APPEND_SCAN:begin
                    if(scan==nk)begin nk<=nk+1;i<=i+1;state<=APPEND;end
                    else begin b<=kr;compare_kind<=1;return_state<=APPEND_TEST;state<=COMP_DIMS;end
                end
                APPEND_TEST:if(hit)begin i<=i+1;state<=APPEND;end else begin scan<=scan+1;state<=APPEND_SCAN;end
                PUB_READ:begin
                    if(scan==nk)begin count<=nk;final_ready<=1;publish<=1;pass_done<=1;busy<=0;state<=IDLE;end
                    else begin a<=kr;state<=PUB_MAP;end
                end
                PUB_MAP:begin
                    mapped_x0<=ax0;mapped_y0<=ay0;mapped_x1<=ax1;mapped_y1<=ay1;state<=PUB_WRITE;
                end
                PUB_WRITE:begin
                    dx0[scan[4:0]]<=mapped_x0*3+160;dy0[scan[4:0]]<=mapped_y0*3;
                    dx1[scan[4:0]]<=mapped_x1*3+162;dy1[scan[4:0]]<=mapped_y1*3+2;
                    scan<=scan+1;state<=PUB_READ;
                end
                COMP_DIMS:begin
                    aw<=a[26:18]-a[8:0];ah<=a[35:27]-a[17:9];bw<=b[26:18]-b[8:0];bh<=b[35:27]-b[17:9];
                    iw<=ix1>ix0?ix1-ix0:0;ih<=iy1>iy0?iy1-iy0:0;gx<=gapx;gy<=gapy;state<=COMP_MULT;
                end
                COMP_MULT:begin aa<=aw*ah;ba<=bw*bh;ia<=iw*ih;state<=COMP_SCALE;end
                COMP_SCALE:begin
                    case(compare_kind)
                        0:begin lhs<=ia*100;rhs<=aa*80;end
                        1:begin lhs<=ia*2;rhs<=small_area;end
                        2:begin lhs<=ia*100;rhs<=small_area*65;end
                        default:begin lhs<=ia*4;rhs<=small_area;end
                    endcase
                    state<=COMP_RESULT;
                end
                COMP_RESULT:begin hit<=lhs>=rhs || (compare_kind==3 && small_area<=200 && gx<=3 && gy<=3);state<=return_state;end
                default:begin error<=1;busy<=0;state<=IDLE;end
            endcase
            if(abort_work)begin busy<=0;state<=IDLE;end
            if(begin_frame)begin nk<=0;np<=0;ne<=0;count<=0;final_ready<=0;error<=0;busy<=0;state<=IDLE;end
        end
    end
endmodule

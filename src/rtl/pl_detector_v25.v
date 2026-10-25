// Four profiles share one detector engine. PS only supplies the same RGB frame
// and selects passes; fusion and all detection decisions remain in PL.
`timescale 1ns/1ps
module pl_detector_v25(
    input wire clk,rst_n,upload_we,
    input wire [16:0] upload_addr,
    input wire [7:0] upload_data,
    input wire overlay_enable,
    output wire [1535:0] box_bus,
    output reg commit_toggle,display_hold,
    output wire detector_active,
    output reg [31:0] status
);
    reg [1:0] mode;
    reg [7:0] selector;
    reg active,running,done,failed,await_engine;
    reg [31:0] cycles;
    reg [31:0] next_status;
    wire command=upload_we && upload_addr==80007;
    wire begin_frame=command && upload_data==1 && mode==0;
    wire abort_work=command && upload_data==3;
    wire eb,ed,ee,fb,fd,fr,fp,fe;
    wire [5:0] pc,pi,count;
    wire [95:0] record,query_record;
    wire [31:0] query_display;
    reg [5:0] qi;
    wire pv;
    wire [35:0] pb;
    wire [31:0] engine_status;
    wire start_fusion=await_engine && ed && !ee;
    pl_pest_engine_v25 engine(
        .clk(clk),.rst_n(rst_n),.upload_we(upload_we),.upload_addr(upload_addr),.upload_data(upload_data),
        .overlay_enable(overlay_enable),.profile_mode(mode),.query_index(pi),.query_record(record),.pool_count(pc),
        .engine_busy(eb),.engine_done(ed),.engine_error(ee),.parent_valid(pv),.parent_bbox(pb),
        .box_bus(),.commit_toggle(),.display_hold(),.detector_active(),.status(engine_status));
    pl_candidate_fusion fusion(
        .clk(clk),.rst_n(rst_n),.begin_frame(begin_frame),.abort_work(abort_work),.start_pass(start_fusion),
        .mode(mode),.pool_count(pc),.pool_index(pi),.pool_record(record),.parent_valid(pv),.parent_bbox(pb),
        .query_index(qi),.query_record(query_record),.query_corner(selector[0]),.query_display(query_display),
        .busy(fb),.pass_done(fd),.final_ready(fr),.publish(fp),.error(fe),.count(count),
        .box_bus(box_bus),.overlay_enable(overlay_enable));
    assign detector_active=active;
    always @*begin
        next_status={8'hD2,10'd0,count,4'd0,active,(failed|ee|fe),done,running};
        if(selector==1)next_status=cycles;
        if(selector==2)next_status=engine_status;
`ifdef PL_RELEASE_26
        if(selector==3)next_status=32'h00020006;
`else
        if(selector==3)next_status=32'h00020005;
`endif
        if(selector==4)next_status={30'd0,fr,done};
        if(selector>=16 && selector<80)next_status=query_display;
        if(selector>=80 && selector<144)begin
            if(selector[0])next_status={7'd0,query_record[35:27],7'd0,query_record[26:18]};
            else next_status={7'd0,query_record[17:9],7'd0,query_record[8:0]};
        end
        if(selector>=144 && selector<176)next_status={15'd0,query_record[52:36]};
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            mode<=0;selector<=0;active<=0;running<=0;done<=0;failed<=0;await_engine<=0;
            cycles<=0;commit_toggle<=0;display_hold<=0;status<=0;qi<=0;
        end else begin
            // Split selector arithmetic / LUT-RAM read / AXI read-data paths.
            qi<=selector>=144?selector-144:(selector>=80?(selector-80)>>1:(selector-16)>>1);
            status<=next_status;
            if(running)cycles<=cycles+1;
            if(start_fusion)await_engine<=0;
            if(fd)begin running<=0;done<=1;end
            if(fp)commit_toggle<=~commit_toggle;
            if(running && (ee||fe))begin failed<=1;running<=0;await_engine<=0;end
            if(upload_we && upload_addr==80005)selector<=upload_data;
            if(command)case(upload_data)
                1:begin active<=1;running<=0;done<=0;failed<=0;await_engine<=0;cycles<=0;
                    if(mode==0)commit_toggle<=~commit_toggle;end
                2:begin running<=1;done<=0;await_engine<=1;end
                3:begin active<=0;running<=0;done<=0;failed<=0;await_engine<=0;end
                5:display_hold<=1;
                6:display_hold<=0;
                7:mode<=selector[1:0];
                default:;
            endcase
        end
    end
endmodule

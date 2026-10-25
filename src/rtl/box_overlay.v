// ============================================================================
// box_overlay.v —— 在像素流水线上实时画红色标注框  V1.0
//
// 【做什么】
//   拿到 8 个矩形框（PS 算好的病灶外接矩形，像素域总线），
//   对当前扫描到的像素 (x,y) 判断"是否落在某个框的边框带上"，
//   是则输出红色。
//
//   注意：只画【边框】不填满内部 —— 病灶本身还能看见，
//   这是工业检测软件的标准画法。
//
// 【纯组合逻辑，零延迟】
//   整个模块没有寄存器：判断和输出都在同一拍完成。
//   所以它不会给视频流水线增加任何延迟，也不会占用 CPU。
//
// 【资源】
//   8 个框 × 4 个比较器 + 边框带判断 ≈ 300~400 个 LUT。
//   当前 LUT 用了 8.7%（约 1530 个），加上后约 11%，余量充足。
//
// 【总线格式】（与 axil_regs 的 box_bus 一致）
//   bus[0]        = 总开关（1 = 画框）
//   bus[4:1]      = 有效框数量 box_cnt（0~8）
//   bus[8+44*i +: 44] = 第 i 个框 {x0[10:0], y0[10:0], x1[10:0], y1[10:0]}
// ============================================================================
`timescale 1ns / 1ps

module box_overlay #(
    parameter NB  = 8,       // 最多几个框
    parameter TH  = 3,       // 边框线宽（像素）
    parameter CW  = 11,      // 坐标位宽（1280/720 只需 11 位）
    parameter CNT_W = NB>16?6:(NB>8?5:4),
    parameter W   = 384      // 总线总位宽
)(
    input  wire [W-1:0]   bus,      // 来自 cdc_boxes 的影子寄存器
    input  wire [15:0]    x,        // 当前像素坐标（已与 rgb 对齐）
    input  wire [15:0]    y,
    output wire           hit       // 1 = 该像素属于某个框的边框
);

    localparam FW = 4*CW;    // 每个框 44 位

    wire        en   = bus[0];
    wire [CNT_W-1:0] cnt = bus[CNT_W:1];

    wire [NB-1:0] hit_of;      // 每个框的命中结果（声明必须在 generate 之前）

    genvar i;
    generate
        for (i = 0; i < NB; i = i + 1) begin : g_box
            localparam B = 8 + i*FW;   // 本框在总线上的起始位

            wire [CW-1:0] x0 = bus[B              +: CW];
            wire [CW-1:0] y0 = bus[B + 1*CW       +: CW];
            wire [CW-1:0] x1 = bus[B + 2*CW       +: CW];
            wire [CW-1:0] y1 = bus[B + 3*CW       +: CW];

            // 先用 11 位比较（x,y 只可能是 0..1279 / 0..719）
            wire [CW-1:0] xi = x[CW-1:0];
            wire [CW-1:0] yi = y[CW-1:0];

            wire inside = (xi >= x0) && (xi <= x1) && (yi >= y0) && (yi <= y1);

            // 边框带：距任一边小于 TH 像素
            wire [CW-1:0] d_left   = xi - x0;
            wire [CW-1:0] d_right  = x1 - xi;
            wire [CW-1:0] d_top    = yi - y0;
            wire [CW-1:0] d_bottom = y1 - yi;

            wire on_edge = (d_left  < TH) || (d_right  < TH) ||
                           (d_top   < TH) || (d_bottom < TH);

            // 该框是否启用（cnt 控制有几个框有效）
            wire valid = (i < cnt);

            assign hit_of[i] = valid && inside && on_edge;
        end
    endgenerate

    assign hit = en & (|hit_of);

endmodule

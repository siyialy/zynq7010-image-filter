// ============================================================================
// axil_regs.v —— AXI4-Lite 从机寄存器组（PS 控制 PL 的"遥控器"）  V1.2
//
// 【寄存器映射】
//   偏移   名字        方向   说明
//   0x00   CTRL        R/W    bit0 = filter_en（1=开滤波，0=直通灰度）
//   0x04   MODE        R/W    [2:0] 滤波模式 0灰度 1均值 2高斯 3Sobel
//   0x08   THRESH      R/W    [7:0] 预留（Sobel 二值化阈值等）
//   0x0C   VERSION     R      固定 0x0001_0000（给软件确认硬件在）
//   0x10   FRAME_CNT   R      帧计数器（由 PL 逻辑提供）
//   0x14   STATUS      R      状态字（由 PL 逻辑提供）
//   0x20   IMG_ADDR    R/W    图像缓冲区字节地址（0..76799）
//   0x24   IMG_DATA    W      向 IMG_ADDR 起写 4 个字节，写完 IMG_ADDR += 4
//   0x28   IMG_ADDR_R  R      回读当前 IMG_ADDR（调试用）
//
// 【V1.2 新增：图像上传通道】
//   PS 往 0x24 写一个 32 位字，硬件就把它拆成 4 个字节，
//   依次写进 img_buf 的 [IMG_ADDR], [IMG_ADDR+1], [IMG_ADDR+2], [IMG_ADDR+3]，
//   然后把 IMG_ADDR 自增 4。
//
//   为什么用"写一个寄存器就进 4 字节"这种设计：
//     - 一次 AXI 写传 4 个像素，76800 字节只需 19200 次写（约 2ms）
//     - 不用为图像单独做 AXI 主机/DMA，逻辑极简
//
//   突发期间把 awready/wready 拉低，主机自然会等 —— 不会丢写。
//
// 【V1.1 修复记录 —— 这是一个真实上板才暴露的 bug】
//   V1.0 的写通道写的是：
//       wire wr_fire = awvalid & wvalid & awready & wready;
//   即"地址和数据必须在同一拍到达"。
//   这在 testbench 里没问题（我的 tb 同时给了 awvalid 和 wvalid），
//   但真机上 Zynq 的 AXI 主机允许 AW 和 W 分开到达：
//       - 第一拍：AWVALID=1（被 awready 收下）
//       - 第二拍：WVALID=1（被 wready 收下）
//   结果 wr_fire 永远是 0 → 写丢失 → BVALID 永远不拉高
//   → **ARM 的 Xil_Out32 永久阻塞，CPU 卡死，什么都不输出**。
//
//   现象：程序 PC 停在 DDR 里，没有串口输出，PL 的模式寄存器始终为 0。
//
//   修复：AW 和 W 各自独立握手、各自锁存，两者都到齐后再执行写。
//   这是 AXI4-Lite 从机的正确写法，也是唯一能兼容所有主机的写法。
// ============================================================================
`timescale 1ns / 1ps

module axil_regs #(
    parameter ADDR_W = 8
)(
    // ---- AXI4-Lite 从机接口 ----
    input  wire              s_axi_aclk,
    input  wire              s_axi_aresetn,     // 低有效

    input  wire [ADDR_W-1:0] s_axi_awaddr,
    input  wire              s_axi_awvalid,
    output reg               s_axi_awready,

    input  wire [31:0]       s_axi_wdata,
    input  wire [3:0]        s_axi_wstrb,
    input  wire              s_axi_wvalid,
    output reg               s_axi_wready,

    output reg  [1:0]        s_axi_bresp,
    output reg               s_axi_bvalid,
    input  wire              s_axi_bready,

    input  wire [ADDR_W-1:0] s_axi_araddr,
    input  wire              s_axi_arvalid,
    output reg               s_axi_arready,

    output reg  [31:0]       s_axi_rdata,
    output reg  [1:0]        s_axi_rresp,
    output reg               s_axi_rvalid,
    input  wire              s_axi_rready,

    // ---- 给用户逻辑的寄存器 ----
    output reg  [2:0]        mode,
    output reg  [7:0]        threshold,
    output reg               filter_en,

    input  wire [31:0]       frame_cnt,
    input  wire [31:0]       status,

    // ---- 图像缓冲区写接口（AXI 时钟域，直连 img_buf 的 B 口）----
    output wire              img_we,
    output wire [16:0]       img_addr,
    output wire [7:0]        img_data,

    // ---- 标框配置总线（AXI 时钟域，交给 cdc_boxes 同步到像素域）----
    output wire [383:0]      box_bus,
    output wire              commit_tog
);

    localparam VERSION = 32'h0001_0000;

    wire [7:0] wr_addr = s_axi_awaddr[7:0];
    wire [7:0] rd_addr = s_axi_araddr[7:0];

    // ==================================================================
    // 写通道：AW / W 各自独立锁存
    // ==================================================================
    reg        aw_got;          // 地址已收到
    reg        w_got;           // 数据已收到
    reg [7:0]  aw_addr_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;

    // ---- 图像上传突发的状态 ----
    reg        burst;           // 突发进行中
    reg [1:0]  bcnt;            // 0..3
    reg [16:0] bbase;           // 突发起始地址
    reg [31:0] bdata;           // 本拍要写的 4 个字节
    reg [16:0] img_addr_q;      // 下一个字节地址

    // ---- 标框寄存器（最多 8 个框）----
    reg [10:0] bx0 [0:7];
    reg [10:0] by0 [0:7];
    reg [10:0] bx1 [0:7];
    reg [10:0] by1 [0:7];
    reg [3:0]  box_cnt;
    reg        overlay_en;
    reg        commit_tog_r;

    // 框地址解码：0x2C 起每 8 字节一个框，+0 是 (x0,y0)，+4 是 (x1,y1)
    wire [7:0] box_off = (aw_addr_q - 8'h2C) & 8'h07;
    wire       box_hi  = box_off[2];
    wire [2:0] box_idx = (aw_addr_q - 8'h2C) >> 3;
    integer    i;

    assign commit_tog = commit_tog_r;

    assign img_we   = burst;
    assign img_addr = bbase + bcnt;
    assign img_data = bdata[bcnt*8 +: 8];

    // ==================================================================
    // 标框配置总线：{保留, 8 个框 × 44 位, box_cnt, 总开关}
    //   每个框 44 位 = {x0[10:0], y0[10:0], x1[10:0], y1[10:0]}
    // ==================================================================
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_pack
            // 低位在前：x0 占 [10:0]，y0 占 [21:11]，x1 占 [32:22]，y1 占 [43:33]
            // 必须与 box_overlay 的解码顺序严格一致
            assign box_bus[8 + gi*44 +: 44] = {by1[gi], bx1[gi], by0[gi], bx0[gi]};
        end
    endgenerate
    assign box_bus[0]   = overlay_en;
    assign box_bus[4:1] = box_cnt;
    assign box_bus[383:360] = 24'd0;   // 其余补零

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_got        <= 1'b0;
            w_got         <= 1'b0;
            aw_addr_q     <= 8'd0;
            wdata_q       <= 32'd0;
            wstrb_q       <= 4'd0;
            filter_en     <= 1'b0;
            mode          <= 3'd0;
            threshold     <= 8'd0;
            burst         <= 1'b0;
            bcnt          <= 2'd0;
            bbase         <= 17'd0;
            bdata         <= 32'd0;
            img_addr_q    <= 17'd0;
            box_cnt       <= 4'd0;
            overlay_en    <= 1'b0;
            commit_tog_r  <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                bx0[i] <= 11'd0; by0[i] <= 11'd0;
                bx1[i] <= 11'd0; by1[i] <= 11'd0;
            end
        end
        else begin
            // ---- ready：突发期间不接受新事务 ----
            s_axi_awready <= ~aw_got & ~s_axi_bvalid & ~burst;
            s_axi_wready  <= ~w_got  & ~s_axi_bvalid & ~burst;

            // ---- 独立接收地址 ----
            if (s_axi_awvalid && s_axi_awready) begin
                aw_addr_q <= wr_addr;
                aw_got    <= 1'b1;
            end

            // ---- 独立接收数据 ----
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                w_got   <= 1'b1;
            end

            // ---- 两者都到齐 ----
            if (aw_got && w_got) begin
                aw_got <= 1'b0;
                w_got  <= 1'b0;

                if (aw_addr_q == 8'h24) begin
                    // IMG_DATA：启动 4 字节突发
                    bbase  <= img_addr_q;
                    bdata  <= wdata_q;
                    bcnt   <= 2'd0;
                    burst  <= 1'b1;
                end
                else begin
                    if (aw_addr_q >= 8'h2C && aw_addr_q <= 8'h6B) begin
                        // ---- 8 个框，每个占 8 字节 ----
                        //   +0 : {保留, y0[10:0], 保留, x0[10:0]}
                        //   +4 : {保留, y1[10:0], 保留, x1[10:0]}
                        if (box_hi) begin
                            bx1[box_idx] <= wdata_q[10:0];
                            by1[box_idx] <= wdata_q[26:16];
                        end
                        else begin
                            bx0[box_idx] <= wdata_q[10:0];
                            by0[box_idx] <= wdata_q[26:16];
                        end
                    end
                    else case (aw_addr_q)
                        8'h00: filter_en  <= wdata_q[0];
                        8'h04: mode       <= wdata_q[2:0];
                        8'h08: threshold  <= wdata_q[7:0];
                        8'h20: img_addr_q <= wdata_q[16:0];
                        8'h6C: box_cnt    <= wdata_q[3:0];
                        8'h70: begin
                            overlay_en   <= wdata_q[0];
                            commit_tog_r <= ~commit_tog_r;   // 每次写都提交一次
                        end
                        default: ;   // 只读寄存器忽略写入
                    endcase
                    s_axi_bvalid <= 1'b1;
                end
            end

            // ---- 突发推进：bcnt 0→3 写四个字节，之后回响应 ----
            if (burst) begin
                if (bcnt == 2'd3) begin
                    burst        <= 1'b0;
                    img_addr_q   <= bbase + 17'd4;
                    s_axi_bvalid <= 1'b1;
                end
                else begin
                    bcnt <= bcnt + 2'd1;
                end
            end

            // ---- 主机收走响应 ----
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    // ==================================================================
    // 读通道
    // ==================================================================
    wire rd_fire = s_axi_arvalid & s_axi_arready;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
        end
        else begin
            s_axi_arready <= ~s_axi_rvalid;

            if (rd_fire) begin
                s_axi_rvalid <= 1'b1;
                case (rd_addr)
                    8'h00: s_axi_rdata <= {31'd0, filter_en};
                    8'h04: s_axi_rdata <= {29'd0, mode};
                    8'h08: s_axi_rdata <= {24'd0, threshold};
                    8'h0C: s_axi_rdata <= VERSION;
                    8'h10: s_axi_rdata <= frame_cnt;
                    8'h14: s_axi_rdata <= status;
                    8'h20: s_axi_rdata <= {15'd0, img_addr_q};
                    8'h28: s_axi_rdata <= {15'd0, img_addr_q};
                    default: s_axi_rdata <= 32'hDEAD_BEEF;   // 非法地址给个标记
                endcase
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // 响应码固定 OKAY
    always @(*) begin
        s_axi_bresp = 2'b00;
        s_axi_rresp = 2'b00;
    end

endmodule

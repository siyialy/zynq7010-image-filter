// ============================================================================
// axil_regs.v —— AXI4-Lite 从机寄存器组（PS 控制 PL 的"遥控器"）
//
// 【寄存器映射】
//   偏移   名字        方向   说明
//   0x00   CTRL        R/W    bit0 = filter_en（1=开滤波，0=直通）
//   0x04   MODE        R/W    [2:0] 滤波模式 0灰度 1均值 2高斯 3Sobel
//   0x08   THRESH      R/W    [7:0] 预留（比如 Sobel 的二值化阈值）
//   0x0C   VERSION     R      固定 0x0001_0000（给软件确认硬件在）
//   0x10   FRAME_CNT   R      帧计数器（由 PL 逻辑提供）
//   0x14   STATUS      R      状态字（由 PL 逻辑提供）
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
    input  wire [31:0]       status
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
        end
        else begin
            // ---- ready 的产生：还没收到、且没有未完成的响应时，可以接收 ----
            s_axi_awready <= ~aw_got & ~s_axi_bvalid;
            s_axi_wready  <= ~w_got  & ~s_axi_bvalid;

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

            // ---- 两者都到齐：执行写，回 BVALID ----
            if (aw_got && w_got) begin
                case (aw_addr_q)
                    8'h00: filter_en <= wdata_q[0];
                    8'h04: mode      <= wdata_q[2:0];
                    8'h08: threshold <= wdata_q[7:0];
                    // 0x0C/0x10/0x14 只读，忽略写入
                    default: ;
                endcase
                aw_got        <= 1'b0;
                w_got         <= 1'b0;
                s_axi_bvalid  <= 1'b1;
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

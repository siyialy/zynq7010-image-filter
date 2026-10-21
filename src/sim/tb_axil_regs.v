// ============================================================================
// tb_axil_regs.v —— AXI4-Lite 寄存器组自检
//
// 验证 6 件事：
//   1. 写 MODE=3，读回来是 3
//   2. 写 THRESH=0x64，读回来是 0x64
//   3. 写 CTRL 打开滤波使能，filter_en 变 1
//   4. 读 VERSION = 0x0001_0000（软件用它确认"硬件在位"）
//   5. 读 FRAME_CNT / STATUS（只读寄存器来自 PL 逻辑）
//   6. 往只读寄存器写数据，读回来必须不变
// ============================================================================
`timescale 1ns / 1ps

module tb_axil_regs;

    reg         clk;
    reg         aresetn;

    reg  [7:0]  awaddr;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg  [7:0]  araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    wire [2:0]  mode;
    wire [7:0]  threshold;
    wire        filter_en;

    reg  [31:0] frame_cnt;
    reg  [31:0] status;

    integer errors;
    reg     sim_done;
    integer i;
    reg [31:0] got;

    // ---------- 被测模块 ----------
    axil_regs u_dut (
        .s_axi_aclk     (clk),
        .s_axi_aresetn  (aresetn),
        .s_axi_awaddr   (awaddr),
        .s_axi_awvalid  (awvalid),
        .s_axi_awready  (awready),
        .s_axi_wdata    (wdata),
        .s_axi_wstrb    (wstrb),
        .s_axi_wvalid   (wvalid),
        .s_axi_wready   (wready),
        .s_axi_bresp    (bresp),
        .s_axi_bvalid   (bvalid),
        .s_axi_bready   (bready),
        .s_axi_araddr   (araddr),
        .s_axi_arvalid  (arvalid),
        .s_axi_arready  (arready),
        .s_axi_rdata    (rdata),
        .s_axi_rresp    (rresp),
        .s_axi_rvalid   (rvalid),
        .s_axi_rready   (rready),
        .mode           (mode),
        .threshold      (threshold),
        .filter_en      (filter_en),
        .frame_cnt      (frame_cnt),
        .status         (status)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;      // 100MHz AXI 时钟

    // ---------- AXI 写事务 ----------
    // 驱动纪律：信号在【下降沿】改变，DUT 在【上升沿】采样，避免同沿竞争
    task axi_write;
        input [7:0]  addr;
        input [31:0] din;
        begin
            @(negedge clk);
            awaddr  = addr;
            awvalid = 1'b1;
            wdata   = din;
            wstrb   = 4'hF;
            wvalid  = 1'b1;
            @(posedge clk);
            while (!(awready && wready)) @(posedge clk);   // 本拍被采纳
            @(negedge clk);
            awvalid = 1'b0;
            wvalid  = 1'b0;
            while (!bvalid) @(negedge clk);
            bready = 1'b1;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    // ---------- AXI 写事务（地址与数据分开到达）----------
    // 这是真机 Zynq 的行为：AW 和 W 可以差好几拍。
    // V1.0 的从机在这种时序下会丢写并卡死 CPU，这个任务是那个 bug 的回归测试。
    task axi_write_split;
        input [7:0]  addr;
        input [31:0] din;
        input integer gap;          // 地址与数据之间隔几拍
        input integer w_first;      // 1 = 先给数据再给地址
        integer k;
        begin
            if (w_first) begin
                @(negedge clk);
                wdata  = din;
                wstrb  = 4'hF;
                wvalid = 1'b1;
                @(posedge clk);
                while (!wready) @(posedge clk);
                @(negedge clk);
                wvalid = 1'b0;
                for (k = 0; k < gap; k = k + 1) @(negedge clk);
                awaddr  = addr;
                awvalid = 1'b1;
                @(posedge clk);
                while (!awready) @(posedge clk);
                @(negedge clk);
                awvalid = 1'b0;
            end
            else begin
                @(negedge clk);
                awaddr  = addr;
                awvalid = 1'b1;
                @(posedge clk);
                while (!awready) @(posedge clk);
                @(negedge clk);
                awvalid = 1'b0;
                for (k = 0; k < gap; k = k + 1) @(negedge clk);
                wdata  = din;
                wstrb  = 4'hF;
                wvalid = 1'b1;
                @(posedge clk);
                while (!wready) @(posedge clk);
                @(negedge clk);
                wvalid = 1'b0;
            end
            while (!bvalid) @(negedge clk);
            bready = 1'b1;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    // ---------- AXI 读事务 ----------
    task axi_read;
        input  [7:0]  addr;
        output [31:0] dout;
        begin
            @(negedge clk);
            araddr  = addr;
            arvalid = 1'b1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            @(negedge clk);
            arvalid = 1'b0;
            while (!rvalid) @(negedge clk);
            dout   = rdata;             // rvalid 有效时数据有效
            rready = 1'b1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task check;
        input [31:0] actual;
        input [31:0] expect;
        input [255:0] name;
        begin
            if (actual !== expect) begin
                $display("FAIL: %0s = 0x%08h, expect 0x%08h", name, actual, expect);
                errors = errors + 1;
            end
            else begin
                $display("PASS: %0s = 0x%08h", name, actual);
            end
        end
    endtask

    // ---------- 主流程 ----------
    initial begin
        errors    = 0;
        sim_done  = 1'b0;
        aresetn   = 1'b0;
        awaddr    = 8'd0;  awvalid = 1'b0;
        wdata     = 32'd0; wstrb = 4'hF; wvalid = 1'b0;
        bready    = 1'b0;
        araddr    = 8'd0;  arvalid = 1'b0;
        rready    = 1'b0;
        frame_cnt = 32'd0;
        status    = 32'd0;

        repeat (5) @(posedge clk);
        aresetn = 1'b1;
        repeat (5) @(posedge clk);

        $display("=== tb_axil_regs start ===");

        // ---- 1. 写 MODE = 3，读回 ----
        axi_write(8'h04, 32'd3);
        axi_read (8'h04, got);
        check(got, 32'd3, "MODE");
        if (mode !== 3'd3) begin
            $display("FAIL: mode 输出 = %0d, expect 3", mode); errors = errors + 1;
        end else $display("PASS: mode 输出 = 3");

        // ---- 2. 写 THRESH = 0x64，读回 ----
        axi_write(8'h08, 32'h64);
        axi_read (8'h08, got);
        check(got, 32'h64, "THRESH");
        if (threshold !== 8'h64) begin
            $display("FAIL: threshold 输出 = %0d", threshold); errors = errors + 1;
        end else $display("PASS: threshold 输出 = 0x64");

        // ---- 3. 写 CTRL 打开滤波使能 ----
        axi_write(8'h00, 32'h1);
        axi_read (8'h00, got);
        check(got, 32'h1, "CTRL");
        if (filter_en !== 1'b1) begin
            $display("FAIL: filter_en 输出 = %0d", filter_en); errors = errors + 1;
        end else $display("PASS: filter_en 输出 = 1");

        // ---- 3b. 地址先到、数据后到（真机时序）----
        axi_write_split(8'h04, 32'd2, 3, 0);
        axi_read (8'h04, got);
        check(got, 32'd2, "MODE via split AW-then-W");
        if (mode !== 3'd2) begin
            $display("FAIL: mode after split write = %0d, expect 2", mode); errors = errors + 1;
        end else $display("PASS: mode after split write = 2");

        // ---- 3c. 数据先到、地址后到 ----
        axi_write_split(8'h00, 32'h0, 4, 1);
        axi_read (8'h00, got);
        check(got, 32'h0, "CTRL via split W-then-AW");
        if (filter_en !== 1'b0) begin
            $display("FAIL: filter_en after split write = %0d, expect 0", filter_en); errors = errors + 1;
        end else $display("PASS: filter_en after split write = 0");

        // ---- 4. 读 VERSION ----
        axi_read(8'h0C, got);
        check(got, 32'h0001_0000, "VERSION");

        // ---- 5. 读 FRAME_CNT / STATUS ----
        frame_cnt = 32'h0000_1234;
        status    = 32'h0000_00AA;
        axi_read(8'h10, got);
        check(got, 32'h0000_1234, "FRAME_CNT");
        axi_read(8'h14, got);
        check(got, 32'h0000_00AA, "STATUS");

        // ---- 6. 往只读寄存器写，必须不生效 ----
        axi_write(8'h0C, 32'hFFFF_FFFF);      // 试图改 VERSION
        axi_read (8'h0C, got);
        check(got, 32'h0001_0000, "VERSION after illegal write");

        // ---- 7. 非法地址读到标记值 ----
        axi_read(8'h3C, got);
        check(got, 32'hDEAD_BEEF, "illegal addr");

        sim_done = 1'b1;
        if (errors == 0)
            $display("RESULT: PASS  (AXI4-Lite register file works)");
        else
            $display("RESULT: FAIL  (%0d errors)", errors);

        $finish;
    end

    initial begin
        #100_000;
        if (sim_done !== 1'b1) $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule

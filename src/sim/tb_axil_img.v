// ============================================================================
// tb_axil_img.v —— 验证「图像上传通道」和「标框寄存器」
//
// 覆盖点：
//   1. AW / W 分两拍到达（回归 V1.1 的握手 bug）
//   2. 一次 IMG_DATA 写 → 缓冲区 4 个连续字节被正确写入
//   3. IMG_ADDR 自动 +4
//   4. 框坐标寄存器写入 → box_bus 打包正确
//   5. 写 0x70 → commit_tog 翻转
//   6. box_overlay 的边框命中逻辑
// ============================================================================
`timescale 1ns / 1ps

module tb_axil_img;

    reg         clk = 0;
    reg         rst_n = 0;
    always #5 clk = ~clk;      // 100MHz

    // ---- DUT: axil_regs ----
    reg  [7:0]  awaddr = 0, araddr = 0;
    reg         awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    reg  [31:0] wdata = 0;
    reg  [3:0]  wstrb = 4'hF;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    wire [2:0]  mode;
    wire [7:0]  threshold;
    wire        filter_en;
    wire        img_we;
    wire [16:0] img_addr;
    wire [7:0]  img_data;
    wire [383:0] box_bus;
    wire        commit_tog;

    axil_regs u_dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .mode(mode), .threshold(threshold), .filter_en(filter_en),
        .frame_cnt(32'h0000_1234), .status(32'h0),
        .img_we(img_we), .img_addr(img_addr), .img_data(img_data),
        .box_bus(box_bus), .commit_tog(commit_tog)
    );

    // ---- img_buf：把写进去的字节存起来，方便回读检查 ----
    reg [7:0] shadow [0:76799];
    integer k;
    initial for (k = 0; k < 76800; k = k + 1) shadow[k] = 8'h00;

    always @(posedge clk) if (img_we) shadow[img_addr] <= img_data;

    // ---- box_overlay ----
    reg  [15:0] px = 0, py = 0;
    wire        hit;

    box_overlay #(.NB(8), .TH(3), .CW(11), .W(384)) u_ov (
        .bus(box_bus), .x(px), .y(py), .hit(hit)
    );

    // ---- AXI 写任务：AW 和 W 故意分两拍 ----
    task axi_write_split(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk); #1;
            awaddr = addr; awvalid = 1; wvalid = 0;
            @(posedge clk); #1;
            awvalid = 0;                       // 地址先走
            @(posedge clk); #1;
            wdata = data; wvalid = 1;          // 数据下一拍才来
            @(posedge clk); #1;
            wvalid = 0;
            wait (bvalid == 1'b1);
            @(posedge clk);
        end
    endtask

    // ---- AXI 读任务（回读 IMG_ADDR）----
    reg [31:0] rd_val;
    task axi_read(input [7:0] addr, output [31:0] data);
        begin
            @(posedge clk); #1;
            araddr = addr; arvalid = 1;
            @(posedge clk); #1;
            arvalid = 0;
            wait (rvalid == 1'b1);
            data = rdata;
            @(posedge clk);
        end
    endtask

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("  [FAIL] %0s", msg);
            end
            else $display("  [ ok ] %0s", msg);
        end
    endtask

    reg [31:0] bx0_word, bx1_word;

    initial begin
        $dumpfile("tb_axil_img.vcd");
        $dumpvars(0, tb_axil_img);

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        $display("=== 1. 图像上传：写 1 个字 → 缓冲区 4 字节 ===");
        axi_write_split(8'h20, 32'd0);              // IMG_ADDR = 0
        axi_write_split(8'h24, 32'h44332211);       // 写 4 字节
        repeat (4) @(posedge clk);
        $display("  buf[0..3] = %02h %02h %02h %02h", shadow[0], shadow[1], shadow[2], shadow[3]);
        check(shadow[0] === 8'h11, "buf[0]==0x11");
        check(shadow[1] === 8'h22, "buf[1]==0x22");
        check(shadow[2] === 8'h33, "buf[2]==0x33");
        check(shadow[3] === 8'h44, "buf[3]==0x44");
        axi_read(8'h20, rd_val);
        $display("  回读 IMG_ADDR = %0d", rd_val);
        check(rd_val === 32'd4,   "IMG_ADDR auto +4");

        $display("=== 2. 连续写第二个字 ===");
        axi_write_split(8'h24, 32'h88776655);
        repeat (4) @(posedge clk);
        $display("  buf[4..7] = %02h %02h %02h %02h", shadow[4], shadow[5], shadow[6], shadow[7]);
        check(shadow[4] === 8'h55, "buf[4]==0x55");
        check(shadow[7] === 8'h88, "buf[7]==0x88");
        axi_read(8'h20, rd_val);
        check(rd_val === 32'd8,   "IMG_ADDR auto +8");

        $display("=== 3. 框坐标寄存器 ===");
        // box0: base 0x2C → +0 = (x0=100,y0=50), +4 = (x1=200,y1=150)
        bx0_word = {5'd0, 11'd50, 5'd0, 11'd100};    // {y0, x0}
        bx1_word = {5'd0, 11'd150, 5'd0, 11'd200};   // {y1, x1}
        axi_write_split(8'h2C, bx0_word);
        axi_write_split(8'h30, bx1_word);
        axi_write_split(8'h6C, 32'd1);               // box_cnt = 1
        axi_write_split(8'h70, 32'h1);               // overlay_en=1, commit 翻转
        repeat (3) @(posedge clk);

        check(commit_tog === 1'b1, "commit_tog toggled once");
        $display("  box_bus[0]=%b  cnt=%0d  x0=%0d y0=%0d x1=%0d y1=%0d",
                 box_bus[0], box_bus[4:1],
                 box_bus[8+21+0 +: 11],  // 先占位，下面用真实位段校验
                 box_bus[8+32 +: 11],
                 box_bus[8+0 +: 11],
                 box_bus[8+11 +: 11]);
        check(box_bus[0] === 1'b1, "box_bus[0] overlay_en=1");
        check(box_bus[4:1] === 4'd1, "box_bus[4:1] cnt=1");
        check(box_bus[8 + 0  +: 11] === 11'd100, "box0 x0=100");
        check(box_bus[8 + 11 +: 11] === 11'd50,  "box0 y0=50");
        check(box_bus[8 + 22 +: 11] === 11'd200, "box0 x1=200");
        check(box_bus[8 + 33 +: 11] === 11'd150, "box0 y1=150");

        $display("=== 4. box_overlay 命中判断 ===");
        px = 16'd150; py = 16'd50;   #1 check(hit === 1'b1, "(150,50) top edge hit");
        px = 16'd100; py = 16'd100;  #1 check(hit === 1'b1, "(100,100) left edge hit");
        px = 16'd150; py = 16'd100;  #1 check(hit === 1'b0, "(150,100) inside, no edge");
        px = 16'd99;  py = 16'd100;  #1 check(hit === 1'b0, "(99,100) outside");
        px = 16'd150; py = 16'd151;  #1 check(hit === 1'b0, "(150,151) below box");
        px = 16'd150; py = 16'd149;  #1 check(hit === 1'b1, "(150,149) bottom edge hit");

        $display("=== 5. 关闭总开关 ===");
        axi_write_split(8'h70, 32'h0);
        repeat (2) @(posedge clk);
        px = 16'd150; py = 16'd50; #1 check(hit === 1'b0, "overlay_en=0, no box");

        $display("");
        if (errors == 0) $display("RESULT: PASS (全部检查通过)");
        else             $display("RESULT: FAIL (%0d 项失败)", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("RESULT: FAIL (超时)");
        $finish;
    end

endmodule

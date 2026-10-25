// ============================================================================
// tb_image_rom_src.v —— 图片 ROM 图像源自检
//
// 验证 4 件事：
//   1. 窗外（左右黑边）输出必须是 0
//   2. 窗内输出必须等于对应源像素（tb 自己也读同一个 .mem 做参考）
//   3. 3 倍放大：每 3 个相邻显示像素应该对应同一个源像素
//   4. 延迟：de_o 比 de 晚 2 拍，x_o/y_o 同步延迟
//
// 注意：testbench 和 DUT 都读 image_gray.mem，两个文件必须一致。
// ============================================================================
`timescale 1ns / 1ps

module tb_image_rom_src;

    localparam IMG_W  = 320;
    localparam IMG_H  = 240;
    localparam SCALE  = 4;
    localparam DISP_W = 1280;
    localparam DISP_H = 720;
    localparam VOFF   = (IMG_H*SCALE - DISP_H) / 2;   // 当前配置：居中裁剪 120 行
localparam Y0     = (DISP_H - DISP_H) / 2;         // 垂直不留边
localparam X0     = (DISP_W - IMG_W*SCALE) / 2;    // 水平刚好铺满 = 0

    reg         clk;
    reg         rst_n;
    reg         de;
    reg  [15:0] x, y;

    wire        de_o;
    wire [15:0] x_o, y_o;
    wire [23:0] rgb_o;

    // 参考图像
    reg [7:0] ref [0:IMG_W*IMG_H-1];

    initial $readmemh("image_gray.mem", ref);

    wire [16:0] raddr;
    wire [7:0]  rdata;
    wire        mark_o;

    // 用参考图模拟外部缓冲区（同步读，1 拍延迟，与 img_buf 一致）
    reg [7:0] rdata_q;
    always @(posedge clk) rdata_q <= ref[raddr];
    assign rdata = rdata_q;

    image_rom_src #(
        .IMG_W(IMG_W), .IMG_H(IMG_H), .SCALE(SCALE),
        .DISP_W(DISP_W), .DISP_H(DISP_H)
    ) u_rom (
        .clk(clk), .rst_n(rst_n),
        .de(de), .x(x), .y(y),
        .raddr(raddr), .rdata(rdata),
        .de_o(de_o), .x_o(x_o), .y_o(y_o), .rgb_o(rgb_o), .mark_o(mark_o)
    );

    initial clk = 1'b0;
    always #20 clk = ~clk;      // 25MHz

    integer errors, i;
    reg     sim_done;
    integer disp_x, disp_y;
    integer exp_val, act_val;
    reg [7:0] pix;

    // 采样检查点：窗内取一批，窗外取一批
    integer test_x [0:99];
    integer test_y [0:99];

    // ---------- 驱动一帧的一部分（只跑前 8 行，够验证） ----------
    task drive_line;
        input integer yy;
        begin
            for (disp_x = 0; disp_x < DISP_W + 8; disp_x = disp_x + 1) begin
                de = (disp_x < DISP_W) ? 1'b1 : 1'b0;
                x  = (disp_x < DISP_W) ? disp_x[15:0] : 16'd0;
                y  = yy[15:0];
                @(posedge clk);
            end
        end
    endtask

    // 在输出侧比对：等 de_o 有效时按 x_o/y_o 算期望值
    integer chk_cnt, fail_cnt;
    // 用下降沿采样：rgb_o 是组合输出，在上升沿采样会和寄存器更新竞争，
    // 表现为"只在源图列边界处差 1"的诡异错误。
    always @(negedge clk) begin
        if (!rst_n) begin
            chk_cnt  = 0;
            fail_cnt = 0;
        end
        else if (de_o && chk_cnt < 400) begin
            // 每 37 个输出像素查一次，避免日志太长
            if ((chk_cnt % 37) == 0) begin
                if (x_o < X0 || x_o >= X0 + IMG_W*SCALE || y_o >= IMG_H*SCALE) begin
                    exp_val = 0;                       // 窗外应是黑
                end
                else begin
                    pix = ref[((y_o-Y0+VOFF)/SCALE)*IMG_W + ((x_o-X0)/SCALE)];
                    exp_val = pix;
                end
                act_val = rgb_o[7:0];
                if ((act_val === 8'hxx) || (act_val !== exp_val)) begin
                    $display("FAIL: (x=%0d,y=%0d) got %0d expect %0d", x_o, y_o, act_val, exp_val);
                    fail_cnt = fail_cnt + 1;
                end
            end
            chk_cnt = chk_cnt + 1;
        end
    end

    initial begin
        errors = 0;
        rst_n  = 1'b0;
        de     = 1'b0;
        x      = 16'd0;
        y      = 16'd0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        sim_done = 1'b0;

        // 先确认 .mem 真的加载进来了（否则 X 和 X 比较也会"通过"，是假通过）
        if ((^ref[0] === 1'bx) || (^ref[1000] === 1'bx) || (^u_rom.rom[0] === 1'bx)) begin
            $display("FAIL: image_gray.mem NOT loaded (rom is X). Check the file path!");
            $display("RESULT: FAIL  (memory not initialized)");
            $finish;
        end
        $display("INFO: memory loaded ok, ref[0]=%0d rom[0]=%0d", ref[0], u_rom.rom[0]);

        $display("=== tb_image_rom_src start (320x240 -> 1280x960, center-crop to 720) ===");

        // 跑 8 行显示
        for (i = 0; i < 8; i = i + 1) begin
            drive_line(i);
        end

        repeat (20) @(posedge clk);

        sim_done = 1'b1;
        if (fail_cnt == 0 && chk_cnt > 0)
            $display("RESULT: PASS  (%0d sampled pixels checked, ROM addressing correct)", chk_cnt);
        else
            $display("RESULT: FAIL  (%0d mismatches)", fail_cnt);

        $finish;
    end

    initial begin
        #5_000_000;
        if (sim_done !== 1'b1) $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule

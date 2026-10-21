// ============================================================================
// img_filter_3x3.v —— 3x3 卷积图像滤波核（本项目的核心 IP）  V1.1
//
// 【V1.1 改动】
//   为了在 75MHz（1280x720@60）下满足时序，把算术流水线加深为 3 级：
//     S4 寄存九抽头 → S5 加法树结果寄存 → S6 乘法/移位/绝对值结果寄存 → S7 输出
//   V1.0 里加法树+乘法+模式选择挤在一拍，实测 WNS = -0.14ns（差一点点），
//   加深之后每段都只有 3~5ns，裕量充足。
//   代价是总延迟从 5 拍变成 7 拍（对图像显示没有任何影响）。
//
//   顺带修掉一个 DRC 警告：addr_s1 原来带异步复位，却被直接连到 BRAM 地址端口，
//   会触发 REQP-1840（异步复位可能损坏存储器内容）。改成不带复位。
//
// 【功能】输入一串像素（每拍一个，带 de/x/y），输出同样一串像素，
//   每个输出像素 = 以该像素为中心的 3x3 邻域按卷积核加权的结果。
//
//   支持 4 种模式（mode）：
//     0 = 灰度直通（只做 RGB->Y，用于对照）
//     1 = 均值模糊  （3x3 全 1 核 /9）
//     2 = 高斯模糊  （[1 2 1; 2 4 2; 1 2 1] /16）
//     3 = Sobel 边缘（|Gx| + |Gy|）
//
// 【为什么必须硬件做】
//   每个像素要读 9 个数、做 9 次乘加，1280x720@60 = 5500 万像素/秒，
//   软件要 5 亿次乘加/秒，ARM A9 单核做不完；而 PL 每拍算一个像素，
//   75MHz 就够 720p60，且完全并行、延迟固定。
//
// 【架构】
//   in → RGB转灰度 → 行缓存BRAM(y-1,y-2) → 三行对齐 → 行内移位(左1,左2)
//        → 九抽头寄存 → 加法树 → 乘/移/绝对值 → mode 选择 → 输出寄存
//
// 【边界处理】用"边缘复制（clamp）"，画面边缘不会出现黑边。
//
// 【延迟与吞吐】每拍 1 像素（无停顿）；延迟约 7 拍 + 1 行。
//   窗口中心比输出坐标偏 1 像素（x-1, y-1），整幅图右/下移 1 像素，视觉不可见。
// ============================================================================
`timescale 1ns / 1ps

module img_filter_3x3 #(
    parameter WIDTH  = 640,     // 图像宽度（行缓存按列寻址）
    parameter DEPTH  = 1024     // 行缓存深度，必须 >= 最大 x 值且为 2 的幂
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [2:0]  mode,        // 滤波模式

    // ---- 视频输入 ----
    input  wire        in_de,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire [23:0] in_rgb,

    // ---- 视频输出（比输入晚约 7 拍 + 1 行） ----
    output reg         out_de,
    output reg  [15:0] out_x,
    output reg  [15:0] out_y,
    output reg  [23:0] out_rgb
);

    // ==================================================================
    // S1：RGB 转灰度  Y = (77R + 150G + 29B) >> 8（BT.601 整数近似）
    // ==================================================================
    wire [15:0] gray_sum = in_rgb[23:16] * 16'd77
                         + in_rgb[15:8]  * 16'd150
                         + in_rgb[7:0]   * 16'd29;
    wire [7:0]  gray_in  = gray_sum[15:8];

    reg  [7:0]  gray_s1;
    reg  [15:0] x_s1, y_s1;
    reg         de_s1;

    // 读地址：故意不带复位（它直连 BRAM 地址口，带异步复位会触发 DRC 警告）
    reg  [9:0]  addr_s1;

    always @(posedge clk) begin
        addr_s1 <= in_x[9:0];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_s1 <= 8'd0;
            x_s1    <= 16'd0;
            y_s1    <= 16'd0;
            de_s1   <= 1'b0;
        end
        else begin
            gray_s1 <= in_de ? gray_in : 8'd0;
            x_s1    <= in_x;
            y_s1    <= in_y;
            de_s1   <= in_de;
        end
    end

    // ==================================================================
    // S2：两条行缓存（lb0 = 第 y-1 行，lb1 = 第 y-2 行）
    //   每来一个有效像素：读出同列的两行旧值，然后把 y-1 搬进 lb1、当前行写进 lb0
    //   地址用 x，所以消隐期完全不影响对齐
    // ==================================================================
    reg [7:0] lb0 [0:DEPTH-1];
    reg [7:0] lb1 [0:DEPTH-1];

    reg [7:0] a0, a1;

    always @(posedge clk) begin
        a0 <= lb0[addr_s1];
        a1 <= lb1[addr_s1];
        if (de_s1) begin
            lb0[addr_s1] <= gray_s1;          // 当前行写入 lb0
            lb1[addr_s1] <= lb0[addr_s1];     // 原 y-1 行旧值挪进 lb1
        end
    end

    // 行缓存读出比 gray_s1 晚一拍，所以当前行也要再延一拍，否则三行列号错开
    reg [7:0]  gray_s2;
    reg [15:0] x_sb, y_sb, x_sb2, y_sb2;
    reg        de_sb, de_sb2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_s2 <= 8'd0;
            x_sb <= 16'd0; y_sb <= 16'd0; de_sb <= 1'b0;
            x_sb2 <= 16'd0; y_sb2 <= 16'd0; de_sb2 <= 1'b0;
        end
        else begin
            gray_s2 <= gray_s1;
            x_sb    <= x_s1;
            y_sb    <= y_s1;
            de_sb   <= de_s1;
            x_sb2   <= x_sb;
            y_sb2   <= y_sb;
            de_sb2  <= de_sb;
        end
    end

    // 三行数据对齐到同一拍
    reg [7:0]  row_cur, row_m1, row_m2;
    reg [15:0] x_s2, y_s2;
    reg        de_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_cur <= 8'd0; row_m1 <= 8'd0; row_m2 <= 8'd0;
            x_s2 <= 16'd0; y_s2 <= 16'd0; de_s2 <= 1'b0;
        end
        else begin
            row_cur <= gray_s2;
            row_m1  <= a0;
            row_m2  <= a1;
            x_s2    <= x_sb2;
            y_s2    <= y_sb2;
            de_s2   <= de_sb2;
        end
    end

    // 垂直方向边界复制
    wire [7:0] row_mid = (y_s2 >= 16'd1) ? row_m1 : row_cur;
    wire [7:0] row_top = (y_s2 >= 16'd2) ? row_m2 : row_mid;

    // ==================================================================
    // S3：行内移位，产生左 1、左 2 抽头；行首把抽头预置成第一个像素
    // ==================================================================
    reg [7:0] c_a, c_b;   // 当前行：左1、左2
    reg [7:0] m_a, m_b;   // y-1 行
    reg [7:0] t_a, t_b;   // y-2 行

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_a <= 8'd0; c_b <= 8'd0;
            m_a <= 8'd0; m_b <= 8'd0;
            t_a <= 8'd0; t_b <= 8'd0;
        end
        else begin
            c_a <= row_cur;  c_b <= c_a;
            m_a <= row_mid;  m_b <= m_a;
            t_a <= row_top;  t_b <= t_a;

            if (x_s2 == 16'd0) begin
                c_b <= row_cur;
                m_b <= row_mid;
                t_b <= row_top;
            end
        end
    end

    // ---- 九抽头（列：左=x-2，中=x-1，右=x；行：上=y-2，中=y-1，下=y） ----
    wire [7:0] p00 = t_b,   p01 = t_a,   p02 = row_top;
    wire [7:0] p10 = m_b,   p11 = m_a,   p12 = row_mid;
    wire [7:0] p20 = c_b,   p21 = c_a,   p22 = row_cur;

    // ==================================================================
    // S4：寄存九抽头（打断"移位寄存器 → 加法树"的长组合路径）
    // ==================================================================
    reg [7:0]  w00, w01, w02, w10, w11, w12, w20, w21, w22;
    reg [15:0] x_s3, y_s3;
    reg        de_s3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w00<=8'd0; w01<=8'd0; w02<=8'd0;
            w10<=8'd0; w11<=8'd0; w12<=8'd0;
            w20<=8'd0; w21<=8'd0; w22<=8'd0;
            x_s3<=16'd0; y_s3<=16'd0; de_s3<=1'b0;
        end
        else begin
            w00<=p00; w01<=p01; w02<=p02;
            w10<=p10; w11<=p11; w12<=p12;
            w20<=p20; w21<=p21; w22<=p22;
            x_s3<=x_s2; y_s3<=y_s2; de_s3<=de_s2;
        end
    end

    // ==================================================================
    // S5：加法树（只有加法，寄存结果）
    // ==================================================================
    wire [11:0] sum9_w = w00 + w01 + w02 + w10 + w11 + w12 + w20 + w21 + w22;

    wire [11:0] gsum_w = w00 + {w01,1'b0} + w02
                       + {w10,1'b0} + {w11,2'b00} + {w12,1'b0}
                       + w20 + {w21,1'b0} + w22;

    wire [11:0] sor_w = w02 + {w12,1'b0} + w22;   // Sobel 右列
    wire [11:0] sol_w = w00 + {w10,1'b0} + w20;   // Sobel 左列
    wire [11:0] sod_w = w20 + {w21,1'b0} + w22;   // Sobel 下行
    wire [11:0] sou_w = w00 + {w01,1'b0} + w02;   // Sobel 上行

    reg [11:0] sum9_r, gsum_r, sor_r, sol_r, sod_r, sou_r;
    reg [7:0]  gray_c;          // 窗口中心像素，必须和加法树同拍寄存，
                                // 否则到 S6 时 w11 已经又往前走了两列（踩过这个坑）
    reg [15:0] x_s4, y_s4;
    reg        de_s4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum9_r<=12'd0; gsum_r<=12'd0;
            sor_r<=12'd0; sol_r<=12'd0; sod_r<=12'd0; sou_r<=12'd0;
            gray_c<=8'd0;
            x_s4<=16'd0; y_s4<=16'd0; de_s4<=1'b0;
        end
        else begin
            sum9_r<=sum9_w; gsum_r<=gsum_w;
            sor_r<=sor_w; sol_r<=sol_w; sod_r<=sod_w; sou_r<=sou_w;
            gray_c<=w11;
            x_s4<=x_s3; y_s4<=y_s3; de_s4<=de_s3;
        end
    end

    // ==================================================================
    // S6：乘法 / 移位 / 绝对值（每种模式一个结果，寄存）
    // ==================================================================
    // ---- 均值：sum9 * 57 >> 9（57/512 ≈ 1/9）----
    //   注意：V1.1 原来写 sum9_r * 18'd57，行为仿真正确，但综合后
    //   netlist 仿真里 mode 1 全变 0（DSP48 推断把结果吃掉了）。
    //   改成纯移位加法（57 = 32+16+8+1），不依赖乘法器推断，行为完全确定。
    wire [17:0] s9x   = {6'd0, sum9_r};                       // 18 位无符号
    wire [17:0] m57   = (s9x << 5) + (s9x << 4) + (s9x << 3) + s9x;
    wire [7:0]  px_mean = m57[16:9];
    wire [7:0]  px_gauss = gsum_r[11:4];             // /16

    wire [12:0] gx = {1'b0, sor_r} - {1'b0, sol_r};
    wire [12:0] gy = {1'b0, sod_r} - {1'b0, sou_r};
    wire [12:0] gx_abs = gx[12] ? (~gx + 13'd1) : gx;
    wire [12:0] gy_abs = gy[12] ? (~gy + 13'd1) : gy;
    wire [12:0] mag    = gx_abs + gy_abs;
    wire [7:0]  px_sobel = (mag > 13'd255) ? 8'd255 : mag[7:0];

    reg [7:0]  r_gray, r_mean, r_gauss, r_sobel;
    reg [15:0] x_s5, y_s5;
    reg        de_s5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_gray<=8'd0; r_mean<=8'd0; r_gauss<=8'd0; r_sobel<=8'd0;
            x_s5<=16'd0; y_s5<=16'd0; de_s5<=1'b0;
        end
        else begin
            r_gray <= gray_c;       // 灰度 = 窗口中心（已在 S5 同拍寄存）
            r_mean <= px_mean;
            r_gauss<= px_gauss;
            r_sobel<= px_sobel;
            x_s5<=x_s4; y_s5<=y_s4; de_s5<=de_s4;
        end
    end

    // ==================================================================
    // S7：模式选择 + 输出寄存
    //   输出坐标比输入偏 (1,1)，因为窗口中心在 (x-1, y-1)
    // ==================================================================
    reg [7:0] px_out;
    always @(*) begin
        case (mode)
            3'd0: px_out = r_gray;
            3'd1: px_out = r_mean;
            3'd2: px_out = r_gauss;
            3'd3: px_out = r_sobel;
            default: px_out = r_gray;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_de  <= 1'b0;
            out_x   <= 16'd0;
            out_y   <= 16'd0;
            out_rgb <= 24'd0;
        end
        else begin
            out_de  <= de_s5;
            out_x   <= x_s5 - 16'd1;
            out_y   <= y_s5 - 16'd1;
            out_rgb <= {px_out, px_out, px_out};
        end
    end

endmodule

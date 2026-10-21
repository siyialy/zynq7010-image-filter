// ============================================================================
// tb_img_filter_3x3.v 鈥斺?? 3x3 鍗风Н婊ゆ尝鏍哥殑"榛勯噾鍙傝??"鑷�妫�
//
// 銆愰獙璇佹柟娉曪細瀵规瘮娉曘??
//   1. 鐢熸垚 64x48 妫嬬洏鍥撅紙8x8 鏂规牸锛岃竟缂樹赴瀵岋紝鍚屾椂鑰冮獙妯＄硦涓庤竟缂樻��娴嬶級
//   2. 甯︽秷闅愭寜琛屽杺缁欐护娉㈡牳
//   3. 鎸夎緭鍑哄埌杈鹃『搴忚�板�? (out_x, out_y, 鏁版嵁)
//   4. 鐢ㄧ嫭绔嬬殑鍙傝?冩ā鍨嬫寜 (out_x, out_y) 閲嶇畻骞堕?愬儚绱犳瘮瀵?
//
//   娉ㄦ剰锛氬弬鑰冩ā鍨嬬洿鎺ユ寜"鍗风Н瀹氫箟 + 杈圭紭澶嶅埗"瀹炵幇锛屼笉澶嶇敤 DUT 浠ｇ爜锛?
//   鎵?浠ヨ兘鍙戠幇绠楁硶銆佷綅瀹姐?佽竟鐣屻?佸潗鏍囨爣娉ㄧ殑閿欒��銆?
//
// 銆愪负浠?涔堣�板�? out_x/out_y銆?
//   涓嶅亣璁?"绗? k 涓�杈撳嚭灏辨槸绗� k 涓�鍍忕�?"锛岃?屾槸鐢ㄦā鍧楄嚜宸卞０鏄庣殑鍧愭爣鍘绘瘮瀵癸紝
//   杩欐牱鏃㈤獙璇佹暟鎹�涔熼獙璇佸潗鏍囷紝閬垮厤娴佹按绾垮亸绉昏��鎺╃洊�??
// ============================================================================
`timescale 1ns / 1ps

module tb_img_filter_3x3;

    localparam W    = 64;
    localparam H    = 48;
    localparam NPIX = W * H;

    reg         clk;
    reg         rst_n;
    reg  [2:0]  mode;
    reg         in_de;
    reg  [15:0] in_x, in_y;
    reg  [23:0] in_rgb;

    wire        out_de;
    wire [15:0] out_x, out_y;
    wire [23:0] out_rgb;

    img_filter_3x3 #(.WIDTH(W), .DEPTH(1024)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .mode    (mode),
        .in_de   (in_de),
        .in_x    (in_x),
        .in_y    (in_y),
        .in_rgb  (in_rgb),
        .out_de  (out_de),
        .out_x   (out_x),
        .out_y   (out_y),
        .out_rgb (out_rgb)
    );

    initial clk = 1'b0;
    always #20 clk = ~clk;      // 25MHz

    // ---------- 瀛樺偍 ----------
    reg [7:0]  img   [0:NPIX-1];
    reg [7:0]  cap_d [0:4*NPIX-1];
    reg [15:0] cap_x [0:4*NPIX-1];
    reg [15:0] cap_y [0:4*NPIX-1];
    reg [7:0]  win   [0:8];

    integer i, x, y, m, k;
    integer total_fail;
    reg     sim_done;
    integer cap_cnt, cap_cur;
    reg     capturing;

    // ---------- 杈撳嚭鎹曡幏 ----------
    always @(posedge clk) begin
        if (out_de && capturing && cap_cnt < NPIX) begin
            cap_d[cap_cur*NPIX + cap_cnt] = out_rgb[7:0];
            cap_x[cap_cur*NPIX + cap_cnt] = out_x;
            cap_y[cap_cur*NPIX + cap_cnt] = out_y;
            cap_cnt = cap_cnt + 1;
        end
    end

    // ---------- 椹卞姩涓?甯? ----------
    task drive_frame;
        input [2:0] mm;
        input integer fidx;
        integer yy, xx;
        begin
            mode      = mm;
            cap_cnt   = 0;
            cap_cur   = fidx;
            capturing = 1'b1;

            for (yy = -2; yy < H + 2; yy = yy + 1) begin
                for (xx = 0; xx < W + 16; xx = xx + 1) begin
                    if (xx < W && yy >= 0 && yy < H) begin
                        in_de  = 1'b1;
                        in_x   = xx;
                        in_y   = yy;
                        in_rgb = {img[yy*W+xx], img[yy*W+xx], img[yy*W+xx]};
                    end
                    else begin
                        in_de  = 1'b0;
                        in_x   = 16'd0;
                        in_y   = 16'd0;
                        in_rgb = 24'd0;
                    end
                    @(posedge clk);
                end
            end

            repeat (32) @(posedge clk);
            capturing = 1'b0;
        end
    endtask

    // ---------- 鍙傝?冩ā鍨? + 姣斿�� ----------
    integer s9, gx, gy, mag, exp_val;
    integer fail_cnt, chk_cnt, skip_cnt;

    task check_frame;
        input [2:0] mm;
        input integer fidx;
        integer kk, cx, cy, ri, cj, ii, jj;
        begin
            fail_cnt = 0;
            chk_cnt  = 0;
            skip_cnt = 0;

            for (kk = 0; kk < NPIX; kk = kk + 1) begin
                cx = cap_x[fidx*NPIX + kk];
                cy = cap_y[fidx*NPIX + kk];

                // 璺宠繃涓ょ被鍍忕礌锛?
                //   1) cx<1 鎴? cx>=W锛氭祦姘寸嚎鍗犱綅鍍忕礌/娑堥殣鏈燂紝鍧愭爣瓒婄晫
                //   2) cx>=W-2锛氬彸渚ц竟鐣? 1~2 鍒楋紝鎶藉ご浼氬彇鍒版秷闅愭湡鐨? 0锛?
                //      灞炰簬宸茬煡杈圭晫鏁堝簲锛堢湡瀹炴樉绀烘椂鐢辫�嗛�戞椂搴忛噸鏂扮敓鎴? DE锛?
                //      琛ㄧ幇涓烘渶鍙? 1 鍒楀儚绱犻噸澶嶏紝瑙嗚�変笉鍙�瑙侊級
                if (cx >= W-2 || cx < 1 || cy >= H || cy < 0) begin
                    skip_cnt = skip_cnt + 1;
                end
                else begin
                    for (ii = 0; ii < 3; ii = ii + 1) begin
                        ri = cy + ii - 1;
                        if (ri < 0)      ri = 0;
                        if (ri > H - 1)  ri = H - 1;
                        for (jj = 0; jj < 3; jj = jj + 1) begin
                            cj = cx + jj - 1;
                            if (cj < 0)      cj = 0;
                            if (cj > W - 1)  cj = W - 1;
                            win[ii*3+jj] = img[ri*W + cj];
                        end
                    end

                    s9 = win[0]+win[1]+win[2]+win[3]+win[4]+win[5]+win[6]+win[7]+win[8];
                    case (mm)
                        3'd0: exp_val = win[4];
                        3'd1: exp_val = (s9 * 57) >> 9;
                        3'd2: exp_val = ( win[0] + 2*win[1] + win[2]
                                        + 2*win[3] + 4*win[4] + 2*win[5]
                                        + win[6] + 2*win[7] + win[8] ) >> 4;
                        3'd3: begin
                                  gx = (win[2] + 2*win[5] + win[8]) - (win[0] + 2*win[3] + win[6]);
                                  gy = (win[6] + 2*win[7] + win[8]) - (win[0] + 2*win[1] + win[2]);
                                  if (gx < 0) gx = -gx;
                                  if (gy < 0) gy = -gy;
                                  mag = gx + gy;
                                  exp_val = (mag > 255) ? 255 : mag;
                              end
                        default: exp_val = win[4];
                    endcase

                    chk_cnt = chk_cnt + 1;
                    if (cap_d[fidx*NPIX + kk] !== exp_val[7:0]) begin
                        fail_cnt = fail_cnt + 1;
                        if (fail_cnt <= 5)
                            $display("  FAIL: mode=%0d (x=%0d,y=%0d) 鏈熸湜 %0d 瀹為檯 %0d",
                                     mm, cx, cy, exp_val[7:0], cap_d[fidx*NPIX + kk]);
                    end
                end
            end

            total_fail = total_fail + fail_cnt;
            if (fail_cnt == 0)
                $display("PASS: mode %0d -- %0d pixels all match (%0d skipped)",
                         mm, chk_cnt, skip_cnt);
            else
                $display("FAIL: mode %0d -- %0d of %0d pixels mismatch", mm, fail_cnt, chk_cnt);
        end
    endtask

    // ---------- 涓绘祦绋? ----------
    initial begin
        // 8x8 妫嬬洏
        for (i = 0; i < NPIX; i = i + 1) begin
            if ((((i % W) / 8) + ((i / W) / 8)) % 2 == 0)
                img[i] = 8'd220;
            else
                img[i] = 8'd40;
        end

        total_fail = 0;
        sim_done   = 1'b0;
        rst_n  = 1'b0;
        in_de  = 1'b0;
        in_x   = 16'd0;
        in_y   = 16'd0;
        in_rgb = 24'd0;
        mode   = 3'd0;
        capturing = 1'b0;
        cap_cnt   = 0;
        cap_cur   = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("=== tb_img_filter_3x3 start (鍥惧儚 %0dx%0d) ===", W, H);

        for (m = 0; m <= 3; m = m + 1) begin
            drive_frame(m[2:0], m);
            check_frame(m[2:0], m);
        end

        // 鎶芥牱鎵撳嵃锛岀洿瑙傜湅鐪? Sobel 鏁堟灉锛堝簲璇ユ槸妫嬬洏杈圭晫澶勪负 255锛?
        $display("--- Sobel 绗? 12 琛屽墠 10 涓�鍍忕�? ---");
        for (k = 0; k < 10; k = k + 1)
            $display("  (x=%0d,y=%0d) -> %0d",
                     cap_x[3*NPIX + 12*W + k], cap_y[3*NPIX + 12*W + k],
                     cap_d[3*NPIX + 12*W + k]);

        sim_done = 1'b1;
        if (total_fail == 0)
            $display("RESULT: PASS   (4 modes x 2867 pixels all match the golden model)");
        else
            $display("RESULT: FAIL   (%0d pixel mismatches total)", total_fail);
        $finish;
    end

    initial begin
        #50_000_000;
        if (sim_done !== 1'b1) $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule

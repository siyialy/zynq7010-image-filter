// ============================================================================
// img_buf.v —— 可写入的图像缓冲区（PS 上传图片的落脚点）  V1.0
//
// 【为什么需要它】
//   原来的图像源是 image_rom_src 内部的一个 $readmemh 只读 ROM，
//   想换图必须重新综合（13 分钟）。现在改成真正的双端口 RAM：
//
//     A 口：像素时钟，显示通路读   （只读）
//     B 口：AXI 时钟，PS 写        （只写）
//
//   两个口独立时钟 —— Xilinx 会推断成真正的双端口 BRAM（TDP）。
//   换图变成"PS 通过 AXI 写 76800 字节"，秒级完成，不用重新综合。
//
// 【标注通道：用最高位表示"这里是病灶"】
//   缓冲区里每个字节的含义：
//     bit7 = 1  →  该像素是病灶标注，显示时渲染成红色（FF0000）
//     bit7 = 0  →  普通灰度，取 bit[6:0] 左移一位当 8 位灰度
//
//   这样 PS 只需要"写字"，不用额外的叠加寄存器、不用跨时钟域同步框坐标。
//   代价是显示灰度从 8 位降到 7 位（128 级），在这个应用里肉眼无差别。
//
// 【容量】
//   320 × 240 = 76800 字节
//   76800 × 8 bit = 614400 bit  →  约 17 个 BRAM36（60 个里占 17 个，可接受）
// ============================================================================
`timescale 1ns / 1ps

module img_buf #(
    parameter IMG_W    = 320,
    parameter IMG_H    = 240,
    parameter EXTRA_PIX = 0,    // v1.5: 32x60 soft-background thumbnail after main frame
    parameter MEM_FILE = "image_gray.mem"
)(
    // ---- A 口：显示读（像素时钟域）----
    input  wire        clk_pix,
    input  wire [16:0] addr_pix,
    output reg  [7:0]  data_pix,

    // ---- B 口：PS 写入（AXI 时钟域）----
    input  wire        clk_axi,
    input  wire        we,
    input  wire [16:0] addr_wr,
    input  wire [7:0]  data_wr
);

    localparam MAIN_PIX = IMG_W * IMG_H;
    localparam IMG_PIX = MAIN_PIX + EXTRA_PIX;

    (* ram_style = "block" *) reg [7:0] mem [0:IMG_PIX-1];

    // 上电时先装入一张默认图（PS 还没上传时屏幕上就有东西）
    integer init_i;
    initial begin
        $readmemh(MEM_FILE, mem, 0, MAIN_PIX-1);
        for (init_i = MAIN_PIX; init_i < IMG_PIX; init_i = init_i+1)
            mem[init_i] = 8'd64;
    end

    // A 口：同步读（1 拍延迟）
    always @(posedge clk_pix) begin
        if (addr_pix < IMG_PIX) data_pix <= mem[addr_pix];
        else                   data_pix <= 8'd0;
    end

    // B 口：同步写
    always @(posedge clk_axi) begin
        if (we && addr_wr < IMG_PIX) mem[addr_wr] <= data_wr;
    end

endmodule

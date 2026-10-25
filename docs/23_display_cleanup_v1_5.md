# v1.5：显示去噪、平滑缩放与柔化背景

## 为什么看起来分成三个区域

当前 HDMI 可见区为 1280×720。上传图片为 320×240，在 PL 等比放大 3 倍后是
960×720，因此左右各剩 `(1280-960)/2=160` 像素。旧版把这两块区域直接输出为黑色。
这是居中留边，不是三路画面，也不是 HDMI 把图片切坏。
旧 `system_top.v` 的“正好铺满屏幕”注释不准确，本次已修正。

用户选择保持比例，因此本轮保留中间图片大小、裁剪窗口及红框坐标，
把左右黑区替换成同一图片边缘的模糊镜像背景，没有横向拉伸或增加裁剪。
原有 PS 裁剪（256×256 原图上下各裁 32 行）未改变。

## 图像处理

噪点主要来自原图的高频颗粒，原先最近邻放大会把每个颗粒扩成可见像素块。
本轮只处理显示用图像：

1. RGB 转灰度后做 3×3 中值滤波，抑制孤立亮点和暗点。
2. 使用 5×5 整数双边滤波，平滑相近亮度并保护较强的边缘。
3. 256×192 到 320×240 的缩放由最近邻改为双线性插值。
4. 红框继续由 PL 在滤波之后叠加，不参与显示去噪，保持清晰。

检测仍使用原始 `pv_rgb`，显示降噪不会改变检测输入或阈值。
原图只有 256×256，降噪改善颗粒感，不会创造新的高清细节；微小纹理也可能变柔和。

## 柔化背景与边界对齐

- 主画面仍是 320×240（76800 字节）。
- 背景为 32×60，共 1920 字节：每侧 16 列，镜像边缘、模糊并降低对比度。
- 背景紧跟主画面存储，总缓冲区为 78720 字节，主画面地址和框寄存器协议不变。
- 左侧 x=0..159、右侧 x=1120..1279 读取背景；中间 x=160..1119 读取主画面。
- 修复图像源 `win1` 比 `x1/y1/de1` 多滞后一拍的问题，避免窗口边缘错位。
- 非图片窗口时不再生成负偏移对应的越界读地址；RAM 增加读写边界保护。

背景与主画面均使用 7 位灰度，bit7 始终为 0，避免被误解释为红色标记。
v1.5 ELF 必须配合 v1.5 bitstream，旧 bitstream 的 RAM 没有背景区域。

## 已完成的检查

- `tools/review_display.py`：真实 C 渲染器处理全部 24 张图片，检测分类和全部框坐标与 v1.4 完全一致；显示处理后的再次检测也一致。
- `tools/test_display.py`：常量亮度、孤立椒盐点抑制、强边缘保留、灰度斜坡插值、标注位安全检查通过。
- 原有分类、定位与坐标回归测试通过；Host GCC `-Wall -Wextra -Werror` 和 ARM Release `-O2` 编译通过。
- `tb_display_source.v`：3 倍留边、4 倍裁剪和3 倍柔化背景三种配置共 2764800 个可见像素逐点检查通过，包含 RGB、标注位、两侧边界和所有 RAM 地址。
- Vivado 构建在原工程的独立克隆中完成，旧工程和旧 bitstream 保留。

预览文件在 `build/display_review/`：

- `display_before_after.jpg`：第 2、9、12、18 张去噪前后比较。
- `sample_12_soft_background.jpg` / `sample_23_soft_background.jpg`：完整布局预览，不含红框。
- `source_sim.log`：逐像素显示源仿真 PASS 记录。
- `detection_v14.json` / `pest_v1_4.c`：本轮修改前的检测结果与算法备份。

## 构建与上板

```powershell
python tools/test_display.py
python tools/review_display.py
& './tools/build_pest_app.ps1' -Version 1_5
& 'D:/XILINX/Vivado/2018.3/bin/vivado.bat' -mode batch -source build/build_display_v15.tcl
# 关闭占用 COM7 的串口终端后下载，脚本会自动选用匹配的 v1.5 bitstream。
& './tools/verify_pest_board.ps1' -Version 1_5 -Sample 12
```

构建脚本会复制默认图片到新的综合目录，避免克隆工程的 `$readmemh` 路径丢失。
显示画面准备属于单次切图开销，整组 `s` 命令只测检测阶段，不包含去噪、背景生成和上传。

## 最终构建与板上结果

- 独立工程：`D:/fpga_build/display_v15_1792819987`。
- bitstream：`D:/fpga_build/bits/system_top_v1_5.bit`；ELF：`build/pest_review/img_filter_app_v1_5.elf`。
- 实现 WNS：`+0.292 ns`；LUT：2355（13.38%），寄存器：2128（6.05%），BRAM：24.5/60（40.83%）。
- 最终构建已补齐默认图片初始化文件；没有 `readmemh` 找不到文件的问题。仍存在继承的时钟分组名称警告，不将整份构建日志描述为零警告。
- JTAG 下载成功，串口确认 `pest detector v1.5 (clean display / soft background)` 和 AXI 链路正常。
- 板上 24 张分类结果仍为 `TP=12 TN=12 FP=0 FN=0`，检测阶段最长 `182000 us`。
- 最后停在第 12 张健康样本，0 个框；显示图和柔化背景已上传。
- 串口记录：`build/pest_review/board_uart_v1_5.txt`；构建记录：`build/display_review/system_build_final.log`。
- `build/display_review/manifest.json` 记录对应源文件、样本、ELF、bitstream 的 SHA256。

显示器最终观感需要用户现场核对；若显示彩条，按板上 KEY1 切到图片源。

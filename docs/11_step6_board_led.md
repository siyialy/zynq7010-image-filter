# 第 6 步：上板点灯工程（已生成 .bit，可直接下载）

> 资料到手后第一件事做完了：用**真实引脚**建工程、综合、实现、生成 bit 流，全部一次通过。

## 成果

| 项目 | 结果 |
|---|---|
| 综合 | 0 Errors / 0 Critical Warnings |
| 实现 | 完成，DRC 0 Errors |
| 时序 | **WNS = +14.556 ns**（时钟周期 20ns，裕量极大） |
| 资源 | LUT 106 / 17600（0.6%），FF 83 / 35200（0.24%），IOB 6 / 100 |
| bit 流 | `board/bitstream/board_top_led.bit`（约 2 MB） |

工程小到几乎不占资源，这是正常的——点灯本来就不需要逻辑。

## 用到的引脚（来自官方 XDC + 引脚总表）

| 信号 | 引脚 | 说明 |
|---|---|---|
| sys_clk | **U18** | 50MHz 单端时钟 |
| sys_rst_n | **N16** | PL 复位按键，低有效 |
| key[0] | **L14** | PL KEY0 |
| key[1] | **K16** | PL KEY1 |
| led[0] | **H15** | 底板 PL_LED0（高电平点亮） |
| led[1] | **L15** | 底板 PL_LED1 |

引脚文件：[constr/pin_led.xdc](../constr/pin_led.xdc)

## 板子上会看到什么

| 现象 | 说明什么 |
|---|---|
| LED0 以 1Hz 均匀闪烁 | **时钟通了**（50MHz 分频正确） |
| 按住 KEY1，LED0 闪得明显变快（4Hz） | **输入通了**（按键电平能读到） |
| 每按一次 KEY0，LED1 翻转一次；松手不连跳 | **消抖 + 单周期边沿检测正常** |
| 按 RESET（N16），两个灯立刻回到初始状态 | 复位正常 |

这四个现象一次把所有基础通路都验证了：时钟、复位、输入、输出、消抖。

## 怎么下载（插上下载器后）

1. 板子上电，`BOOT CFG` 两个开关拨到 **ON**（JTAG 模式）
2. 14 脚排线接板子 `JTAG` 座，下载器 USB 接电脑
3. Vivado → `Open Hardware Manager` → `Open Target` → `Auto Connect`
4. 看到 `xc7z010_1` 后，右键它 → **`Program Device`**
5. Bitstream file 选：`D:\FPGA比赛\board\bitstream\board_top_led.bit`
6. 点 **Program**，几秒钟后 LED 就该开始闪了

**注意**：这是"下载到 FPGA"，掉电就没了。以后要做成上电自动运行，需要烧 QSPI Flash（另说，暂时不用）。

## 踩到的坑：中文路径会让 Vivado 综合直接崩

第一次构建失败，日志结尾只有一句莫名其妙的话：

```
TclStackFree: incorrect freePtr. Call out of sequence?
```

没有任何可读的错误信息，状态是 `synth_design ERROR (0%)`。

**原因**：Vivado 2018.3 在 Windows 上处理**中文路径**（`D:\FPGA比赛\src\...`）时，综合阶段会崩。函数仿真不受影响（xsim 能正常读中文路径），只有综合/实现会出问题。

**解决办法**：构建前把源码复制到纯英文目录再建工程。这一步我已经写进 `build_led.tcl`：

```tcl
set stage_src "D:/fpga_build/led_src"   # 纯英文暂存目录
foreach f $rtl_files { file copy -force $f $stage_src }
```

**以后所有综合/实现工程都要这么干**。这个坑很值得写进报告的"踩坑清单"，也是技能包的好素材——它属于"工具链陷阱"，换块板子、换个题目同样会碰到。

## 复现命令

```powershell
cd D:\FPGA比赛
D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\build_led.tcl
```

约 3~5 分钟，最后打印：

```
TIMING: WNS = 14.556 ns
TIMING: OK (met)
BITSTREAM: D:/fpga_build/led_board/led_board.runs/impl_1/board_top_led.bit
=== BUILD DONE ===
```

## 顺便确认的 HDMI 方案（重要）

从官方 XDC 和底板原理图看清楚了：

```
set_property -dict {PACKAGE_PIN J20 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[2]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[1]}]
set_property -dict {PACKAGE_PIN G19 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[0]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD TMDS_33} [get_ports tmds_clk_p]
```

原理图里对应的差分对（含 N 侧）：

| 通道 | P 侧 | N 侧 | bank |
|---|---|---|---|
| D2 | J20 | H20 | 35 |
| D1 | K19 | J19 | 35 |
| D0 | G19 | G20 | 35 |
| CLK | J18 | H18 | 35 |

**结论：这块板子的 HDMI 是 PL 直接输出 TMDS 差分信号，没有 HDMI 发送芯片。**

这意味着我们必须自己实现：

1. **TMDS 8b/10b 编码器**（把 24bit RGB + 行场同步编成 3 路 10bit 串行码流）
2. **OSERDESE2 10:1 串行化**（125.875MHz 位时钟，5 倍像素时钟，DDR 模式）
3. **MMCM 双时钟**（25.175MHz 像素时钟 + 125.875MHz 位时钟）

这三件是 7 系列 FPGA 输出 HDMI 的标准做法，但**时序约束和 OSERDES 的 CLKDIV/CLK 复位顺序都比较细**，第一次写容易踩坑。正点原子的 HDMI 例程里有成熟实现，直接复用能省掉最容易出错的一环。

→ 所以还需要下载 `4_Source_Code` 里**名字含 HDMI 的例程**。

## 下一步

| 顺序 | 做什么 | 依赖 |
|---|---|---|
| 1 | 下载 bit 流，确认 LED 正常 | 下载器 + 电源（都有了） |
| 2 | 拿 HDMI 例程，复用 TMDS 编码器 | 需要下 `4_Source_Code` 的 HDMI 例程 |
| 3 | 把 `video_pipeline`（彩条+滤波）接到 HDMI 输出 | 第 2 步完成 |
| 4 | PS 端：AXI-Lite 寄存器 + 串口菜单 + 软件基线 | 第 3 步完成 |

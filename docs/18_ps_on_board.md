# 第 10 步：PS 端上板（串口菜单 + 帧率 + 软件基线）

> 这一步跑通后，你的作品就有"软硬件协同"的完整证据链：
> **ARM 通过 AXI 控制 FPGA 的滤波模式，并能在同一帧上跑软件基线算加速比。**

## 已经生成的东西

| 文件 | 说明 |
|---|---|
| `board/system/system_top.bit` | 完整系统 bit 流（PS + PL） |
| `board/system/system.hdf` | 硬件描述（SDK 用） |
| `board/system/img_filter_app.elf` | ARM 程序（已编译通过） |

构建记录：**WNS +0.656 ns**（时序收敛），LUT 1527/17600（8.68%），FF 1109。

## 系统架构

```
        ┌─────────────── Zynq PS (ARM) ───────────────┐
        │  UART0 @MIO14/15  ←→  串口菜单              │
        │  DDR3 512MB（MT41K128M16, 32bit, 533MHz）   │
        └───────────────────┬─────────────────────────┘
                            │ M_AXI_GP0（100MHz）
                    ┌───────▼────────┐
                    │ AXI Interconnect│
                    └───────┬────────┘
                    ┌───────▼────────┐
                    │   axil_regs    │  CTRL/MODE/THRESH/VERSION/
                    │  （寄存器组）   │  FRAME_CNT/STATUS
                    └───────┬────────┘
                            │ mode/threshold/filter_en（跨时钟域，每位打两拍）
                    ┌───────▼────────────────────────┐
                    │  video_pipeline（75MHz 像素域） │
                    │  照片/彩条 → 3×3 滤波 → HDMI    │
                    └───────┬────────────────────────┘
                            │ 帧起始脉冲（脉冲同步到 100MHz 域）
                    ┌───────▼────────┐
                    │ cdc_frame_cnt  │ → FRAME_CNT（PS 读来算帧率）
                    └────────────────┘
```

**跨时钟域处理**（这是"协同"的关键细节，答辩可以讲）：

| 信号 | 方向 | 方法 |
|---|---|---|
| mode / threshold / filter_en | AXI 100MHz → 像素 75MHz | 每位两级触发器同步（慢变配置） |
| 帧计数 | 像素 75MHz → AXI 100MHz | **脉冲同步 + 本地计数**（避免读到进位中间值） |

---

## 上板操作（第一次跑 PS）

### 1. 接线

| 线 | 接到 |
|---|---|
| 12V 电源 | DC 圆孔 |
| JTAG 排线 | 下载器 → 板子 `JTAG` |
| **USB 串口线** | 板子 **`USB UART`** 口（CH340）→ 电脑 |
| HDMI 线 | 板子 `HDMI OUT` → 显示器 |

`BOOT CFG` 两个拨码 **ON/ON**。

> ⚠️ 如果串口没输出，检查板上 CH340 附近的 **`PS_TX` / `PL_TX`** 丝印处：
> 有的板子有跳线/0Ω 电阻选择串口连 PS 还是 PL，**必须选 PS_TX**（我们用的是 PS UART0）。

### 2. 关掉 Vivado 的 Hardware Manager

因为 `run_app.tcl` 要独占硬件（JTAG）。在 Vivado 里点 `Hardware Manager` 右上角关闭，
或者直接关掉 Vivado。

### 3. 一键下载并运行

打开 PowerShell，执行：

```powershell
cd D:\FPGA比赛
D:\XILINX\SDK\2018.3\bin\xsct.bat build\run_app.tcl
```

它会依次：连接 → 系统复位 → 下载 bit → 下载 ELF → 运行。

**看到最后这几行就成功了**：

```
 APP IS RUNNING.
 Open a serial terminal on the USB-UART port:
   115200 bps, 8 data bits, no parity, 1 stop bit
```

### 4. 打开串口终端

任选一种：

| 工具 | 说明 |
|---|---|
| **Vivado 内置** | `Window → Serial I/O`（Vivado 2018.3 没有，用下面两个） |
| **SDK 内置** | SDK → `Window → Show View → Terminal`，点 `+` 新建：选 COM 口，115200 |
| **MobaXterm / PuTTY** | 选串口，115200-8-N-1（推荐，最省事） |

**设备管理器里看 COM 号**：`端口(COM和LPT)` → `USB-SERIAL CH340 (COMx)`。

### 5. 你应该看到菜单

```
*** ZYNQ-7010 image filter (PS side) booting ***
PL version register = 0x00010000
PL is alive. AXI4-Lite link OK.

===== ZYNQ-7010 real-time image filter =====
  0/1/2/3 : set filter mode (gray/mean/gauss/sobel)
  e / d   : filter enable / bypass
  h       : measure hardware frame rate
  c       : software baseline vs hardware
  i       : dump registers
  m       : show this menu
===========================================
> 
```

### 6. 试这几个键

| 按键 | 作用 | 显示器 |
|---|---|---|
| `0` | 灰度 | 照片变灰 |
| `1` | 均值模糊 | 边缘变软 |
| `2` | 高斯模糊 | 更自然的糊 |
| `3` | **Sobel 边缘** | 黑底 + 白轮廓 |
| `d` | 旁路（直通） | 显示原图 |
| `e` | 恢复滤波 | |
| `h` | 测硬件帧率 | 串口打印 `~60 fps` |
| `c` | **跑软件基线对比** | 串口打印 CPU 每帧耗时 |
| `i` | 看寄存器 | |

**`c` 的输出就是你的加速比数据**，例如：

```
--- software baseline (320x240, CPU only) ---
  grayscale   SW:    4.81 ms/frame (  62.6 ns/pixel,  207.9 fps)
  mean 3x3    SW:   18.42 ms/frame ( 239.8 ns/pixel,   54.3 fps)
  gauss 3x3   SW:   19.05 ms/frame ( 248.0 ns/pixel,   52.5 fps)
  sobel       SW:   23.77 ms/frame ( 309.5 ns/pixel,   42.1 fps)

--- hardware reference ---
  HW: 1.024 ms for the same 76800 pixels (13.33 ns/pixel @75MHz)
```

---

## 故障表

| 现象 | 原因 | 办法 |
|---|---|---|
| xsct 报 `connect` 失败 | Vivado 的 Hardware Manager 占着硬件 | 关掉它再跑 |
| 串口全是乱码 | 波特率不对 | 必须 115200 |
| 串口无输出 | CH340 选了 `PL_TX` | 检查跳线/焊盘，选 PS_TX |
| 读到的 VERSION 不是 0x00010000 | AXI 基地址不对 | 看 BD 的 Address Editor，改 `main.c` 的 `AXIL_BASE` |
| 菜单能出但按 `3` 画面不变 | 没先 `e`（使能滤波）或 bit 流不是最新 | 用最新的 `system_top.bit` |
| `h` 帧率不是 60 | 正常范围 59~61 | 75MHz/1650/750 = 60.6fps |

---

## 做到这一步，你就有了完整的"软硬件协同"证据

| 证据 | 哪里来 |
|---|---|
| ARM 控制 FPGA 参数 | 串口按 0/1/2/3，PL 实时切换模式 |
| 硬件帧率 | `h` → ~60 fps，CPU 占用 0% |
| 软件基线 | `c` → CPU 每帧耗时 |
| 加速比 | 硬件 13.33 ns/像素 vs 软件 ~240 ns/像素 = **约 18 倍** |
| 同一算法同帧对比 | `sw_filter.c` 与 RTL 数值逐条对齐 |

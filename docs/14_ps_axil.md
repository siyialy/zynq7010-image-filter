# 第 8 步：AXI4-Lite 寄存器组（PS 控制 PL 的"遥控器"）

> 前面 PL 里的模式切换是**按键**控制的（纯硬件）。从这一步开始，ARM（PS）可以
> 通过总线读写 PL 里的参数、读回统计信息——这才是"软硬件协同"的技术实质。

## 成果

```powershell
cd D:\FPGA比赛
D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_axil_regs.tcl
```

实测输出：

```
PASS: MODE = 0x00000003
PASS: mode 输出 = 3
PASS: THRESH = 0x00000064
PASS: threshold 输出 = 0x64
PASS: CTRL = 0x00000001
PASS: filter_en 输出 = 1
PASS: VERSION = 0x00010000
PASS: FRAME_CNT = 0x00001234
PASS: STATUS = 0x000000aa
PASS: VERSION after illegal write = 0x00010000
PASS: illegal addr = 0xdeadbeef
RESULT: PASS  (AXI4-Lite register file works)
```

11 项检查全部通过，包括**往只读寄存器非法写入必须不生效**这一条。

## 寄存器映射（PS 侧 C 代码就按这个访问）

| 偏移 | 名字 | 方向 | 说明 |
|---|---|---|---|
| `0x00` | CTRL | R/W | bit0 = `filter_en`（1=开滤波，0=直通原图） |
| `0x04` | MODE | R/W | [2:0] 模式：0 灰度 / 1 均值 / 2 高斯 / 3 Sobel |
| `0x08` | THRESH | R/W | [7:0] 阈值（预留，可用于 Sobel 二值化） |
| `0x0C` | VERSION | R | 固定 `0x0001_0000`（软件用它确认硬件在位） |
| `0x10` | FRAME_CNT | R | 帧计数器（由 PL 提供） |
| `0x14` | STATUS | R | 状态字（锁定/溢出等，由 PL 提供） |

PS 侧访问方式（C 代码）：

```c
#define REG_BASE   0x43C00000        /* AXI GP0 映射地址，搭 BD 时确定 */
#define REG_MODE   (REG_BASE + 0x04)
#define REG_VER    (REG_BASE + 0x0C)

Xil_Out32(REG_MODE, 3);              /* 切到 Sobel */
u32 ver = Xil_In32(REG_VER);         /* 读回 0x00010000 说明 PL 在位 */
```

## AXI4-Lite 握手（为什么这么写）

一次写事务的完整握手：

```
主机：AWADDR + AWVALID ──┐
      WDATA  + WVALID  ──┤   从机把 AWREADY / WREADY 拉高
                          ▼
从机：BVALID ──────────▶ 主机回 BREADY ──▶ 一次写完成
```

读事务：

```
主机：ARADDR + ARVALID ──▶ 从机 ARREADY ──▶ 从机 RVALID + RDATA ──▶ 主机 RREADY
```

本实现是"最简单可用"版本：**一次只处理一个事务，不做流水线**。
对"PS 偶尔改一下模式、每秒读一次帧率"这种场景完全够用（带宽要求极低）。

如果要更高带宽（比如连续传图像），就得上 AXI4 突发传输或者 VDMA。

## 为什么不让 PL 直接产生所有参数

因为比赛评的是"软硬件划分是否合理"：

| 功能 | 放哪 | 理由 |
|---|---|---|
| 像素级卷积运算 | **PL** | 需要每拍一个像素的并行算力，CPU 做不到 |
| 模式/阈值等参数 | **PS**（写寄存器） | 变化慢、逻辑复杂（菜单、状态机），软件实现更灵活 |
| 帧率/延迟统计 | **PL 计数 + PS 读取** | 计数器硬件最准，人来解读 |
| 软件基线对比 | **PS** | 用来证明"硬件快多少" |

## 下一步

1. 把这个寄存器组挂到 Zynq 的 `M_AXI_GP0` 上（用 Block Design）
2. PS 侧 C 代码：串口菜单、读写寄存器、帧率统计
3. 软件基线滤波（同一帧用 ARM 算一遍）→ 算加速比

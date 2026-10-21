# 第 9 步：上板调试实录（从"能显示"到"四个模式全对"）

> 这一篇记录**真机调试**遇到的问题和定位方法。比"我写完了"更有价值的是
> "我怎么知道哪里错了"——评委也会问这个。

---

## 战果

| 项目 | 状态 |
|---|---|
| JTAG 扫链 | ✅ `xc7z010_1` 扫到（驱动/排线/供电全通） |
| 点灯 | ✅ LED0 1Hz 闪、按键响应 |
| HDMI 720p 出图 | ✅ 显示器出 8 条竖彩条 |
| 灰度模式 | ✅ 灰阶竖条正确（255/226/178/…/0） |
| 高斯模式 | ✅ |
| Sobel 模式 | ✅ 黑底 + 竖亮线 |
| **均值模式** | ❌→✅ 全黑 bug 已定位并修复（见问题 2） |
| 照片源（KEY1） | ✅ 320×240 照片 3 倍放大居中显示 |
| 照片 + 四模式 | ✅ 灰度/均值/高斯/**Sobel 轮廓**全部正常 |

---

## 问题 1：中文路径让 Program Device 失败

**现象**：填 `D:\FPGA比赛\board\bitstream\board_top_led.bit`，报

```
The file 'D:/FPGA/board/bitstream/board_top_led.bit' does not exist.
```

注意报错里的路径：**"比赛"两个字被吃掉了**。

**原因**：Vivado 的 Program Device 对话框用 ANSI API 处理路径，非 ASCII 字符丢失。

**解决**：bit 文件放纯英文目录，例如 `D:\fpga_build\bits\`。

> 这是本项目第 3 次撞到"中文路径"：综合崩溃、`$readmemh` 找不到文件、Program Device 路径截断。
> 统一规则：**凡是给 Vivado 读写的路径一律纯英文。**

---

## 问题 2（核心）：均值模式在硬件上全黑，但仿真正常

**现象**：按下 KEY0 切到 `mode 1`（均值模糊），显示器**全黑**。其他三个模式都正常。

**第一步判断**：仿真里 mode 1 是通过的（2867 个像素逐点吻合）。所以是
"**仿真对、硬件不对**"——这类问题最难查，因为 RTL 代码看起来完全正确。

### 定位方法：综合后仿真（post-synthesis simulation）

不要去猜，也不急着上逻辑分析仪。先用**综合后的网表**跑同一个 testbench：

```powershell
D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_img_filter_postsynth.tcl
```

实测输出（修复前）：

```
PASS: mode 0 -- 2867 pixels all match
FAIL: mode 1 -- 2867 of 2867 pixels mismatch     ← 全部输出 0！
PASS: mode 2 -- 2867 pixels all match
PASS: mode 3 -- 2867 pixels all match
```

**在本地就复现了硬件 bug**，而且精确定位到"只有均值通路坏"。

### 根因

均值公式原本写成：

```verilog
wire [17:0] mean_prod = sum9_r * 18'd57;    // 57/512 ≈ 1/9
wire [7:0]  px_mean  = mean_prod[17:9];
```

- **行为仿真**（RTL）：按 IEEE 语义算出完整乘积，取 `[17:9]`，正确
- **综合后**：Vivado 把 `*` 推断成 DSP48E1，并对"只用到乘积高 9 位"做了位宽优化，
  结果乘积被截断 → 高 9 位恒为 0 → 屏幕全黑

这是典型的"**综合优化改变了功能**"。DSP 推断不是错，错在依赖它处理"部分位宽"的乘法。

### 修复：不用乘法器，改成移位加法

`57 = 32 + 16 + 8 + 1`：

```verilog
wire [17:0] s9x   = {6'd0, sum9_r};                        // 18 位无符号
wire [17:0] m57   = (s9x << 5) + (s9x << 4) + (s9x << 3) + s9x;
wire [7:0]  px_mean = m57[16:9];
```

优点：
- **行为完全确定**，不依赖工具怎么推断
- 只用 3 个加法器，比 DSP 更省（70 LUT 级别的设计里这点开销无所谓）
- 综合后仿真与行为仿真**逐位一致**

修复后综合后仿真：

```
PASS: mode 0 / mode 1 / mode 2 / mode 3   （全部 2867 像素）
```

---

## 这个 bug 的教训（值得写进报告）

| 教训 | 说明 |
|---|---|
| **行为仿真通过 ≠ 硬件正确** | 仿真器按 IEEE 解释，综合器会做优化 |
| **一定要跑综合后仿真** | 一条命令的成本，能抓出"DSP/BRAM 推断改变功能"这类问题 |
| **别用乘法器算"部分位宽"** | `x * 57 >> 9` 这种"只要高位"的写法最容易被优化坏 |
| **常量乘法用移位加法最稳** | 尤其是系数简单（57=32+16+8+1）时 |

---

## 问题 3：3×3 模糊在宽彩条上"看不出效果"

**现象**：切到均值/高斯模式，画面和灰度模式几乎一样。

**原因**：彩条宽 160 像素，3×3 模糊只影响边缘 1~2 个像素——**远看确实没区别**。

**这不是 bug**，是测试图案不合适。

**后续改进**：加一个"细密棋盘格"图案（8×8 像素），模糊效果才会一眼可见。
报告里演示模糊效果时应该用这类图案。

---

## 当前硬件状态速查

| 操作 | 期望 |
|---|---|
| 上电 + Program `hdmi_top.bit` | 8 条竖彩条（灰度，mode 0） |
| KEY0 ×1 | 均值模糊（边缘变软，凑近看） |
| KEY0 ×2 | 高斯模糊 |
| KEY0 ×3 | Sobel：黑底 + 7 条等间距竖线 |
| KEY0 ×4 | 回到灰度 |
| KEY1 | 切换到照片源（320×240 放大 3 倍居中） |

LED[1:0] 用二进制显示当前模式：`00` 灰度 / `01` 均值 / `10` 高斯 / `11` Sobel。

---

## 问题 4（核心）：AXI 从机握手写错，ARM 卡死在第一条写操作

**现象**：
- 下载 bit + ARM 程序后，串口**一个字都没输出**
- PL 上的两个 LED 全灭（模式寄存器始终是 0）
- 显示器画面不变（还是灰度彩条）

**三个现象同时出现**，说明程序**根本没执行到第一行打印**。

### 定位过程（三步）

**第一步：确认 CPU 真的在跑**

用 xsct 暂停 APU 并读 PC：

```
pc = 0x00100C04
```

> 0x100000 正是 ELF 的加载地址 → 程序**确实在 DDR 里执行**，不是没启动。

**第二步：读 AXI 寄存器**

按正确方式（`connect` → 选 target → `loadhw` 加载 memory map）读 0x43C0000C，
会报 `Blocked address ... not added to the memory map`——这是调试器的保护，不是硬件错误。

**第三步：回到代码看握手**

看 `axil_regs.v` V1.0 的写通道：

```verilog
wire wr_fire = s_axi_awvalid & s_axi_wvalid & s_axi_awready & s_axi_wready;
```

**要求 AWVALID 和 WVALID 必须在同一拍到达。**

### 根因

AXI4-Lite 标准**允许地址和数据分不同周期到达**。真机上 Zynq 的 AXI 主机经常这样：

```
周期1： AWVALID=1  ← 地址先到，被 awready 收下
周期2： WVALID =1  ← 数据后到，被 wready 收下
```

在这种情况下：
- `wr_fire` 恒为 0 → **写丢失**
- `BVALID` 永远不拉高 → 主机等响应 → **CPU 永久阻塞在 `Xil_Out32`**

于是程序卡死在第一条寄存器写，后面所有代码（包括串口打印）都没机会执行。

### 为什么仿真没发现

我的 testbench 是这么驱动的：

```verilog
awvalid = 1'b1;  wvalid = 1'b1;   // 同一拍给
```

**恰好是最宽松的情况**，掩盖了 bug。

### 修复（两处）

**1. RTL：AW / W 各自独立锁存**

```verilog
// ready 独立产生
s_axi_awready <= ~aw_got & ~s_axi_bvalid;
s_axi_wready  <= ~w_got  & ~s_axi_bvalid;

// 各自接收
if (s_axi_awvalid && s_axi_awready) begin aw_addr_q <= wr_addr; aw_got <= 1'b1; end
if (s_axi_wvalid  && s_axi_wready ) begin wdata_q   <= s_axi_wdata; w_got <= 1'b1; end

// 都到齐才执行
if (aw_got && w_got) begin ...写入...; bvalid <= 1'b1; end
```

**2. Testbench：加"分开到达"的回归测试 + 修正驱动纪律**

- 新增 `axi_write_split(addr, data, gap, w_first)`：可以测"地址先到"和"数据先到"两种顺序
- 所有任务改成**下降沿驱动、上升沿采样**（原来在上升沿同一时刻改信号，会和 DUT 的采样竞争，导致地址采到上一笔）

修复后结果：

```
PASS: MODE / THRESH / CTRL / VERSION / FRAME_CNT / STATUS
PASS: MODE via split AW-then-W
PASS: CTRL via split W-then-AW
RESULT: PASS  (AXI4-Lite register file works)
```

### 教训

| 教训 | 说明 |
|---|---|
| **AXI4-Lite 手册必须逐字看** | "AW and W may be asserted independently" 是标准行为 |
| **从机 ready 要独立给** | 不能用"两者同时有效"当触发条件 |
| **testbench 要测最坏时序** | 只测"同时到达"等于没测 |
| **TB 驱动要在下降沿** | 上升沿改信号会和 DUT 采样竞争，产生假失败 |
| **硬件比仿真严格** | 仿真器容忍的写法，真机不一定容忍 |

# 电脑上具体怎么操作（不用板子，纯软件）

> 这份是"点哪里"级别的操作指引。照着做，不需要任何硬件。

## 先认清 3 个软件

| 软件 | 在哪 | 干什么 | 现在用不用 |
|---|---|---|---|
| **Vivado 2018.3** | 开始菜单搜 `Vivado 2018.3` | 写 Verilog、仿真、综合、生成 .bit、下载到板子 | ✅ **现在只用它** |
| SDK 2018.3 | `D:\XILINX\SDK\2018.3\bin\xsdk.bat` | 写 ARM（PS 端）C 代码 | 等 PS 系统做好再用 |
| Python | 命令行 `python` | 跑我给的图片转换工具 | 可选 |

---

# 任务 1：打开工程（2 分钟）

## 方法 A：双击（推荐）

打开文件资源管理器，进到：

```
D:\FPGA比赛\build\img_filter_sim\
```

**双击 `img_filter_sim.xpr`**。

Vivado 会自动启动并打开工程（第一次可能要等 1~3 分钟，界面会先出现欢迎页再变成工程界面）。

## 方法 B：先开软件再打开

1. 开始菜单 → 搜 `Vivado 2018.3` → 打开
2. 左上角 `File` → `Project` → `Open...`
3. 选 `D:\FPGA比赛\build\img_filter_sim\img_filter_sim.xpr`

## 打开后你应该看到

```
┌──────────────────────────────────────────────────────────┐
│ 菜单栏 File Edit Flow Tools Reports Window Help           │
├──────────────┬───────────────────────────────────────────┤
│ Flow         │  Project Summary                          │
│ Navigator    │  - Sources (设计源文件)                    │
│              │  - Simulation (测试文件)                   │
│ ▸ PROJECT    │                                           │
│ ▸ IP INTEG   │                                           │
│ ▸ SIMULATION │ ← 这里待会点                              │
│ ▸ SYNTHESIS  │                                           │
│ ▸ IMPLEMENT  │                                           │
├──────────────┴───────────────────────────────────────────┤
│ Tcl Console / Messages / Log / Reports  ← 底部标签栏      │
└──────────────────────────────────────────────────────────┘
```

> 如果左边没有 `Flow Navigator`：菜单 `Window` → `Flow Navigator` 打勾。
> 如果底部没有 `Tcl Console`：菜单 `Window` → `Tcl Console`。
> 界面乱了：`Window` → `Reset Layout`。

---

# 任务 2：跑一次仿真（3 分钟）

1. 左边 `Flow Navigator` 面板 → 展开 **`SIMULATION`**
2. 点 **`Run Simulation`**
3. 弹出小菜单 → 点 **`Run Behavioral Simulation`**

**接下来会发生什么**（按顺序）：

| 步骤 | 你会看到 | 大约耗时 |
|---|---|---|
| 1 | 底部 `Tcl Console` 滚动编译信息 | 10~20 秒 |
| 2 | 弹出 **waveform（波形）窗口**，界面变成仿真布局 | — |
| 3 | 波形窗口底部出现一排信号 | — |
| 4 | 仿真自动跑完（代码里有 `$finish`） | 10~60 秒 |

**关键：在底部 `Tcl Console` 里找这几行**：

```
PASS: 模式 0 —— 2867 像素全部吻合（跳过 205 个占位像素）
PASS: 模式 1 —— 2867 像素全部吻合
PASS: 模式 2 —— 2867 像素全部吻合
PASS: 模式 3 —— 2867 像素全部吻合
```

看到 4 行 `PASS` = 你的软件环境完全正常，滤波核逻辑正确。

---

# 任务 3：看波形（重点，10 分钟）

波形窗口一开始只有 tb 顶层信号。要看到滤波核内部，得手动加。

## 3.1 加信号

1. 波形窗口左上有个 **`Scope`** 面板，双击 `tb_img_filter_3x3` → 展开 `u_dut`
2. 在 `Objects` 面板里能看到这个模块的所有信号
3. **选中** 你要看的信号（按住 Ctrl 多选）
4. 右键 → **`Add to Wave Window`**

**推荐加这几个**（按顺序理解）：

| 信号 | 含义 |
|---|---|
| `de` / `in_x` / `in_y` | 输入有效、列号、行号 |
| `out_de` / `out_x` / `out_y` | 输出（比输入晚 8 拍） |
| `out_rgb[7:0]` | 输出像素值（灰度） |
| `mode[2:0]` | 当前模式 |

## 3.2 放大到能看

1. 工具栏点 **`Zoom Fit`**（放大镜+方框图标），看全局
2. 你会发现 `mode` 分成了 4 段（0→1→2→3），这就是 4 帧
3. 想看细节：在波形区**滚轮缩放**，或点 `Zoom In`（放大镜+加号）

## 3.3 验证 Sobel（最关键的一步）

1. 在波形里**扫过** `mode`，找到它等于 `3` 的那一段
2. 在那段里，观察 `out_rgb[7:0]`：
   - 大部分时间是 **0**（彩条内部没有梯度）
   - 每隔 80 个像素**突然跳到 255**（这就是彩条交界处的边缘）
3. 在 `out_x` 上验证：跳变应该发生在 x = 79/80、159/160、239/240… 附近

**这就是"硬件算出了 7 条 Sobel 竖线"的直接证据**——上板后显示器上看到的就是这个。

## 3.4 看数据怎么"流"过去

1. 把时间轴拉到某一行的开头（`x == 0` 的位置）
2. 看 `de` 高电平持续 **64 拍**（因为测试图是 64 宽）
3. 看 `out_de` 比 `de` **晚 8 拍** 才开始有效——这就是流水线延迟
4. 看 `out_x` 比 `in_x` 滞后 8 拍，值也刚好差 1（窗口中心偏 1 像素）

**看懂这个，你就理解了"流水线"到底是什么意思。**

---

# 任务 4：看一次"完整画面"的效果（5 分钟）

打开另一个工程：**双击 `D:\FPGA比赛\build\pipeline_sim\pipeline_sim.xpr`**

同样 `SIMULATION` → `Run Behavioral Simulation`。

这个 tb 会跑 640×480 的一整帧，并在 `Tcl Console` 打印：

```
PASS: 行周期 = 32000 ns（800 像素）
PASS: DE 宽度 = 25600 ns（640 像素）
PASS: mode0 x=40 灰度 = 255
...
Sobel 亮线 #0：x = 79 ~ 80（中心 79）
Sobel 亮线 #1：x = 159 ~ 160（中心 159）
...
PASS: Sobel 出现 7 条竖亮线
```

**这 7 行"亮线"就是显示器上那 7 条竖线的坐标。**

---

# 任务 5：看综合报告（资源用了多少、时序够不够）

1. 双击打开 **`D:\fpga_build\hdmi\hdmi.xpr`**
2. 左边 `Flow Navigator` → `IMPLEMENTATION` → 点 **`Open Implemented Design`**
   （工程已经跑完实现，直接打开就行，不用重跑）
3. 菜单 `Reports` → **`Report Utilization`** → 看：

| 资源 | 用了多少 |
|---|---|
| Slice LUTs | 678 / 17600（3.85%） |
| Slice Registers | 478 / 35200（1.36%） |
| Block RAM Tile | 0.5 / 60 |
| DSPs | 1 / 80 |

4. 菜单 `Reports` → **`Report Timing Summary`** → 看 **WNS = +4.063 ns**（正数=时序收敛）

**答辩时这两页截图就是"性能与资源"的证据。**

---

# 任务 6：用 Python 把照片转成 .coe（可选，5 分钟）

1. 按 `Win + R`，输入 `powershell`，回车
2. 输入：

```powershell
cd D:\FPGA比赛
python tools\bmp2coe.py "C:\Users\九思\Pictures\你的照片.jpg" -o tools\我的图.coe --width 320 --height 240 --gray
```

3. 看输出：

```
原图尺寸      : 1920x1080
存储尺寸      : 320x240, 8 bit/像素
总容量        : 0.59 Mb
BRAM36 占用   : 约 17 / 60 块 (28%)
[OK] 容量合适，可以烧进 BRAM
```

4. 打开同目录的 `我的图_preview.png` 看效果（这就是要烧进 FPGA 的图）

> 如果提示 `python 不是内部或外部命令`：说明 PATH 没有 Python。直接告诉我，我给你完整路径。

---

# 任务 7（电来了再做）：下载到板子

1. 板子上电、拨码 ON/ON、接好 JTAG 和 HDMI
2. Vivado → 左边最下面 **`Open Hardware Manager`**
3. 上方 **`Open target`** → **`Auto Connect`**
4. 出现 `xc7z010_1` 后，右键 → **`Program Device`**
5. Bitstream file 选：
   - 点灯：`D:\FPGA比赛\board\bitstream\board_top_led.bit`
   - 显示：`D:\FPGA比赛\board\bitstream\hdmi_top.bit`
6. 点 **`Program`**

---

# 每个工程是干什么的（对照表）

| 工程文件 | 用来做什么 |
|---|---|
| `build\led_sim\led_sim.xpr` | 第 1 个实验：计数器分频点灯 |
| `build\debounce_sim\debounce_sim.xpr` | 第 2 个实验：按键消抖 |
| `build\video_timing_sim\video_timing_sim.xpr` | 第 3 个实验：视频时序 + 彩条 |
| **`build\img_filter_sim\img_filter_sim.xpr`** | **第 4 个实验：3×3 滤波核（核心）** |
| `build\pipeline_sim\pipeline_sim.xpr` | 顶层流水线（彩条→滤波） |
| `D:\fpga_build\hdmi\hdmi.xpr` | HDMI 720p 工程（含综合实现结果） |
| `D:\fpga_build\led_board\led_board.xpr` | 点灯上板工程 |

> 注意：`D:\fpga_build\` 是**纯英文的构建目录**，故意放在外面——
> 因为 Vivado 在中文路径下综合会崩（见 [docs/11](11_step6_board_led.md)）。
> 仿真工程在中文路径下没问题，所以留在 `D:\FPGA比赛\build\`。

---

# 界面常见问题

| 现象 | 解决 |
|---|---|
| 找不到 Flow Navigator | 菜单 `Window` → `Flow Navigator` |
| 找不到 Tcl Console | 菜单 `Window` → `Tcl Console` |
| 波形窗口被我关掉了 | 重新点 `Run Simulation` → `Run Behavioral Simulation`（会重新打开） |
| 界面排版乱了 | 菜单 `Window` → `Reset Layout` |
| 双击 .xpr 打不开 | 先打开 Vivado，再用 `File → Project → Open` |
| 仿真一直转圈 | 第一次编译要 20~40 秒，耐心等；超 2 分钟说明卡了，看 Tcl Console 报错 |

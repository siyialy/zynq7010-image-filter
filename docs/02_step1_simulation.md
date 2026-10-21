# 第 1 步：跑通你的第一个 FPGA 仿真（不用板子，20 分钟）

> 目标：亲眼看到"我写的 Verilog 变成了波形"。这一步不碰硬件，所以不会烧板子、不会失败在上板环节。

## 为什么要先仿真，而不是先点灯

零基础最容易踩的坑，是**第一次就上板**：代码有语法错、约束文件缺失、下载器没装、板子型号选错……任何一个小问题都会让你卡一整天，还学不到东西。

仿真是"在电脑里把电路跑一遍"，只用 Vivado，不接板子。它能把 90% 的逻辑错误当场抓出来。养成"先仿真、再上板"的习惯，你后面会省掉无数时间。

## 方式 A：一条命令跑完（推荐，先看到结果）

打开 PowerShell（或 CMD），执行：

```powershell
cd D:\FPGA比赛
D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_led_blink.tcl
```

**第一次运行要等 1~3 分钟**（Vivado 启动 + 建工程 + 编译 + 仿真），期间屏幕上会滚很多东西，这是正常的。

你要找的关键行（下面是**实测输出**，2026-10-20 在本机跑出来的）：

```
INFO: proj_root = D:/FPGA比赛
INFO: proj_dir  = D:/FPGA比赛/build/led_sim
...
=== tb_led_blink start ===
[190000 ns] reset released
...
[3000190000 ns] rise_cnt = 3
RESULT: PASS  (LED 正常翻转 3 次)
INFO: simulation finished
=== TCL SCRIPT DONE ===
```

看到 **`RESULT: PASS`**，这一步就完成了 ✅

> 实测结论：**中文路径 `D:\FPGA比赛` 在 Vivado 2018.3 的仿真流程里是可以正常工作的**（编译、elaborate、仿真全部通过）。只是控制台里中文会显示成 `D:/FPGA????`，那是编码显示问题，不影响结果。如果后面综合或 IP 生成阶段出现路径相关报错，再改用纯英文目录：
> ```powershell
> D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_led_blink.tcl -tclargs D:/fpga_build/led_sim
> ```

## 方式 B：在图形界面里手动做一遍（强烈建议做，因为比赛现场你得会操作）

命令行的方式你看不到"工程长什么样"。请再手动做一遍，记住界面：

1. **启动**：开始菜单搜索 `Vivado 2018.3` → 打开。
2. **建工程**：左边 `Flow Navigator` → `Create Project` → Next
   - Project name：`led_blink_gui`
   - Project location：`D:/fpga_build`（**纯英文路径**，别放中文目录）
   - 勾掉 `Create project subdirectory`（可选）
   - Project type：`RTL Project`，勾 `Do not specify sources at this time` → Next
   - Default part → 选 `Parts` → 搜索 `xc7z010clg400` → 选 **xc7z010clg400-1** → Next → Finish
3. **加源文件**：`PROJECT MANAGER` → `Add Sources` → `Add or create design sources` → `Add Files` → 选 `D:\FPGA比赛\src\rtl\led_blink.v` → Finish（弹窗问 define module 就点 OK/Cancel 都行）
4. **加测试文件**：`Add Sources` → `Add or create simulation sources` → `Add Files` → 选 `D:\FPGA比赛\src\sim\tb_led_blink.v` → Finish
5. **设顶层**：在 `Sources` 窗口，右键 `tb_led_blink` → `Set as Top`；再确认 `led_blink` 已经在设计源里。
6. **跑仿真**：左边 `Flow Navigator` → `SIMULATION` → `Run Simulation` → `Run Behavioral Simulation`。等编译完，会弹出波形窗口。
7. **看波形**：
   - 窗口里能看到 `clk`、`rst_n`、`led`、`cnt`。
   - 点工具栏的 **`Zoom Fit`**（放大镜+方框图标）看全局，`led` 应该是一条方波。
   - 在 `Scopes` 窗口点 `u_dut` 能看到模块内部信号 `cnt`。
   - 顶部中间的 **`Tcl Console`** 里会打印 `RESULT: PASS`。

## 这一步你到底学到了什么（答辩能讲的东西）

| 概念 | 在这个实验里的具体体现 |
|---|---|
| 模块与端口 | `led_blink` 有 3 个端口：`clk`（输入）、`rst_n`（输入）、`led`（输出） |
| 时序逻辑 | `always @(posedge clk)` 里面的语句每个时钟上升沿生效一次，综合出来就是触发器 |
| 分频 | 50MHz 太快人眼看不出，用计数器数 2500 万个节拍翻转一次，得到 1Hz |
| 参数化 | `CLK_FREQ`、`BLINK_HZ` 是参数，同一份代码换个板子改参数就能用 |
| testbench | 不是电路，是"喂信号的脚本"：生成时钟、给复位、等时间、检查结果 |
| 自检 | `rise_cnt >= 3` 这种断言比"肉眼看波形"可靠，后面所有模块都要这么测 |

## 常见疑问

**Q：仿真显示 PASS，是不是就能上板了？**
A：不一定。仿真不检查引脚、不检查时钟质量。上板还需要 XDC 约束文件（见 `03_board_materials.md`），而且要在综合/实现不报错、时序收敛（WNS ≥ 0）之后。

**Q：`<=` 和 `=` 有什么区别？**
A：在 `always @(posedge clk)` 里必须用 `<=`（非阻塞），它表示"所有触发器同时更新"；组合逻辑 `always @(*)` 里用 `=`。

**Q：为什么 `rst_n` 要低有效？**
A：板子上按键按下接地，天然是低电平，所以复位信号习惯用低有效，代码里写 `negedge rst_n`。

**Q：`reg` 和 `wire` 怎么选？**
A：在 `always` 块里被赋值的用 `reg`；用 `assign` 赋值的、或者只是连线的用 `wire`。

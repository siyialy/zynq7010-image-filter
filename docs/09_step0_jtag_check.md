# 第 0 步：让 Vivado "看见"你的板子（不需要原理图，不需要工程）

> 这是零基础第一次摸硬件的关键一步：**只要 Vivado 能扫到 xc7z010，就说明下载器、驱动、电源、JTAG 接线全部正常**。
> 做到这一步，后面"点灯"就只剩一个 .xdc 文件的事了。

## 你箱子里的东西（已确认）

| 东西 | 是什么 | 用途 |
|---|---|---|
| 正点原子 **PTD04 FPGA 下载器** | JTAG 下载器（FT2232 方案，支持 Xilinx ZYNQ/FPGA/CPLD） | ★ 把 .bit 下进 FPGA、把 .elf 下进 ARM，都靠它 |
| 2 条灰色排线 | 14 脚（2×7）、2.0mm 间距，丝印 `TCK TDO TDI TMS GND VCC` | 插板子上的 `JTAG` 座 |
| 3 根 Micro-USB 线 | 数据线 | 下载器 1 根、板子 `USB UART` 1 根、`USB SLAVE` 1 根 |
| microSD 读卡器 | 只是读卡器 | 暂时用不到（要做 SD 卡启动时才需要，还得另买卡） |

**还缺**：电源适配器、HDMI 线 + 带 HDMI 输入的显示器。

## 步骤 1：装 USB 线缆驱动

Vivado 自带的驱动安装器在（我已确认存在）：

```
D:\XILINX\Vivado\2018.3\data\xicom\cable_drivers\nt64\install_drivers_wrapper.bat
```

操作：
1. **先插上下载器**（只插 USB，不接板子），让它出现在设备管理器里
2. **以管理员身份**运行上面那个 `.bat`（右键 → 以管理员身份运行）
3. 弹出驱动安装向导就一路"下一步/安装"
4. 装完**重新插拔**下载器

> PTD04 是第三方方案，Vivado 可能把它识别成 `Xilinx Platform Cable USB II`，也可能识别成 `Digilent USB Device`（Vivado 里带了两套驱动：`xusbdfwu` 和 `digilent`），两种都能用。
> 如果装完还是"未知设备"，去资料盘 `6_常用软件` 里找正点原子提供的下载器驱动，或者用设备管理器"更新驱动程序 → 浏览计算机"指向 `nt64` 目录。

## 步骤 2：接线 + 拨码

1. **电源**：给板子接上 DC 电源（先确认电压，见 [05_shopping_list.md](05_shopping_list.md)）
2. **拨码**：板上 `BOOT CFG` 两个开关都拨到 **ON**（表上写的就是 `JTAG = ON/ON`）
3. **JTAG 排线**：一头插下载器的 2×7 排针，另一头插板子的 `JTAG` 座
   - 排线有**防呆缺口**，插不进去就是方向反了，别硬怼
   - 板子的 `JTAG` 座丝印旁边通常有个小三角/圆点标记 1 脚，排线的红线（1 脚）要对应
4. **USB 线**：下载器接电脑

## 步骤 3：在 Vivado 里扫链（不用建工程）

1. 打开 Vivado 2018.3
2. 左边 `Flow Navigator` 最下面 → **`Open Hardware Manager`**
3. 上方点 **`Open target`** → **`Auto Connect`**
4. 等几秒

**成功的样子**：Hardware 窗口里出现一棵树：

```
localhost (127.0.0.1)
└── xilinx_tcf/Digilent/xxxxx   (或 Xilinx/xxxxx)
    └── xc7z010_1        ← 这就是你的芯片，扫到它就赢了
        └── arm_dap (或 xc7z010)
```

**扫到 `xc7z010_1` 就说明**：下载器 OK、驱动 OK、排线 OK、板子供电 OK、JTAG 没有虚焊。
这一步过了，后面所有"上板"操作都只是这个流程的重复。

## 失败排查表

| 现象 | 大概率原因 | 怎么办 |
|---|---|---|
| 设备管理器里根本没有新设备 | USB 线是"只充电线"、或下载器没通电 | 换一根线；换一个 USB 口（优先主板后置口） |
| 设备管理器里有**黄色感叹号** | 驱动没装 | 管理员运行 `install_drivers_wrapper.bat`，或手动指定 `nt64` 目录 |
| `Auto Connect` 转圈后报 `no cable found` | 驱动不匹配 | 设备管理器看它叫什么，对应装 Xilinx / Digilent 驱动 |
| 扫到 cable 但**没有芯片** | 排线方向反了 / 板子没上电 / 拨码不是 JTAG | 检查三项；板子上电后 LED 应该亮 |
| 扫到芯片但 ID 不对 | 排线接触不良 | 重新插紧，尤其板子端 |

## 做完之后

把 Hardware Manager 里那棵树**截图发我**（能看到 `xc7z010_1` 就行）。

拿到原理图/XDC 后，我立刻给你上板点灯的完整工程；下载器既然已经在手，资料一到就能当天点亮。

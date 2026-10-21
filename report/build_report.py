# -*- coding: utf-8 -*-
"""
build_report.py —— 按比赛模板生成作品报告
输出：report/作品报告.docx
"""
import os
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

HERE = os.path.dirname(os.path.abspath(__file__))
FIG  = os.path.join(HERE, "figures")
PHO  = os.path.join(HERE, "photos")
TPL  = r"D:\2658aa94-81d0-454c-b2ac-fc040ff2c01a.docx"
OUT  = os.path.join(HERE, "design_report.docx")

EA = "宋体"
EA_H = "黑体"
ASCII_F = "Times New Roman"

doc = Document(TPL)

# ---------------- 清空模板正文（保留节属性：页面大小/页边距） ----------------
body = doc.element.body
sectPr = body.find(qn('w:sectPr'))
for child in list(body):
    if child is not sectPr:
        body.remove(child)

# ---------------- 基础样式 ----------------
normal = doc.styles['Normal']
normal.font.name = ASCII_F
normal.font.size = Pt(12)          # 小四
normal.element.rPr.rFonts.set(qn('w:eastAsia'), EA)
normal.paragraph_format.line_spacing = 1.5
normal.paragraph_format.space_after = Pt(0)


def _set_run(run, size=12, bold=False, ea=EA, color=None):
    run.font.name = ASCII_F
    run.font.size = Pt(size)
    run.font.bold = bold
    run._element.rPr.rFonts.set(qn('w:eastAsia'), ea)
    if color:
        run.font.color.rgb = RGBColor(*color)


def H(text, level=1, size=None, before=12, after=6, align=None):
    """标题"""
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.3
    if align is not None:
        p.alignment = align
    sizes = {0: 18, 1: 15, 2: 13.5, 3: 12}
    r = p.add_run(text)
    _set_run(r, size or sizes.get(level, 12), bold=True, ea=EA_H)
    return p


def P(text, indent=True, size=12, bold=False, align=None, space_after=0):
    p = doc.add_paragraph()
    if indent:
        p.paragraph_format.first_line_indent = Pt(size * 2)
    p.paragraph_format.space_after = Pt(space_after)
    if align is not None:
        p.alignment = align
    r = p.add_run(text)
    _set_run(r, size, bold)
    return p


def CAP(text, above=False):
    """图注/表注。above=True 用于表题（置于表格上方，并与表格同页）"""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    if above:
        p.paragraph_format.space_before = Pt(10)
        p.paragraph_format.space_after = Pt(3)
        p.paragraph_format.keep_with_next = True   # 表题不能与表格分页
    else:
        p.paragraph_format.space_before = Pt(3)
        p.paragraph_format.space_after = Pt(10)
    r = p.add_run(text)
    _set_run(r, 10.5, bold=False, color=(40, 40, 40))
    return p


def IMG(path, width_cm=14.0, caption=None):
    if not os.path.exists(path):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = p.add_run("【此处待插入图片：%s】" % os.path.basename(path))
        _set_run(r, 10.5, bold=True, color=(200, 0, 0))
        if caption:
            CAP(caption)
        return
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(0)
    p.add_run().add_picture(path, width=Cm(width_cm))
    if caption:
        CAP(caption)


def BULLET(text, size=12):
    p = doc.add_paragraph(style='List Paragraph')
    p.paragraph_format.left_indent = Pt(size * 2)
    p.paragraph_format.space_after = Pt(0)
    r = p.add_run("• " + text)
    _set_run(r, size)
    return p


def set_table_borders(table):
    tbl = table._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement('w:tblBorders')
    for edge in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        el = OxmlElement('w:' + edge)
        el.set(qn('w:val'), 'single')
        el.set(qn('w:sz'), '6')
        el.set(qn('w:space'), '0')
        el.set(qn('w:color'), '808080')
        borders.append(el)
    tblPr.append(borders)


def TABLE(headers, rows, widths=None, caption=None, fontsize=10.5):
    if caption:
        CAP(caption, above=True)          # 表题在表格上方
    t = doc.add_table(rows=1, cols=len(headers))
    set_table_borders(t)
    t.autofit = False
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    hdr = t.rows[0].cells
    for i, h in enumerate(headers):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = p.add_run(h)
        _set_run(r, fontsize, bold=True, ea=EA_H)
        shd = OxmlElement('w:shd')
        shd.set(qn('w:fill'), 'EDF2F9')
        hdr[i]._tc.get_or_add_tcPr().append(shd)
    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if i else WD_ALIGN_PARAGRAPH.LEFT
            r = p.add_run(str(v))
            _set_run(r, fontsize)
    if widths:
        tblPr = t._tbl.tblPr
        layout = OxmlElement('w:tblLayout')
        layout.set(qn('w:type'), 'fixed')
        tblPr.append(layout)
        for i, w in enumerate(widths):
            for row in t.rows:
                row.cells[i].width = Cm(w)
    return t


# ============================================================== 封面标题
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_before = Pt(6)
p.paragraph_format.space_after = Pt(18)
r = p.add_run("基于 ZYNQ-7010 的软硬件协同实时图像硬件加速滤波系统")
_set_run(r, 20, bold=True, ea=EA_H)

# ============================================================== 摘要
H("摘要", 1)
P("图像滤波是机器视觉、工业检测、医疗影像与智能安防等应用的基础环节。以 3×3 卷积为典型代表的"
  "均值、高斯与 Sobel 算子，在 1280×720 分辨率、60 Hz 场频（即 720p60）的视频流上，需要每秒完成约"
  " 5500 万像素的邻域运算；"
  "若由通用嵌入式处理器逐像素执行，单帧耗时远超人眼可接受的延迟，且会占满 CPU 算力，"
  "使上层算法无以为继。针对这一问题，本作品设计并实现了一套基于 Xilinx ZYNQ-7010 全可编程 SoC 的"
  "软硬件协同实时图像滤波加速系统。")
P("系统采用“PL 做数据通路、PS 做控制与度量”的分工：PL 侧构建了一条从视频时序生成、图像源选择、"
  "3×3 卷积滤波、到 TMDS 编码输出的全流水线数据通路，滤波核内含两条行缓冲（Line Buffer）、"
  "九个抽头寄存器、四组并行加法树以及乘加/移位/绝对值运算单元，做到每个像素时钟输出一个像素，"
  "并使用同一套硬件资源共享实现灰度、均值、高斯、Sobel 四种模式，模式切换零延迟；"
  "PS 侧通过 AXI4-Lite 总线访问自研寄存器组，完成模式设定、阈值配置、PL 版本确认与帧计数读取，"
  "并以串口命令行形式提供人机接口，同时在同一帧上运行与硬件数值完全一致的 C 语言软件基线用于对比。")
P("跨时钟域是软硬件协同的关键难点，本作品针对两类信号分别设计：配置类信号（模式、阈值、使能）"
  "采用两级触发器同步并标注 ASYNC_REG 属性；反向的帧计数信号采用“脉冲同步 + 本地计数”方案，"
  "避免直接读取 32 位计数器时读到进位中间值。")
P("实测结果表明：系统稳定输出 1280×720 图像，实际场频 60.6 Hz（1 秒计数窗口实测约 60 fps）；"
  "硬件单像素耗时 13.33 ns，处理整帧 921600 像素仅需 12.29 ms，在 16.50 ms 的帧周期内留有 4.21 ms 余量，"
  "滤波期间 CPU 占用率约为 0%；"
  "同一算法在 ARM Cortex-A9 上以 -O2 优化编译后单像素仍需 166~178ns，硬件较软件提升约 13 倍；"
  "若要求软件处理完整 720p 帧则需 153ms，比实时差 9.2 倍，说明该类算子在软件上不具备实时性。"
  "设计资源占用为 LUT 8.7%、寄存器 3.2%、块 RAM 54%，时序收敛（WNS +3.447ns）。")
p = doc.add_paragraph()
p.paragraph_format.space_before = Pt(6)
r = p.add_run("关键词：")
_set_run(r, 12, bold=True, ea=EA_H)
r = p.add_run("ZYNQ；软硬件协同设计；图像滤波；Sobel 边缘检测；AXI4-Lite；跨时钟域；实时视频；FPGA 加速")
_set_run(r, 12)

# ============================================================== 第一部分
H("第一部分  作品概述", 1)

H("1.1  功能与特性", 2)
P("本作品在一块常见的 ZYNQ-7010 开发板上，实现了对视频图像的四类实时硬件处理与人机可交互控制，"
  "具体功能如下：")
BULLET("实时视频输出：PL 内部自行生成 1280×720、60 Hz 场频的视频时序，通过 TMDS 差分信号直驱 HDMI 显示器，"
       "不依赖任何外部视频编码芯片，实测帧率约 60 fps。")
BULLET("四种硬件滤波：灰度（BT.601 加权）、均值 3×3、高斯 3×3、Sobel 边缘检测，"
       "全部在 PL 内以每拍一个像素的速率完成，可在运行中零延迟切换。")
BULLET("双图像源：内置彩条测试图案与 320×240 灰度照片 ROM；照片经 4 倍像素复制放大后居中裁剪至满屏显示，"
       "用于直观展示滤波前后差异，并可通过板上按键一键切换。")
BULLET("软硬件协同控制：ARM 通过 AXI4-Lite 读写 PL 寄存器，用串口命令行即可切换模式、旁路滤波、"
       "查询寄存器状态，实现“软件下命令、硬件做计算”。")
BULLET("性能自测能力：软件可读取 PL 的 32 位帧计数器并结合片内定时器实测硬件帧率；"
       "同时内置与硬件逐条对齐的 C 语言软件基线，可在同一帧上对比软硬件耗时并自动计算加速比。")

H("1.2  应用领域", 2)
P("3×3 邻域卷积是图像处理的“原子操作”，本作品所验证的加速结构可直接迁移到以下场景：")
BULLET("工业视觉检测：产线高速相机（60~120fps）下的缺陷边缘提取、尺寸测量与表面划痕检测，"
       "需要在毫秒级完成 Sobel/Canny 前级梯度计算。")
BULLET("智能安防与车载视觉：多路视频接入时的实时去噪、图像增强与目标轮廓提取，"
       "对确定性的低延迟有硬性要求。")
BULLET("医疗影像与显微成像：超声、内窥镜等实时成像设备的边缘增强与降噪，"
       "要求处理链路延迟稳定、不随画面内容波动。")
BULLET("无人机与机器人视觉：机载算力与功耗受限，把像素级运算卸载到 FPGA 可显著降低主控负载，"
       "为位姿估计、避障等上层算法留出算力。")
P("上述场景的共同特征是“像素率高、算子局部、实时性刚性”，正是可编程逻辑相对通用处理器的优势区，"
  "也说明本作品的设计思路具有较好的通用性。")

H("1.3  主要技术特点", 2)
P("（1）全流水线、零停顿的像素级并行结构。滤波核采用“行缓冲 + 九个抽头寄存器 + 四组并行加法树”"
  "的经典滑窗结构：两条行缓存分别保存前两行数据，随像素流滑动即可在每拍同时获得 3×3 邻域的全部九个"
  "像素，因此吞吐率恒为每时钟 1 像素，与画面内容无关，延迟固定为 12 拍（160ns）。")
P("（2）四种算子共享同一套数据通路。灰度、均值、高斯与 Sobel 的计算在第 4 级之后分叉："
  "共享行缓存与抽头寄存器，仅在加法树与末级运算上并行展开，最后通过四选一选择器输出，"
  "因此增加模式几乎不增加存储器开销，且切换模式不需要清空流水线。")
P("（3）软硬件分工明确、接口标准化。PL 只负责数据通路，所有可配置参数（模式、阈值、使能）与可观测"
  "状态（版本号、帧计数）都通过 AXI4-Lite 寄存器暴露给 PS；PS 侧代码与 PL 内部实现解耦，"
  "仅依赖一份寄存器手册，便于后续更换滤波算子或增加模式。")
P("（4）严格的跨时钟域处理与时序收敛。系统内存在 50MHz 晶振时钟、75MHz 像素时钟、375MHz 串行时钟与"
  "100MHz AXI 时钟共四个时钟、三个异步域；作品对配置信号采用双触发器同步并标注 ASYNC_REG，"
  "对帧计数采用脉冲同步方案，同时用 set_clock_groups 与 set_max_delay 正确约束异步路径，"
  "使工具不会对跨域路径报出假违例，最终 WNS 达 +3.447ns。")
P("（5）工程可复现。全部设计以 Tcl 脚本从源码一键重建（Block Design、IP 生成、综合、实现、"
  "bit 流与硬件描述文件导出、ARM 程序编译与下载），配套 7 个仿真 testbench 覆盖滤波核、视频时序、"
  "AXI 从机、图像源与顶层数据通路，便于评审复现与二次开发。")

H("1.4  主要性能指标", 2)
TABLE(
    ["指标", "数值", "说明"],
    [
        ["输出分辨率 / 场频", "1280×720，60.6 Hz", "75MHz÷1650÷750；实测约 60 fps"],
        ["硬件单像素耗时", "13.33 ns", "75MHz 像素时钟，每拍 1 像素"],
        ["硬件整帧处理时间", "12.29 ms", "921600 像素，帧周期 16.50 ms"],
        ["软件单像素耗时", "166 ~ 178 ns", "Cortex-A9 @667MHz，-O2"],
        ["加速比", "约 13 倍", "同算法、同帧逐像素对比"],
        ["滤波期间 CPU 占用", "≈ 0%", "像素运算全部在 PL"],
        ["时序收敛", "WNS +3.447 ns", "75MHz 时钟，无违例"],
        ["资源占用", "8.7% / 3.2% / 54%", "LUT / FF / BRAM，XC7Z010-1CLG400C"],
        ["视频链路延迟", "160 ns", "12 拍像素时钟"],
        ["实时余量", "4.21 ms", "16.50 ms 帧周期内"],
        ["系统功耗", "约 2.6 W", "12V 供电，整板实测"],
    ],
    widths=[4.0, 4.2, 5.8],
    caption="表 1  主要性能指标"
)

H("1.5  主要创新点", 2)
BULLET("以“寄存器化接口 + 四选一末级”实现多算子共享同一数据通路：在不增加行缓存与抽头寄存器的前提下，"
       "同时支持点运算、低通与高通三类算子，模式切换零延迟、不打断视频流。")
BULLET("自研 AXI4-Lite 从机采用地址/数据独立锁存结构，严格符合 AXI 规范中 AW 与 W 可分离到达的时序要求，"
       "避免了“同拍到达”错误实现导致主机永久阻塞的问题（该问题在真机上表现为 CPU 死锁，详见 2.3.2 节）。")
BULLET("针对“慢变配置”与“反向计数”两类跨时钟域信号分别设计同步方案，并给出可复用的约束模板，"
       "使异步路径既不误报违例、也不被工具过度优化。")
BULLET("在无摄像头的条件下，用“片上 ROM + 像素复制放大”构建可复现、可对比的图像源，"
       "使系统在脱离外部输入设备时仍能完整演示四种算子的效果，降低了演示与评审的硬件门槛。")

H("1.6  设计流程", 2)
P("作品遵循“先仿真、再上板；先单元、后系统”的流程，共分五个阶段："
  "①需求与指标分解，确定 720p60、每拍 1 像素的吞吐目标；"
  "②以 Verilog 自顶向下实现各 RTL 模块，并为每个模块编写独立 testbench，用 Python 生成黄金参考模型逐像素比对；"
  "③在 Vivado 中以 Tcl 脚本搭建 Block Design（PS7 + DDR3 + AXI + 自研寄存器组），生成 bit 流与时序报告；"
  "④在 SDK 中开发 ARM 程序，实现寄存器控制、串口命令行与软件基线测量，编译后通过 JTAG 下载；"
  "⑤上板联调，按“点灯 → HDMI 出图 → 四模式正确 → PS 控制生效 → 加速比实测”的顺序逐级验证，"
  "并对每个问题留下完整定位记录。")

# ============================================================== 第二部分
H("第二部分  系统组成及功能说明", 1)

H("2.1  整体介绍", 2)
P("系统整体由 ZYNQ 芯片的两部分协同构成：PS（ARM Cortex-A9 双核、DDR3 控制器、UART 等硬核外设）"
  "负责控制与度量；PL（可编程逻辑）负责视频时序生成、图像滤波与 HDMI 输出。两侧通过 AXI4-Lite 总线"
  "以内存映射寄存器的方式交互，整体框图如图 1 所示。")
IMG(os.path.join(FIG, "fig1_system.png"), 15.5, "图 1  系统总体框图")
P("数据流自上而下贯穿三个层次：")
BULLET("控制层：PC 串口终端 → PS 的 UART0 → ARM 程序 → AXI4-Lite 主机 → 自研寄存器组 axil_regs → "
       "跨时钟域同步 → PL 视频流水线的 mode 输入。这条链路决定了“软件下命令、硬件立即响应”的能力。")
BULLET("数据层：视频时序生成器产生 hs/vs/de 与像素坐标 → 图像源（彩条或照片 ROM）输出 24bit RGB → "
       "源选择器 → 3×3 卷积滤波核 → 输出寄存 → TMDS 编码 → HDMI 差分对。整条链路每个像素时钟推进一个像素。")
BULLET("度量层：滤波输出产生的帧起始脉冲在像素域变换为翻转标志，经同步后在 AXI 域计数，"
       "PS 读取该 32 位计数器并结合私有定时器即可实测硬件帧率，形成“硬件运行、软件观测”的闭环。")
P("值得说明的是三个时钟域的划分：系统晶振 50MHz 经时钟管理单元产生 75MHz（像素）与 375MHz（串行）两个"
  "同步时钟；PS 的 FCLK_CLK0 提供 100MHz 的 AXI 时钟，与像素域完全异步。全部跨域信号均按第 2.2.3 节"
  "所述方案处理。")
P("关于场频的选择需要加以说明。CEA-861 标准中 720p60 格式的像素时钟为 74.25 MHz，对应场频恰为 60.000 Hz；"
  "本设计为便于时钟管理单元做整数倍分频（375 MHz = 75 MHz × 5，供 TMDS 串行化使用），采用 75 MHz 像素时钟，"
  "在 1650×750 的时序参数下对应场频 60.606 Hz，比标准高约 1%，帧周期为 16.50 ms。"
  "该偏差处于显示器通常可接受的 ±2% 同步容差之内，实测长期工作稳定、无失锁与花屏现象。"
  "若需要严格符合 CEA 标准，只需把 MMCM 输出改为 74.25 MHz 并相应调整串行时钟倍频即可。")

H("2.2  硬件系统介绍", 2)

H("2.2.1  硬件整体介绍", 3)
P("硬件平台为一块 XC7Z010-1CLG400C（ZYNQ-7010）开发板，主要资源与配置如下："
  "PS 侧为 ARM Cortex-A9 双核 @667MHz，搭配 512MB DDR3（MT41K128M16，32 位，533MHz）；"
  "PL 侧可用资源为 17600 个 LUT、35200 个触发器、60 个 36Kb 块 RAM 与 80 个 DSP48E1；"
  "板载 50MHz 有源晶振、USB-UART 桥接芯片（CH340）、HDMI 输出接口、JTAG 排针与 QSPI Flash。")
P("系统对外只需三根线缆：12V 电源、JTAG 下载器（USB）与 HDMI 显示器；调试时可再加一根 USB 线连接板载"
  "USB-UART 接口用于串口命令行。启动模式设为 JTAG，便于开发阶段反复下载验证。")
TABLE(
    ["资源", "用量", "占比", "说明"],
    [
        ["Slice LUT", "1527", "8.7%", "滤波加法树、四选一、TMDS 编码"],
        ["Slice Register", "1109", "3.2%", "流水线寄存器与抽头寄存器"],
        ["Block RAM", "32.5 / 60", "54.2%", "320×240 灰度图像 ROM 占主要部分"],
        ["DSP48E1", "1", "1.3%", "Sobel 绝对值前级比较"],
        ["MMCM", "1", "—", "50MHz → 75MHz / 375MHz"],
        ["时序余量 WNS", "+3.447 ns", "—", "75MHz 时钟，无违例"],
    ],
    widths=[3.2, 3.0, 2.4, 5.4],
    caption="表 2  PL 资源与时序"
)

H("2.2.2  机械设计介绍", 3)
P("本作品为纯电子系统，不涉及机械结构设计，故本节从略。实物安装仅涉及开发板固定、HDMI 线缆与下载器"
  "排线的插接，见第三部分实物照片。")

H("2.2.3  电路各模块介绍", 3)
P("系统电路可分为四个功能模块：")
P("（1）供电与启动模块。整板由 12V 直流适配器供电（亦可由 USB 5V 供电），经板载 DC-DC 转换为 3.3V、1.8V、"
  "1.5V、1.0V 等电压；BOOT CFG 拨码设为 ON/ON 时芯片从 JTAG 启动，此时 bit 流与 ARM 程序均由下载器写入，"
  "掉电即失效，适合开发阶段；若量产可将 bit 流固化至 QSPI Flash 实现上电自启动。")
P("（2）时钟模块。50MHz 有源晶振经 MMCM 产生 75MHz 像素时钟与 375MHz 串行时钟（5 倍关系），"
  "同时输出 locked 信号与外部复位键共同构成 PL 复位；PS 侧通过内部 PLL 产生 100MHz 的 FCLK_CLK0 供 AXI 使用。"
  "两套时钟完全独立，构成异步域。")
P("（3）视频输出模块。TMDS 差分对直接由 PL 引脚驱动，无需外部编码芯片：每个通道由 8b/10b 编码器与"
  "OSERDESE2（10:1 DDR 串行化）构成，时钟通道输出 75MHz×5 的串行时钟，三个数据通道分别承载 R/G/B。"
  "该方案节省了 BOM 成本，也把视频接口完全置于设计者控制之下。")
P("（4）调试与通信模块。JTAG 链路用于下载与在线调试；板载 CH340 通过跳线选择接到 PS 的 MIO14/15（UART0）"
  "或 PL 引脚，本作品使用 PS 侧串口，波特率 115200，用于命令行交互。")
P("在 PL 内部，各 RTL 模块的层次关系为：system_top（顶层）实例化 system_wrapper（Block Design：PS7 与 AXI 互联）、"
  "clk_wiz_0（时钟）、cdc_cfg/cdc_frame_cnt（跨域）、key_debounce（按键消抖）、video_pipeline（视频流水线）"
  "与 dvi_transmitter_top（HDMI 发送）；其中 video_pipeline 再实例化 video_timing_gen、test_pattern、"
  "image_rom_src、img_filter_3x3 四个子模块。")

H("2.3  软件系统介绍", 2)

H("2.3.1  软件整体介绍", 3)
P("软件系统运行于 PS 的 ARM Cortex-A9 上，为 Xilinx Standalone 裸机程序，由三部分组成："
  "①硬件抽象层（BSP，由工具根据硬件描述自动生成，提供 UART、定时器、缓存等驱动）；"
  "②应用层 main.c，实现命令行交互、寄存器读写、帧率测量与软件基线调度；"
  "③算法层 sw_filter.c，实现与 RTL 逐条对齐的四种滤波算法，用于软件基线测量。")
P("软件的全部设计目标围绕“协同”二字：既不参与任何像素运算，又能对 PL 施加精确控制并观测其运行状态，"
  "同时提供可比的软件实现以量化加速收益。程序编译采用 Release（-O2）配置，以保证软件基线不被编译器"
  "拖累；这一点在实测中影响巨大（-O0 时单像素耗时高达 1000ns，-O2 后降至 170ns 左右）。")

H("2.3.2  软件各模块介绍", 3)
P("程序主流程如图 2 所示，可分为初始化、自检、命令循环三个阶段：")
IMG(os.path.join(FIG, "fig5_flow.png"), 12.0, "图 2  应用程序流程图")
P("（1）初始化与自检。程序启动后先等待数十毫秒，再向 PL 写入 CTRL=1 与 MODE=3（Sobel），"
  "随后读回 MODE 寄存器进行比对，若不一致则重试，最多 8 次。这一“写-读回-重试”的设计源于真机调试中"
  "发现的现象：若在 PL 侧 AXI 复位尚未释放时立即访问，首次写会被静默丢弃，导致画面停留在模式 0。"
  "自检通过后读取 VERSION 寄存器，若等于 0x00010000 即判定 PL 加载正常并在串口打印确认信息。")
P("（2）命令循环。程序阻塞于 inbyte() 等待串口字符，按字符分发处理："
  "‘0’~‘3’写 MODE 寄存器并读回确认；‘e’/‘d’分别置位与清零 CTRL 实现滤波使能与旁路；"
  "‘h’读取 FRAME_CNT 两次并结合定时器计算帧率；‘c’依次运行四种算法的软件实现并打印耗时；"
  "‘i’打印全部寄存器；‘m’重印菜单。")
P("（3）寄存器映射。软硬件之间仅通过 6 个 32 位寄存器交互，接口定义如表 3。这种极简接口既降低了耦合，"
  "也使 PL 侧逻辑开销极小（寄存器组仅约 60 个触发器）。")
TABLE(
    ["偏移", "名称", "属性", "含义"],
    [
        ["0x00", "CTRL", "R/W", "bit0 = filter_en，1 使能滤波，0 直通原图"],
        ["0x04", "MODE", "R/W", "[2:0] 滤波模式：0 灰度 / 1 均值 / 2 高斯 / 3 Sobel"],
        ["0x08", "THRESH", "R/W", "[7:0] 预留阈值（用于扩展二值化）"],
        ["0x0C", "VERSION", "R", "固定 0x00010000，用于确认 PL 在位"],
        ["0x10", "FRAME_CNT", "R", "PL 输出的 32 位帧计数（跨时钟域同步后）"],
        ["0x14", "STATUS", "R", "保留状态字"],
    ],
    widths=[2.0, 2.6, 1.6, 7.8],
    caption="表 3  AXI4-Lite 寄存器映射"
)
P("（4）帧率与基线测量方法。硬件帧率通过“两次读取帧计数器 + 定时器差分”得到，"
  "由于计数器在 AXI 域本地递增，不存在跨域读取的中间值问题；软件基线则对 320×240 的测试图像执行"
  "与 RTL 完全相同的整数运算（均值用 (Σ×57)>>9 近似除以 9、高斯用 >>4、Sobel 用 |Gx|+|Gy| 并限幅），"
  "计时前先预热并刷新缓存，以保证比较公平。")

# ============================================================== 第三部分
H("第三部分  完成情况及性能参数", 1)

H("3.1  整体介绍", 3 if False else 2)
P("系统已在真实硬件上完成端到端联调：开发板通过 JTAG 下载 bit 流与 ARM 程序后，HDMI 显示器立即输出"
  "720p 画面，串口终端同时打印 PL 版本号与菜单。整机仅需 12V 电源、HDMI 线与下载器三根线缆，"
  "演示时不依赖 PC 上的任何图形界面。")
IMG(os.path.join(PHO, "norm_board.jpg"), 13.5, "图 3  系统实物（开发板 + 串口 + HDMI）")

H("3.2  工程成果", 2)

H("3.2.1  硬件成果", 3)
P("硬件成果主要体现为 PL 内部的完整视频与图像处理系统，其数据通路如图 4 所示。系统自研了视频时序生成器、"
  "彩条图案发生器、图像 ROM 源、3×3 卷积滤波核、AXI4-Lite 从机以及两套跨时钟域模块，"
  "并复用了开源社区的 TMDS 编码与串行化实现。")
IMG(os.path.join(FIG, "fig2_pipeline.png"), 15.5, "图 4  PL 内部视频数据通路")
P("滤波核的内部结构如图 5 所示。为兼顾吞吐与时序，设计把 3×3 卷积拆分为六级流水：坐标计算（S0）、"
  "RGB 转灰度（S1）、行缓存写入与抽头（S2~S3）、抽头寄存（S4）、加法树（S5）、乘移与限幅（S6）。"
  "这一划分使得最长的组合路径仅约 6.5ns，在 75MHz（13.33ns 周期）下留有充足余量。")
IMG(os.path.join(FIG, "fig3_filter.png"), 15.5, "图 5  3×3 卷积滤波核的硬件流水线")

H("3.2.2  软件成果", 3)
P("软件成果为运行于 ARM 上的命令行程序与配套的软件基线库。串口界面如下所示（实际运行输出），"
  "用户可实时切换四种模式并查看寄存器状态与性能数据。")
p = doc.add_paragraph()
p.paragraph_format.left_indent = Pt(24)
p.paragraph_format.space_before = Pt(6)
r = p.add_run(
    "===== ZYNQ-7010 real-time image filter =====\n"
    "  0/1/2/3 : set filter mode (gray/mean/gauss/sobel)\n"
    "  e / d   : filter enable / bypass\n"
    "  h       : measure hardware frame rate\n"
    "  c       : software baseline vs hardware\n"
    "  i       : dump registers\n"
    "> i\n"
    "  CTRL      = 0x00000001     MODE    = 0x00000003\n"
    "  VERSION   = 0x00010000     FRAME_CNT = 0x0000964C")
_set_run(r, 10, ea="Consolas")

H("3.2.3  软硬件协同成果", 3)
P("协同效果可通过两点直接验证：其一，在串口输入字符 ‘0’~‘3’ 时，显示器画面在同一帧内切换模式，"
  "说明命令经 AXI 写入寄存器后立即作用于像素通路；其二，读回的 FRAME_CNT 随时钟稳定递增，"
  "说明 PL 的帧事件已正确同步回 PS。跨时钟域设计如图 6 所示。")
IMG(os.path.join(FIG, "fig4_cdc.png"), 15.0, "图 6  PS 与 PL 的跨时钟域设计")

H("3.3  特性成果", 2)
P("四种滤波模式在真实硬件上的效果如下（同一幅 320×240 源图，显示于 1280×720 屏幕）。"
  "源图为户外石雕龙首照片，包含大量高频纹理，便于体现各算子的差异。")
IMG(os.path.join(PHO, "norm_src.jpg"), 7.5, "图 7  源图像（320×240 灰度，4 倍像素复制放大后满屏显示）")
IMG(os.path.join(PHO, "norm_mode0.jpg"), 13.0, "图 8  模式 0 灰度：亮度信息保留，细节清晰")
IMG(os.path.join(PHO, "norm_mode1.jpg"), 13.0, "图 9  模式 1 均值 3×3：邻域平均，纹理被平滑")
IMG(os.path.join(PHO, "norm_mode2.jpg"), 13.0, "图 10  模式 2 高斯 3×3：加权平均，过渡更自然")
IMG(os.path.join(PHO, "norm_mode3.jpg"), 13.0, "图 11  模式 3 Sobel：提取全部边缘，龙鳞与树叶纹理被勾勒成亮线")
P("从结果可以看到：均值与高斯使高频纹理明显柔化，且高斯的高斯核保留了更多主体轮廓；"
  "Sobel 则将平滑区域压暗、把梯度大的位置点亮，龙首轮廓、鳞片边缘与背景枝叶被清晰分离。"
  "四种模式共用同一套行缓存与抽头电路，切换由末级四选一选择器完成，因此切换瞬间无花屏、无延迟。")
P("性能方面，软件与硬件的单像素耗时对比如图 12 的柱状图所示：四种算法的软件实现在 166~178 ns/像素，"
  "而硬件恒为 13.33 ns/像素，加速比约 13 倍。更关键的是实时性差异：硬件处理整帧 921600 像素仅需 12.29 ms，"
  "可在 16.50 ms 的帧周期内完成并留有 4.21 ms 余量；软件处理同样一帧需要 153 ms，比实时差 9.3 倍，"
  "即使完全不考虑 CPU 还需承担其他任务，也无法满足 60fps 的刚性要求。")
IMG(os.path.join(FIG, "fig6_speed.png"), 15.0,
    "图 12  四种滤波模式的单像素耗时对比（柱状图，同一算法、同一帧，板上实测）")
P("图 12 直观呈现了二者的数量级差距；表 4 则进一步给出整帧耗时与“能否满足 16.50 ms 帧周期”的判断，"
  "二者互为补充：前者便于快速把握差距，后者便于查证具体数值与实时性结论。")
TABLE(
    ["滤波模式", "软件 (-O2)", "硬件", "加速比", "软件处理 720p 一帧", "能否实时"],
    [
        ["灰度", "166 ns/px", "13.33 ns/px", "12.5×", "153 ms", "否"],
        ["均值 3×3", "177 ns/px", "13.33 ns/px", "13.3×", "163 ms", "否"],
        ["高斯 3×3", "174 ns/px", "13.33 ns/px", "13.1×", "160 ms", "否"],
        ["Sobel", "178 ns/px", "13.33 ns/px", "13.4×", "164 ms", "否"],
        ["硬件（任意模式）", "—", "13.33 ns/px", "—", "12.29 ms", "是"],
    ],
    widths=[3.0, 2.6, 2.6, 1.8, 2.6, 1.4],
    caption="表 4  软硬件性能对比与实时性判断（同一算法、同一帧，板上实测）"
)
P("此外，系统在连续运行中保持稳定：帧计数无丢帧、无跳变，CPU 占用率始终接近 0，"
  "说明像素级运算已完全从处理器卸载到可编程逻辑，PS 可专心处理上层逻辑。")

# ============================================================== 第四部分
H("第四部分  总结", 1)

H("4.1  可扩展之处", 2)
P("本作品已完整验证了“PS 控制 + PL 计算”的实时图像处理架构，后续可在四个方向继续扩展："
  "①图像源升级：接入 OV5640 等摄像头模组，或通过 AXI-DMA/VDMA 从 DDR 读取任意分辨率图像，"
  "摆脱片上 ROM 容量限制；②算子扩展：在现有流水线后级串联中值滤波、二值化、形态学与 Canny，"
  "构成完整的视觉前处理链；③功能增强：把帧率、模式、加速比等数据以字符叠加（OSD）方式直接绘制在画面上，"
  "脱离串口也能观测；④系统集成：将 bit 流固化到 QSPI Flash 实现上电自启动，并加入多路视频输入与"
  "乒乓缓存，向多通道实时处理平台演进。")

H("4.2  心得体会", 2)
P("这个项目从零开始，最终在一块 ZYNQ-7010 上跑通了完整的软硬件协同图像处理系统。回顾整个过程，"
  "最大的收获不是“做出了一块板子能跑的 demo”，而是对“仿真通过不等于硬件正确”这句话建立了切身体会。")
P("第一，硬件设计必须用“最坏时序”去验证。滤波核最初把 RGB 转灰度、行缓存地址计算与乘法全部压在一拍内，"
  "综合后关键路径达 15ns，75MHz 下无法收敛；把运算拆成六级流水后余量立刻充裕。更隐蔽的是另一个问题："
  "均值模式在行为仿真中完全正确，上板却整屏变黑。用综合后网表重新仿真才发现，"
  "“sum×57 后取高 9 位”这种只使用部分位宽的乘法写法被工具做了位宽优化，导致结果恒为 0。"
  "把它改成纯移位加法（57 = 32+16+8+1）后，行为仿真与网表仿真结果完全一致。这件事让我明白："
  "凡是依赖工具推断的写法，都应该在综合后仿真中复核一遍。")
P("第二，接口协议要逐字读，不能想当然。AXI4-Lite 从机的第一版把写操作实现为“AWVALID 与 WVALID 同时有效"
  "才执行”，这在我的 testbench 里工作得很好，因为测试激励恰好让地址和数据同拍到达。但在真机上，"
  "Zynq 的 AXI 主机允许两者分离到达，结果写操作被静默丢弃、BVALID 永不拉高，ARM 在第一条 Xil_Out32 上"
  "就永久阻塞——表现为串口一个字都不输出、LED 全灭、画面不变，看上去像“程序没跑”，实际是“程序卡死”。"
  "后来把从机改成地址与数据各自独立锁存，并给 testbench 补上“地址先到”“数据先到”两种时序的回归用例，"
  "同时把激励改为下降沿驱动、上升沿采样，问题彻底解决。这个 bug 让我真正理解了“协议”二字的分量。")
P("第三，跨时钟域是软硬件协同的必答题。系统里有 75MHz 像素域与 100MHz AXI 域两个异步域，"
  "配置信号用双触发器同步即可，但帧计数器若直接跨域读取，可能读到进位中间值。"
  "作品采用“像素域翻转标志 + 同步器 + AXI 域边沿检测 + 本地计数”的方案，代价是几个时钟周期的延迟，"
  "换来的是绝对可靠。同时必须给工具正确的约束：不加 set_clock_groups 时，工具会把跨域路径当作同步路径分析，"
  "报出 -0.29ns 的假违例，让人误以为设计有问题。")
P("第四，与硬件打交道时，现象与原因之间往往隔着好几层。调试期间还遇到过两类“看起来像代码问题、"
  "其实是环境问题”的情况：一是 Vivado 的 Program Device 对话框无法处理中文路径，会把路径中的中文字符"
  "吃掉，导致“文件不存在”；二是板载 USB-UART 跳线默认接在 PL 侧而非 PS 侧，"
  "使 PS 的串口输出完全无法到达电脑。前者教会我把所有给工具读写的路径统一放在纯英文目录，"
  "后者教会我在怀疑代码之前先确认物理连接。类似地，xil_printf 不支持 %f 导致所有浮点数据打印为空、"
  "Debug(-O0) 构建让软件基线慢了六倍,这些都属于“先确认工具与环境，再怀疑算法”的经验。")
P("第五，工程化与可复现同样重要。整个项目从第一天起就用 Tcl 脚本构建、用脚本生成位流与 ARM 程序，"
  "所有验证都有对应的 testbench 与预期输出。当出现“某次构建通过、下一次却失败”时，"
  "脚本化的流程让问题定位变成“对比两次日志”，而不是“凭记忆重来一遍”。最终交付的仓库可以在干净的"
  "环境中从源码重建全部产物，这既是比赛要求，也是对工程能力的训练。")
P("最后，这个项目让我对“分工”有了更具体的认识：FPGA 擅长的是确定性的、数据密集的、"
  "可流水化的运算；处理器擅长的是控制、决策与不规则逻辑。把 3×3 卷积交给 PL 后，"
  "CPU 占用从接近 100% 降到 0，而 13 倍的加速只是副产品，真正的价值在于系统获得了确定性的实时能力。"
  "我想，这就是软硬件协同设计最朴素也最有说服力的意义。")

# ============================================================== 第五部分
H("第五部分  参考文献", 1)
refs = [
    "[1] Xilinx Inc. Zynq-7000 SoC technical reference manual: UG585 (v1.12.2)[Z]. "
    "San Jose: Xilinx Inc., 2018.",
    "[2] ARM Ltd. AMBA AXI and ACE protocol specification: ARM IHI 0022E[S]. "
    "Cambridge: ARM Ltd., 2013.",
    "[3] Xilinx Inc. 7 series FPGAs SelectIO resources user guide: UG471 (v1.10)[Z]. "
    "San Jose: Xilinx Inc., 2017.",
    "[4] Xilinx Inc. Vivado design suite user guide: using constraints: UG903 (v2018.3)[Z]. "
    "San Jose: Xilinx Inc., 2018.",
    "[5] GONZALEZ R C, WOODS R E. Digital image processing[M]. 4th ed. "
    "New York: Pearson, 2018.",
]
for i, t in enumerate(refs):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Pt(24)
    p.paragraph_format.first_line_indent = Pt(-24)
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run(t)
    _set_run(r, 10.5)

doc.save(OUT)
print("saved:", OUT)
print("paragraphs:", len(doc.paragraphs), " tables:", len(doc.tables))

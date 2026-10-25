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
OUT  = os.path.join(HERE, "design_report_v5.docx")

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
r = p.add_run("基于 ZYNQ-7010 的软硬件协同实时图像处理与叶片病斑检测系统")
_set_run(r, 20, bold=True, ea=EA_H)


# ============================================================== 摘要
H("摘要", 1)
P("作物病害的早期识别依赖对叶片表面细小病斑的定位与计数，这类任务的两个难点是：一是“像素级”的形态学"
  "与邻域运算量巨大，若由通用处理器逐像素执行，单帧耗时远超人眼可接受的延迟；二是“判定规则”需要"
  "在现场按品种、光照与拍摄条件反复调整。本作品基于 Xilinx ZYNQ-7010 全可编程 SoC，设计并实现了一套"
  "软硬件协同的实时图像处理与叶片病斑检测系统，把这两类任务分别交给最合适的部件。")
P("系统采用“PS 搬运与预处理、PL 逐像素判断”的分工。PS（双核 Cortex-A9）从 DDR 中的 24 张 256×256 "
  "彩色叶片样本读取图像，做 3×3 均值平滑后经 AXI4-Lite 分块上传；PL 内一块独立的检测状态机在 100 MHz "
  "下依次完成灰度化与亮度量化、31×31 灰度闭运算背景估计、局部对比度提取、叶片掩膜、连通域标记、"
  "候选验证与排序去重，在帧边界输出最多 32 个病斑框；画框器在像素流上用比较器实时叠加红色矩形，"
  "与 1280×720@60 的 TMDS 视频通路同源输出，全程不占用 CPU。")
P("系统同时保留了完整的图像处理平台能力：PL 内的 3×3 卷积流水线支持灰度、均值、高斯与 Sobel 四种算子，"
  "两条行缓冲加九个抽头寄存器的结构使吞吐恒为每时钟 1 像素，整帧 921600 像素仅需 12.29 ms，"
  "在 16.50 ms 的帧周期内留有 4.21 ms 余量，滤波期间 CPU 占用率约为 0%，较 ARM 上的优化 C 实现提速约 13 倍。")
P("病斑检测的实测结果为：在 24 张开发样本、85 个人工标注病斑上（IoU 门限 0.5、一对一匹配），"
  "病斑召回率 72.94%、预测精确率 93.94%、每图平均误框 0.17 个；12 张健康样本全部未产生误框。"
  "第 13 张样本的 PL 检测耗时 83.1 ms，含 PS 预处理与传图的完整流程 116.0 ms。"
  "整板资源占用 LUT 13821、FF 8303、BRAM 60 块、DSP 11 个，时序收敛（setup +0.131 ns、hold +0.038 ns），"
  "未放宽任何约束。")
p = doc.add_paragraph()
p.paragraph_format.space_before = Pt(6)
r = p.add_run("关键词：")
_set_run(r, 12, bold=True, ea=EA_H)
r = p.add_run("ZYNQ；软硬件协同；图像处理；叶片病斑检测；形态学；连通域标记；AXI4-Lite；实时视频")
_set_run(r, 12)

# ============================================================== 第一部分
H("第一部分  作品概述", 1)

H("1.1  功能与特性", 2)
P("本作品在一块常见的 ZYNQ-7010 开发板上，实现了“实时图像处理平台 + 叶片病斑检测应用”两层功能，"
  "全部由板载 PS 与 PL 协同完成，运行时不依赖任何上位机。")
BULLET("病斑检测与标注（核心功能）：内置 24 张 256×256 彩色叶片样本（12 张健康、12 张早疫病），"
       "PL 内独立完成病斑分割、连通域分析与候选验证，在 1280×720 画面上以红色矩形标注病灶，"
       "最多可同时输出 32 个目标框。")
BULLET("四种实时滤波：灰度（BT.601 加权）、均值 3×3、高斯 3×3 与 Sobel 边缘检测全部在 PL 内以"
       "每拍一个像素的速率完成，运行中零延迟切换，用于展示平台的通用处理能力。")
BULLET("人机交互：串口命令行可切换样本、开关红框、在线调整褐色阈值、一键批量统计；"
       "板上按键可在不接触电脑的情况下循环切换四种滤波模式。")
BULLET("性能自测：PS 可读取 PL 的 32 位帧计数器结合片内定时器实测帧率，并内置与硬件逐条对齐的"
       "C 语言软件基线，在同一帧上对比软硬件耗时、自动计算加速比。")

H("1.2  应用领域", 2)
P("本作品解决的是“嵌入式设备上对图像做逐像素判断”这一共性问题，可直接迁移到以下场景：")
BULLET("作物病害与虫害检测：叶片病斑、霉层、虫咬孔的定位与计数，用于分级分选、施药决策与长势监测。")
BULLET("工业表面缺陷检测：划痕、污点、缺焊等小目标在产线节拍内的定位，要求确定性延迟与稳定帧率。")
BULLET("医学与显微影像：细胞计数、斑点定量分析等需要形态学与连通域处理的场合。")
BULLET("低功耗边缘设备：农业无人机、便携检测仪等供电受限的场景，把像素级运算卸载到可编程逻辑可显著降低"
       "主控负载与整机功耗。")
P("这些场景的共同特征是“像素率高、算子局部、实时性刚性、参数需现场可调”，正是可编程逻辑与处理器"
  "协同工作的优势区间。")

H("1.3  主要技术特点", 2)
P("（1）把形态学与连通域做成确定性硬件状态机。检测器不使用处理器逐像素循环，而是用固定状态机按扫描顺序"
  "推进，同一张图的耗时与结果完全可复现，不受调度与缓存影响；连通域采用“有界洪泛前沿 + FIFO”实现，"
  "不需要整帧标记内存，在片内 BRAM 已占满的条件下仍能完成标记与排序。")
P("（2）大窗口运算的可分离化。31×31 灰度闭运算若逐像素读取邻域，需要约 1.26 亿次取样；本作品利用正方形"
  "结构元素可精确分解的性质，将其改写为“横向最大值 → 纵向最大值 → 横向最小值 → 纵向最小值”四条扫描线，"
  "窗口历史只用 30 项移位寄存器保存，单帧耗时由 3939 ms 降至 172.6 ms（22.8 倍），且判定结果与原实现逐像素一致。")
P("（3）双层验证体系：算法先在 PC 上用 Python 建立整数参考模型，再生成 RTL 逐像素向量，最终在板上逐框比对。"
  "评估不止于“这张图判为有病”，而是对人工标注的 85 个病斑按 IoU 0.5 一对一匹配统计 TP/FP/FN，"
  "并同时给出源图坐标与 HDMI 投影两套结果，避免用理想浮点框抬高小目标的指标。")
P("（4）严格的跨时钟域设计。系统内存在 50 MHz 晶振、75 MHz 像素、375 MHz 串行与 100 MHz AXI 共四个时钟域；"
  "配置信号采用两级触发器同步并标注 ASYNC_REG，检测结果使用“数据总线 + 提交翻转位”在帧边界整体锁存，"
  "并用 set_clock_groups 与 set_max_delay 正确约束异步路径，工具既不误报违例也不过度优化。")
P("（5）工程可复现。全部设计由 Tcl 脚本从源码重建（Block Design、综合、实现、bit、HDF、ARM 程序），"
  "配套 8 个仿真 testbench 与板级自动核对脚本，构建入口会强制检查 setup/hold 后才发布 bit 流。")

H("1.4  主要性能指标", 2)
TABLE(
    ["指标", "数值", "说明"],
    [
        ["输出分辨率 / 场频", "1280×720，60.6 Hz", "75 MHz÷1650÷750，显示器实测稳定"],
        ["病斑召回率", "72.94%", "85 个人工标注病斑，IoU 0.5"],
        ["病斑预测精确率", "93.94%", "每图平均误框 0.17 个"],
        ["健康样本误框", "0 个", "12 张健康叶片全部无误框"],
        ["PL 检测耗时", "83.1 ms", "第 13 张，100 MHz 状态机"],
        ["检测完整流程", "116.0 ms", "PS 预处理 + 上传 + PL 检测 + 读回"],
        ["滤波吞吐", "13.33 ns/像素", "每拍 1 像素，CPU 占用 ≈0%"],
        ["滤波整帧耗时", "12.29 ms", "921600 像素，较软件提速约 13 倍"],
        ["时序", "setup +0.131 ns / hold +0.038 ns", "未放宽约束"],
        ["资源占用", "LUT 13821 / FF 8303 / BRAM 60 / DSP 11", "XC7Z010-1CLG400C"],
        ["整机功耗", "约 2.6 W", "12 V 供电，整板实测"],
    ],
    widths=[4.2, 5.2, 5.0],
    caption="表 1  主要性能指标"
)

H("1.5  主要创新点", 2)
BULLET("把“大窗口形态学 + 连通域 + 多条件验证”整链下沉到 PL，用确定性状态机实现，检测过程零 CPU 占用，"
       "同一图像的结果与耗时可完全复现。")
BULLET("用可分离扫描线实现 31×31 闭运算，在片内 BRAM 已占满、无法新增整帧缓存的约束下，把大窗口运算"
       "加速 22.8 倍，并与参考实现逐像素等价。")
BULLET("以“颜色核心计数 + 四侧绿色组织支持 + 形状约束”的组合判据替代单一灰度阈值，"
       "使暗背景与叶脉阴影不被误判为病斑，12 张健康样本实现零误框。")
BULLET("自研 AXI4-Lite 从机采用地址/数据独立锁存结构，严格满足 AW 与 W 可分离到达的时序要求，"
       "避免了“同拍到达”错误实现导致主机永久阻塞的典型故障。")
BULLET("建立“Python 参考 → RTL 逐像素 → 板卡逐框”三层验证与自动核对流程，构建入口强制时序检查后才发布，"
       "使结论可复现、可追溯。")

H("1.6  设计流程", 2)
P("设计按“算法离线验证 → RTL 逐像素比对 → 板级逐框核对”三步推进：先在 PC 上用 Python 建立整数参考模型，"
  "在人工标注集上确定判据；再把规则翻译为 Verilog 状态机，用逐像素向量与参考模型比对；"
  "最后通过 JTAG 下载到板卡，用串口读回全部框坐标与参考结果逐框核对，并复测时序与资源。"
  "整条链路由脚本驱动，任一环节不一致都会中断发布。")
IMG(os.path.join(FIG, "fig4_cdc.png"), 14.5, "图 1  跨时钟域与结果提交流程")

# ============================================================== 第二部分
H("第二部分  系统组成及功能说明", 1)

H("2.1  整体介绍", 2)
P("系统由 ZYNQ-7010 开发板、HDMI 显示器与 12 V 电源构成，无其他外部设备。芯片内部按功能划分为三部分："
  "PS（ARM Cortex-A9 + DDR3 控制器 + MIO 串口）负责图像搬运、预处理与命令解析；PL 负责视频时序生成、"
  "滤波流水线、病斑检测状态机与画框；两者之间通过 AXI4-Lite 寄存器与两个异步时钟域交互。"
  "整体结构如图 2 所示。")
IMG(os.path.join(FIG, "fig7_detector.png"), 15.0, "图 2  系统总体框图（PS 预处理 → PL 检测 → 画框输出）")
P("数据流可以概括为：DDR 中的样本 → PS 平滑与分块上传 → PL 检测器给出病斑框 → cdc_boxes 在帧边界锁存 → "
  "画框比较器叠加红色矩形 → TMDS 编码 → HDMI 显示。整条链路中，PS 只搬运与预处理，"
  "所有逐像素判断与显示都在 PL 内完成。")

H("2.2  硬件系统介绍", 2)
P("硬件部分完全基于开发板板载资源，未增加任何外设模块，是一套自包含的嵌入式系统。")
H("2.2.1  硬件整体介绍", 3)
P("主控为 Xilinx XC7Z010-1CLG400C（28 nm，双核 Cortex-A9 @667 MHz + 约 28K 逻辑单元），"
  "板载 MT41K128M16 512 MB DDR3 与 50 MHz 晶振。PL 侧共用 17600 个 LUT、35200 个触发器、60 块 BRAM36 "
  "与 80 个 DSP48；外部接口仅使用 50 MHz 时钟输入、JTAG、PS 的 MIO14/15 串口与 4 对 TMDS 差分输出，"
  "显示器通过板载 HDMI 接口直连，不经过任何视频编码芯片。")
H("2.2.2  机械设计介绍", 3)
P("作品为板卡级原型，未做机械结构件。为保证演示稳定，实际使用时将开发板固定于绝缘垫上，"
  "12 V 电源、JTAG 排线与 HDMI 线分别从板卡三侧引出，避免线缆受力牵扯板卡；"
  "显示器置于板卡正前方，便于同时观察画面与串口输出。")
H("2.2.3  电路各模块介绍", 3)
P("PL 内部按数据流划分为五个模块：①视频时序发生器，产生 1280×720@60（H_TOTAL 1650、V_TOTAL 750）"
  "的行场同步与数据有效信号；②图像缓冲 img_buf，为双端口 RAM，A 口供显示通路在 75 MHz 像素域读取，"
  "B 口供 PS 在 100 MHz AXI 域写入，实现“运行中换图”；③3×3 卷积流水线，两条行缓存 + 九个抽头寄存器 + "
  "四组并行加法树，支持灰度/均值/高斯/Sobel 四种算子，如图 3 所示；④病斑检测器 pl_pest_detector，"
  "独立状态机，完成形态学、连通域与验证；⑤TMDS 发送器，用 OSERDESE2 做 10:1 DDR 串行化并输出差分信号。")
IMG(os.path.join(FIG, "fig3_filter.png"), 15.0, "图 3  3×3 卷积滤波核的硬件流水线（四种算子共享行缓存与抽头）")
P("图像缓冲与检测器共享片内 BRAM：两块 9 bit 帧 RAM 同时承担“灰度背景”“掩膜/中间结果”的存储，"
  "通过分时复用避免新增整帧缓存；这也是本作品能在 BRAM 60/60 全部占满的情况下仍完成检测的关键约束。")
H("2.2.4  视频通路与画框", 3)
P("显示通路的输出延迟固定为 12 拍像素时钟（160 ns）。病斑框不参与卷积，而是由画框模块在滤波后的像素流上"
  "用比较器判断“当前坐标是否落在某个框的边框带上”，命中即输出红色。因此标注框边缘锐利、不随滤波模式变化，"
  "且不额外消耗带宽。")

H("2.3  软件系统介绍", 2)
H("2.3.1  软件整体介绍", 3)
P("PS 端为裸机 C 程序（无操作系统），编译后与 24 张样本一起构成约 4.7 MB 的 ELF，经 JTAG 载入 DDR。"
  "程序主体是一个串口命令行循环，按功能分为四层：样本管理（切换、重检、批量统计）、预处理与上传"
  "（3×3 均值 + AXI 分块写）、结果处理（读回框坐标并换算为屏幕坐标）、自检与报告"
  "（帧率、加速比、寄存器状态）。")
H("2.3.2  软件各模块介绍", 3)
P("① 预处理模块：对 256×256 彩色样本做 3×3 均值，抑制叶片表面噪声，再把结果按 32 位字分块写入 PL 的"
  "上传寄存器；同时生成 320×240 的显示用灰度图，保证屏幕与检测使用同一幅图像。")
P("② 命令模块：`n`/`b` 切换样本、`p` 重检、`o` 开关红框、`s` 批量统计混淆矩阵、"
  "`[`/`]` 在线调整褐色阈值（改后自动重检）、`0`~`3` 切换滤波模式、`i` 打印全部寄存器。")
P("③ 结果处理模块：把 PL 输出的框坐标（源图坐标）按显示网格换算为屏幕坐标，并做整数边界收敛，"
  "避免小目标因放大取整而偏移。")
P("④ 自检模块：读取 32 位帧计数器与片内定时器实测帧率，运行与硬件逐条对齐的软件基线并计算加速比。")
TABLE(
    ["偏移", "名称", "方向", "说明"],
    [
        ["0x00", "CTRL", "R/W", "bit0 = 滤波使能"],
        ["0x04", "MODE", "R/W", "滤波模式：0 灰度 / 1 均值 / 2 高斯 / 3 Sobel"],
        ["0x08", "THRESH", "R/W", "褐色阈值（在线可调）"],
        ["0x0C", "VERSION", "R", "硬件版本号（PS 用于确认 PL 在位）"],
        ["0x10", "FRAME_CNT", "R", "帧计数（跨时钟域同步后）"],
        ["0x20", "IMG_ADDR", "R/W", "图像缓冲区字节地址"],
        ["0x24", "IMG_DATA", "W", "写入 4 字节并自动地址 +4"],
        ["0x28", "BOX_*", "R/W", "病斑框坐标（每框 2 个 32 位字）"],
        ["0x70", "BOX_CTRL", "W", "画框使能 + 提交翻转"],
    ],
    widths=[2.2, 3.6, 2.2, 6.4],
    caption="表 2  AXI4-Lite 寄存器映射（节选）"
)

# ============================================================== 第三部分
H("第三部分  完成情况及性能参数", 1)

H("3.1  整体介绍", 2)
P("系统已完成从 RTL 到板级演示的全链路调试：bit 流与 ARM 程序经 JTAG 下载后可独立运行，"
  "HDMI 稳定输出 1280×720@60 画面，串口命令行响应正常，病斑标注与四种滤波模式均可现场切换。"
  "实物如图 4 所示。")
IMG(os.path.join(PHO, "norm_board.jpg"), 12.0, "图 4  系统实物（开发板 + JTAG 下载器 + HDMI + 串口）")

H("3.2  工程成果", 2)
H("3.2.1  机械成果", 3)
P("本作品为板卡级原型，未设计机械结构件；实物装配以“稳定、可复现”为原则：板卡平放于绝缘垫，"
  "电源、JTAG 与 HDMI 三侧走线分离，显示器正对操作者，便于同时观察画面与串口。")
H("3.2.2  电路成果", 3)
P("硬件为单板系统，未制作自制 PCB；所有电路为板载资源的使用与约束配置，包括 50 MHz 时钟输入、"
  "TMDS 差分对引脚约束与时序约束。板级调试中遇到的“串口无输出”问题最终定位为底板跳线接在 PL 侧而非 PS 侧，"
  "属硬件配置问题，已在文档中记录排查方法。")
H("3.2.3  软件成果", 3)
P("软件成果包括：一套完整的裸机 C 程序（样本管理、预处理上传、命令解析、自检统计）；"
  "一套可在 PC 上复现的离线评估工具链（整数参考模型、逐像素向量生成、板级逐框核对脚本）；"
  "以及构建入口脚本——它会在实现后强制检查 setup/hold，只有时序通过才发布 bit 流。"
  "串口命令行以单字符命令交互，便于现场快速演示，全部输出为整数格式以适配裸机打印。")
P("串口典型输出如下（一次样本切换）：屏幕切换到第 13 张病叶，串口打印“样本序号 / 病害判定 / "
  "检测框数量 / PL 周期数”，并把框坐标回读用于与参考模型核对。")

H("3.3  特性成果", 2)
P("（1）健康样本零误框。12 张健康叶片在全部 24 张批量测试中均未产生任何标注框，如图 5 所示——"
  "画面只有叶片本身，没有任何红色矩形。这一结果说明“颜色核心 + 四侧组织支持”的组合判据"
  "能有效排除叶脉、阴影与背景。")
IMG(os.path.join(PHO, "实验结果图像", "IMG_20261025_162200.jpg"), 12.5,
    "图 5  健康样本：不产生任何标注框")
P("（2）病叶病灶被逐处框出。第 13 张病叶的检测结果如图 6 所示：叶片上的坏死斑被红色矩形逐处圈出，"
  "框边界与病灶轮廓贴合，画面其余区域（包括叶片下部的深色阴影）未被误框。")
IMG(os.path.join(PHO, "实验结果图像", "IMG_20261025_162245.jpg"), 12.5,
    "图 6  病叶样本：坏死斑被逐处标注（PL 硬件比较器绘制）")
P("（3）定位精度可量化。为避免“只看框数”的主观评价，本作品对 24 张样本人工标注了 85 个病斑框，"
  "按 IoU 0.5 一对一匹配统计，结果如表 3 所示；图 7 给出同一张样本在两种判定规则下的标注对照。")
IMG(os.path.join(FIG, "fig8_detect_result.jpg"), 15.0,
    "图 7  同一张样本的标注对照（左：4 框版本；右：7 框版本）")
TABLE(
    ["指标", "数值", "说明"],
    [
        ["源图 TP / FP / FN", "62 / 4 / 23", "85 个人工标注病斑，IoU 0.5 一对一匹配"],
        ["病斑召回率", "72.94%", "62 / 85"],
        ["预测精确率", "93.94%", "62 / 66"],
        ["每图平均误框", "0.17 个", "4 / 24"],
        ["HDMI 投影 TP / FP / FN", "61 / 5 / 24", "按显示网格整数坐标投影后评估"],
        ["健康样本误框", "0 个", "前 12 张健康样本均未产生框"],
    ],
    widths=[4.2, 4.0, 6.0],
    caption="表 3  病斑级检测指标（24 张开发样本 + 人工标注）"
)
P("（4）检测性能与资源。检测器把整帧扫描拆成确定性状态机，单张图的最长检测流程如表 4 所示；"
  "由于片内 BRAM 已全部占用（60/60），后续优化只能走“减少重复扫描”的路线，例如把二值形态学的逐像素"
  "九邻域读取改为行缓冲滑动窗口、以及对同一张图的重复检测复用显示缓冲。")
TABLE(
    ["项目", "数值", "说明"],
    [
        ["PL 检测（第 13 张）", "83.1 ms", "100 MHz AXI 时钟域，独立状态机"],
        ["检测完整流程", "116.0 ms", "PS 预处理 + 上传 + PL 检测 + 读回"],
        ["首次切图完整流程", "255.1 ms", "额外包含显示图生成与上传"],
        ["24 张最慢检测流程", "537.5 ms", "含 PS 预处理与传图，不含切图渲染"],
        ["时序", "setup +0.131 ns / hold +0.038 ns", "未放宽约束、未加多周期例外"],
        ["资源", "LUT 13821 / FF 8303 / BRAM 60 / DSP 11", "XC7Z010-1CLG400C"],
    ],
    widths=[4.2, 5.6, 4.4],
    caption="表 4  检测性能与资源（板上实测）"
)
P("（5）滤波平台的通用能力。四种 3×3 算子共享同一套行缓存与抽头电路，实测单像素耗时 13.33 ns、"
  "整帧 12.29 ms，CPU 占用接近 0；同一算法在 ARM 上以 -O2 优化编译后单像素仍需 166~178 ns，"
  "硬件提速约 13 倍，且软件处理完整 720p 帧需 153 ms、比实时差 9.3 倍。")
IMG(os.path.join(FIG, "fig6_speed.png"), 14.5,
    "图 8  四种滤波模式的单像素耗时对比（同一算法、同一帧，板上实测）")
P("（6）稳定复现。检测器为确定性状态机，同一张图重复检测的框数与坐标完全一致；"
  "板级回归脚本会对全部 24 张逐一比对框数、坐标、面积与顺序，任一不一致即中断发布。")

# ============================================================== 第四部分
H("第四部分  总结", 1)

H("4.1  可扩展之处", 2)
P("①图像源升级：接入 OV5640 等摄像头模组，或通过 AXI-DMA/VDMA 从 DDR 读取任意分辨率图像，"
  "摆脱片上样本限制；②速度优化：把二值形态学的逐像素九邻域读取改为行缓冲滑动窗口（静态估算可省去"
  "六遍扫描中的大部分周期），并对同一张图的重复检测复用显示缓冲；③精度提升：扩充并标注更多真实样本，"
  "把病斑检测从“框级定位”推进到“像素级分割”，并引入近红外通道与叶片姿态归一化改善暗背景小目标召回；"
  "④工程化：接入千兆网口或 SD 卡实现运行时换图，把 bit 流固化到 QSPI Flash 实现上电自启动。")

H("4.2  心得体会", 2)
P("这个作品从一块点不亮的开发板开始，最后变成一套能自己看图、自己判断、自己标注的完整系统。"
  "回顾整个过程，真正有价值的收获不在“用上了哪些技术”，而在于几次被现实纠正的过程。")
P("第一件事是学会怀疑“仿真通过”。AXI 从机的第一版在 testbench 里一切正常，写到板上却让 ARM 直接卡死——"
  "因为我在从机里要求地址和数据同一拍到达，而真机的主机会分两拍发。行为仿真跑得通，说明仿真激励本身"
  "写错了假设；从那以后我养成了“按最坏时序造激励”的习惯。类似地，均值滤波第一版用了一处乘法，"
  "综合器把它推断成 DSP 乘法器后结果全黑，行为仿真却毫无异常，最后是靠综合后仿真才发现。")
P("第二件事是学会把“结果对不对”变成可量化的东西。早期我满足于“屏幕上出现了红框”，"
  "但框到底准不准、漏了多少、误了多少，完全说不清。后来对 24 张样本人工标注了 85 个病斑，"
  "按 IoU 0.5 一对一匹配统计，才有了召回率、精确率和每图误框这些能写进报告、也能被质疑的数字。"
  "过程中还发现过“图像级准确率”会掩盖定位问题——一张图判对并不代表框画对了，指标口径本身就是设计的一部分。")
P("第三件事是学会接受约束下的取舍。片内 BRAM 只有 60 块，检测器把两块 9 bit 帧 RAM 复用到极致，"
  "代价是无法再增加整帧缓存；31×31 的闭运算最初逐像素读邻域，一帧要近 4 秒，改成可分离扫描后降到 172 ms。"
  "这些改动都不是“更先进的算法”，而是在明确约束下找到了可行的工程路径。")
P("第四件事是理解软硬件分工的边界。把检测放进 PL 以后，CPU 占用降到接近 0，但检测耗时反而从毫秒级"
  "变成了百毫秒级——因为状态机按扫描顺序逐像素推进，是“确定性”换“并行度”。这让我明白："
  "“放到硬件里就更快”是错的，正确的问法是“这个算法能不能并行”。滤波每个像素独立，天然适合流水线；"
  "而连通域标记是数据相关的串行过程，硬件的优势要靠有界洪泛、排序去重这些巧妙的数据结构来换。")
P("最后是工程习惯。串口没输出查了两天，最后发现是底板跳线接在 PL 侧而不是 PS 侧；"
  "中文路径会让 Vivado 报出各种难以定位的错误；这些坑都被记进了文档。把踩过的坑写下来、"
  "把构建做成一条命令、把每次发布都过一遍时序检查，这些看起来“不酷”的事情，"
  "恰恰是让作品能从“我电脑上能跑”变成“别人也能跑”的关键。")

# ============================================================== 第五部分
H("第五部分  参考文献", 1)
refs = [
    "[1] Xilinx Inc. Zynq-7000 SoC technical reference manual: UG585 (v1.12.2)[Z]. San Jose: Xilinx Inc., 2018.",
    "[2] ARM Ltd. AMBA AXI and ACE protocol specification: ARM IHI 0022E[S]. Cambridge: ARM Ltd., 2013.",
    "[3] Xilinx Inc. 7 series FPGAs SelectIO resources user guide: UG471 (v1.10)[Z]. San Jose: Xilinx Inc., 2017.",
    "[4] Xilinx Inc. Vivado design suite user guide: using constraints: UG903 (v2018.3)[Z]. San Jose: Xilinx Inc., 2018.",
    "[5] GONZALEZ R C, WOODS R E. Digital image processing[M]. 4th ed. New York: Pearson, 2018.",
]
for t in refs:
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    r = p.add_run(t)
    _set_run(r, 10.5)

# ============================================================== 保存
doc.save(OUT)
print("saved:", OUT)
print("paragraphs:", len(doc.paragraphs), " tables:", len(doc.tables), " figures:", len(doc.inline_shapes))

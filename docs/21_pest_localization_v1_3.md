# 病灶红框修改记录与上板验证（2026-10-24）

本轮修改 PS 算法和下载脚本，PL 寄存器接口不变。测试输入直接读取
`ps_app/pv_samples.h` 中已经烧录的 24 张 RGB 图片，保持原样本顺序和标签，未重新挑图。
翻拍照片仅用于观察显示问题，不作为颜色分割输入。

## 第一步：修复坐标边界

- 新增 `pest_map_box`，先求框与可见裁剪区（原图 y=32..223）的交集。
- 完全不可见或反向的框直接丢弃；所有端点在有符号整数中完成裁剪。
- 修复负 `by1` 转为 `u16` 后，再被主程序限制到 719 导致贯穿画面长框的问题。
- 坐标映射按渲染器 `floor(x*4/5)` 的逆映射计算，包含右、下边界。
- 框外扩由显示坐标 6 像素减为 2 像素；主程序拒绝非法框，并补齐三倍放大的最后两个屏幕像素。

## 第二步：修复框的筛选

- 对全部连通域进行检查，插入时保持面积降序，保留全局最大的 8 个。
- 不再取“扫描顺序遇到的前 8 个”后排序。
- 移除面积 600 / 宽高 60 的硬上限，避免大病斑被直接丢弃。
- 使用八邻域、3×3 闭运算连接细小裂隙；保留最小面积、填充率和极端长宽比过滤。

## 第三步：改善定位掩膜

1. 对 RGB 做 3×3 均值去噪。
2. 用植被颜色候选、最大连通域和封闭孔洞填充建立叶片区域，降低背景零碎误框。
3. 定位掩膜向内收缩 1 像素；旧版分类分母不收缩。
4. 褐色分支增加颜色比例约束，减少黄化区域与真正褐斑混在一起。
5. 补充灰紫色暗斑候选，要求其四周有较充分的绿色支持，减少单纯阴影触发。
6. 保留旧版整图褐色比例判据作为褐色分支的门控；封闭暗斑可补充触发病害判断。

串口中的 `legacy brown` 是旧版统计口径，可能仍受偏色背景影响，**不是精确病斑面积**。
暗斑分支触发时，该比例可以低于 0.5%。菜单包含 `pest detector v1.3` 便于确认版本。

## 已完成的验证

- 编译并通过 ctypes 直接调用真实 `pest.c`，没有用 Python 重写算法来替代 C 验证。
- 旧版固定样本分类：TP=10、TN=12、FP=0、FN=2。
- 新版固定样本分类：TP=12、TN=12、FP=0、FN=0；前 12 张无框，后 12 张均有框。
- 通过完全不可见、跨裁剪边界、反向框、448 个逐像素缩放边界测试。
- 通过后到的大框替换前八个小框、最大尺寸 flood 队列、连续正序/逆序处理测试。
- Host GCC `-Wall -Wextra -Werror` 通过；ARM GCC `-Wall -Wextra` 检查和 Release `-O2` 完整编译链接通过。
- 算法静态工作区约 576 KiB，位于 DDR；无递归、无堆分配。

**这些样本参与过规则调整，只能作为回归结果，不能报告为独立测试集 100% 准确率。**
没有人工病斑框标注，目前不能给出 IoU、定位精度或病斑召回率。
第 20、23 张仍有框偏大、阴影混入的情况；小病斑也可能遗漏。
应先上板验证本轮修复，再用人工标注和新增独立样本评估下一轮分割。
ARM 板上复测已完成，见文末记录；不能沿用旧检测程序的耗时。

## 查看结果 / 重跑本机验证

产物在 `build/pest_review/`：

- `after_blight.jpg` / `after_healthy.jpg`：新 C 算法的离线预览，非上板实拍。
- `original_blight.jpg` / `original_healthy.jpg`：对应 RGB 原图。
- `before.json` / `after.json`：逐图分类和框坐标；旧版非法坐标也保留供排查。
- `pest_before.c`：本次修改前的算法备份，不要用于当前程序构建。
- `img_filter_app_v1_3.elf`：使用已有 BSP、链接脚本生成的新 ARM 程序。

在仓库根目录执行（本机 Python 需要 NumPy 和 Pillow；Host 编译器路径在工具脚本中）：

```powershell
python tools/review_pest.py
python tools/test_pest.py
# 已编译过 DLL 时，可加 --no-compile 直接重跑；修改 C 后必须先重新编译。
```

## 第四步：上板检查

本轮无需重新综合 PL。新版 ELF 已生成；之后修改 C 可执行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_pest_app.ps1
```

板子上电、串口终端 115200、关闭占用 JTAG 的 Hardware Manager 后，在仓库根目录执行：

```powershell
# 使用新文件名，保留原来的 SDK ELF。
Copy-Item -LiteralPath '.\build\pest_review\img_filter_app_v1_3.elf' -Destination 'D:\fpga_build\bits\img_filter_app_v1_3.elf'
& 'D:\XILINX\SDK\2018.3\bin\xsct.bat' build/run_app.tcl D:/fpga_build/bits/img_filter_app_v1_3.elf
```

`run_app.tcl` 现在支持显式 ELF 参数，不传参数时保留原行为。
继续使用 `D:/fpga_build/bits/system_top.bit`，应为包含图像上传和标框功能的当前版本。

1. 确认菜单出现 `pest detector v1.3`。
2. 按 KEY1 切到图像缓冲区源；开机默认仍是彩条，第一次按 `p` 显示当前样本。
3. 按 `s` 查看 24 张混淆矩阵，并记录新检测耗时。
4. 按 `n` 顺序查看，重点检查第 13、14 张新增框和第 20～23 张是否仍有异常长框。
5. 区分“实际大面积坏死形成的大框”和“跨越整幅画面的坐标错误长框”。
6. 查看第 19、24 张的背景误框是否减少；用 `o` 对比开关红框的原图。

## 第五步：实际下载与串口测试结果（2026-10-24）

已通过 JTAG 下载当前 bitstream 和新版 ELF，在 COM7 / 115200 捕获到了
`pest detector v1.3` 菜单和 `PL is alive. AXI4-Lite link OK.`。

板上执行 `s` 的原始输出摘要：

```text
TP=12 TN=12 FP=0 FN=0
sensitivity = 12/12 = 100.00%
specificity = 12/12 = 100.00%
accuracy    = 24/24 = 100.00%
max detect time = 109394 us
```

随后依次显示样本 1～13，目前停在第 13 张：

```text
sample 13/24 EARLY BLIGHT
legacy brown 0.00% (0 / 34327 px) boxes=1 104.019 ms
verdict (color + enclosed dark spots): DISEASED
box0: screen (595,273)-(670,393) area 316
```

最后一行是现有串口调试打印；实际送到 PL 的右/下边界还补齐了三倍放大的最后两像素。
分类与本机 C 验证一致。最长检测耗时约 109.4 ms，仅检测阶段相当于约 9.1 张/秒，
不包含图片渲染、AXI 上传和显示延迟；不能称为 60 fps 病害检测。
HDMI 视频扫描与 ARM 检测是不同过程。

- 串口全文：`build/pest_review/board_uart_v1_3.txt`
- 下载日志：`build/pest_review/board_download_v1_3.txt`
- 自动复测脚本：`tools/verify_pest_board.ps1`（会重置、重新下载并运行测试，默认停在第 13 张）

尚未通过外部摄像头或用户反馈确认显示器上的实际框线位置。
若屏幕仍为彩条，按板上 KEY1 切到图像缓冲区源；后续用 `n` 切图、`o` 开关标框。

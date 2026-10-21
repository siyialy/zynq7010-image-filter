# =============================================================================
# set_image.ps1 —— 换图片：把任意图片转成 FPGA 片上 ROM
#
# 做的事：
#   1. 缩放到 320x240（保持比例，居中裁剪，不变形）
#   2. 转灰度 8bit
#   3. 生成 image_gray.coe + image_gray.mem
#   4. 拷到 src/rtl/（构建脚本会自动用它）
#   5. 生成预览图 tools/image_gray_preview.png，先确认对不对
#
# 用法：把图片拖到 set_image.cmd 上，或双击 set_image.cmd 后输入路径
# =============================================================================
param(
    [string]$ImagePath
)

$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$root  = Split-Path $tools -Parent

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " 换图片 → FPGA ROM" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

if (-not $ImagePath) {
    $ImagePath = Read-Host "请输入图片路径（也可以直接把图片拖到 set_image.cmd 上）"
}
$ImagePath = $ImagePath.Trim('"').Trim()

if (-not (Test-Path $ImagePath)) {
    Write-Host "找不到文件: $ImagePath" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

# 找 python（优先系统 python，其次 DSH 自带）
$py = $null
foreach ($cand in @('D:\python\python.exe',
                    'C:\Users\九思\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe')) {
    if (Test-Path $cand) { $py = $cand; break }
}
if (-not $py) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $py = $cmd.Source }
}
if (-not $py) {
    Write-Host "找不到 python，请先安装 Python 3 + Pillow" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

$coe = Join-Path $tools 'image_gray.coe'

Write-Host ""
Write-Host "正在转换（缩放 320x240、灰度化）..." -ForegroundColor Yellow
& $py (Join-Path $tools 'bmp2coe.py') $ImagePath -o $coe --width 320 --height 240 --gray
if ($LASTEXITCODE -ne 0) {
    Write-Host "转换失败" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

$mem = [System.IO.Path]::ChangeExtension($coe, '.mem')
if (-not (Test-Path $mem)) {
    Write-Host "没有生成 .mem 文件（检查 bmp2coe.py）" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

# 拷到 RTL 目录（构建脚本从这里取）
$dstMem = Join-Path $root 'src\rtl\image_gray.mem'
$dstCoe = Join-Path $root 'src\rtl\image_gray.coe'
Copy-Item $mem $dstMem -Force
if (Test-Path $coe) { Copy-Item $coe $dstCoe -Force }

$size = (Get-Item $dstMem).Length
Write-Host ""
Write-Host "OK！已更新：" -ForegroundColor Green
Write-Host "  $dstMem  ($size 字节 = 320x240 灰度)" -ForegroundColor Green

$preview = Join-Path $tools 'image_gray_preview.png'
if (Test-Path $preview) {
    Write-Host ""
    Write-Host "预览图（先看一眼对不对）：" -ForegroundColor Cyan
    Write-Host "  $preview" -ForegroundColor Cyan
    Start-Process $preview
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " 下一步：重新构建 bit 流（约 13 分钟）" -ForegroundColor Yellow
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  cd D:\FPGA比赛" -ForegroundColor White
Write-Host "  Remove-Item D:\fpga_build\sys -Recurse -Force -ErrorAction SilentlyContinue" -ForegroundColor White
Write-Host "  D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\build_system.tcl" -ForegroundColor White
Write-Host ""
Write-Host " 构建完再运行：build\run_app.tcl 下载到板子" -ForegroundColor White
Write-Host "（或者直接把这条消息告诉我，我帮你跑）" -ForegroundColor DarkGray
Write-Host ""
Read-Host "按回车退出"

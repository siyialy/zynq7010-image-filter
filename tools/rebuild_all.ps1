# =============================================================================
# rebuild_all.ps1 —— 一条龙：换图 → 构建 → 部署 → 下载到板子
#
# 用法：
#   1) 换图并重新构建：把图片拖到 rebuild_all.cmd 上
#   2) 只重新构建（图不变）：双击 rebuild_all.cmd
#
# 做的事：
#   [1/5] 转换图片（可选）
#   [2/5] 清掉旧工程
#   [3/5] Vivado 综合+实现+生成 bit（约 13 分钟）
#   [4/5] 把 bit 拷到纯英文路径
#   [5/5] xsct 下载 bit + ARM 程序并运行
# =============================================================================
param(
    [string]$ImagePath
)

$ErrorActionPreference = 'Continue'
$tools = $PSScriptRoot
$root  = Split-Path $tools -Parent
$t0    = Get-Date

function Step($n, $msg) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host " [$n/5] $msg" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host " 已用时间: $([int]((Get-Date) - $t0).TotalMinutes) 分 $([int]((Get-Date) - $t0).TotalSeconds % 60) 秒" -ForegroundColor DarkGray
}

function Fail($msg) {
    Write-Host ""
    Write-Host "!!! 失败: $msg" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

# ---------------------------------------------------------------- 找 python
$py = $null
foreach ($cand in @('D:\python\python.exe',
                    'C:\Users\九思\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe')) {
    if (Test-Path $cand) { $py = $cand; break }
}

# ================================================================ [1/5] 换图
if ($ImagePath) {
    $ImagePath = $ImagePath.Trim('"').Trim()
    Step 1 "转换图片: $(Split-Path $ImagePath -Leaf)"
    if (-not (Test-Path $ImagePath)) { Fail "找不到图片 $ImagePath" }
    if (-not $py) { Fail "找不到 python" }

    $coe = Join-Path $tools 'image_gray.coe'
    & $py (Join-Path $tools 'bmp2coe.py') $ImagePath -o $coe --width 320 --height 240 --gray
    if ($LASTEXITCODE -ne 0) { Fail "图片转换失败" }

    $mem = [System.IO.Path]::ChangeExtension($coe, '.mem')
    if (-not (Test-Path $mem)) { Fail "没有生成 .mem" }
    Copy-Item $mem (Join-Path $root 'src\rtl\image_gray.mem') -Force
    Copy-Item $coe (Join-Path $root 'src\rtl\image_gray.coe') -Force
    Write-Host " 已更新 src\rtl\image_gray.mem" -ForegroundColor Green

    $preview = Join-Path $tools 'image_gray_preview.png'
    if (Test-Path $preview) {
        Write-Host " 预览图: $preview" -ForegroundColor Yellow
        Start-Process $preview
    }
} else {
    Step 1 "使用现有图片（跳过转换）"
    Write-Host " 当前 ROM: src\rtl\image_gray.mem" -ForegroundColor Gray
}

# ================================================================ [2/5] 清理
Step 2 "清理旧工程"
Remove-Item 'D:\fpga_build\sys' -Recurse -Force -ErrorAction SilentlyContinue
Write-Host " D:\fpga_build\sys 已删除" -ForegroundColor Green

# ================================================================ [3/5] 构建
Step 3 "Vivado 构建（约 13 分钟，不要关窗口）"
$log = Join-Path $root 'build\rebuild_all.log'
if (Test-Path $log) { Remove-Item $log -Force }

& 'D:\XILINX\Vivado\2018.3\bin\vivado.bat' -mode batch `
    -source (Join-Path $root 'build\build_system.tcl') 2>&1 |
    Tee-Object -FilePath $log |
    Select-String -Pattern 'synth status|impl status|TIMING|SYSTEM BUILD DONE|ERROR:' |
    ForEach-Object { Write-Host "  " $_.Line.Trim() -ForegroundColor DarkGray }

$bit = 'D:\fpga_build\sys\sys.runs\impl_1\system_top.bit'
$okImpl = Select-String -Path $log -Pattern 'write_bitstream Complete' -Quiet
if (-not $okImpl) { Fail "构建没完成，看日志: $log" }
if (-not (Test-Path $bit)) { Fail "没有生成 bit 文件" }

$age = ((Get-Date) - (Get-Item $bit).LastWriteTime).TotalMinutes
if ($age -gt 30) { Fail "bit 文件是 $([int]$age) 分钟前的，可能是旧文件" }

# 时序检查
$rpt = 'D:\fpga_build\sys\sys.runs\impl_1\system_top_timing_summary_routed.rpt'
if (Test-Path $rpt) {
    $txt = [System.IO.File]::ReadAllText($rpt, [System.Text.Encoding]::GetEncoding(936))
    if ($txt -match 'Slack \(VIOLATED\)') {
        Write-Host " 警告：有时序违例（但 bit 已生成，功能一般仍可用）" -ForegroundColor Yellow
    } else {
        Write-Host " 时序: 无违例 ✓" -ForegroundColor Green
    }
}
Write-Host " bit: $bit  ($( [math]::Round((Get-Item $bit).Length/1KB,0) ) KB)" -ForegroundColor Green

# ================================================================ [4/5] 部署
Step 4 "部署到纯英文路径"
New-Item -ItemType Directory -Force -Path 'D:\fpga_build\bits' | Out-Null
Copy-Item $bit 'D:\fpga_build\bits\system_top.bit' -Force
Copy-Item $bit (Join-Path $root 'board\system\system_top.bit') -Force
if (Test-Path 'D:\fpga_build\sys\system.hdf') {
    Copy-Item 'D:\fpga_build\sys\system.hdf' (Join-Path $root 'board\system\system.hdf') -Force
}
Write-Host " 已拷贝到 D:\fpga_build\bits\system_top.bit" -ForegroundColor Green

# ================================================================ [5/5] 下载
Step 5 "下载到板子并运行"
Write-Host " 如果失败：确认板子上电、BOOT CFG 两个都 ON、Vivado 的 Hardware Manager 已关闭" -ForegroundColor Yellow
& 'D:\XILINX\SDK\2018.3\bin\xsct.bat' (Join-Path $root 'build\run_app.tcl') 2>&1 |
    Select-String -Pattern 'programming PL|downloading ELF|APP IS RUNNING|ERROR|error|DAP' |
    ForEach-Object { Write-Host "  " $_.Line.Trim() }

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " 全部完成！总耗时 $([int]((Get-Date) - $t0).TotalMinutes) 分 $([int]((Get-Date) - $t0).TotalSeconds % 60) 秒" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host " 现在看屏幕；串口终端里按 0/1/2/3 切模式" -ForegroundColor White
Write-Host ""
Read-Host "按回车退出"

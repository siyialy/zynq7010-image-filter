# =============================================================================
# serial_term.ps1 —— 极简串口终端（交互式，轮询实现，稳定不挑环境）
#
# 用途：和板子的 PS 串口对话，敲 0/1/2/3 切滤波模式、h 测帧率、c 跑基线
# 用法：双击同目录下的 serial_term.cmd
# =============================================================================
param(
    [string]$ComPort = "COM7",
    [int]$Baud = 115200
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " ZYNQ-7010 图像滤波 —— 串口终端" -ForegroundColor Cyan
Write-Host " 端口 $ComPort   波特率 $Baud   8-N-1" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "命令： 0 1 2 3 = 切模式 | e 开滤波 | d 旁路" -ForegroundColor Green
Write-Host "       h 硬件帧率 | c 软件基线对比 | i 看寄存器 | m 菜单" -ForegroundColor Green
Write-Host "直接敲字符即可（不用回车），Esc 或 Ctrl+C 退出" -ForegroundColor DarkGray
Write-Host ""

$port = New-Object System.IO.Ports.SerialPort $ComPort,$Baud,'None',8,'One'
$port.ReadTimeout = 50
$port.WriteTimeout = 500

try {
    $port.Open()
} catch {
    Write-Host "打开串口失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "可能原因：端口号不对 / 被别的程序占用（关掉其他串口工具，比如 Vivado 的调试窗口）" -ForegroundColor Yellow
    Read-Host "按回车退出"
    exit 1
}

Start-Sleep -Milliseconds 200
try { $port.DiscardInBuffer() } catch { }

# 敲个回车，让板子把菜单打出来
$port.Write("`r")

try {
    while ($true) {
        # 1) 收：把板子发来的字符打到屏幕
        try {
            $d = $port.ReadExisting()
            if ($d.Length -gt 0) { [Console]::Write($d) }
        } catch { }

        # 2) 发：把键盘按下的字符发出去
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Escape) { break }
            if ($key.Key -eq [ConsoleKey]::Enter) {
                $port.Write("`r")
                [Console]::Write("`r`n")
            }
            elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                $port.Write([char]8)
                [Console]::Write("`b `b")
            }
            else {
                $ch = [string]$key.KeyChar
                if ($ch.Length -gt 0 -and [int][char]$ch -ge 32) {
                    $port.Write($ch)
                    [Console]::Write($ch)
                }
            }
        }

        Start-Sleep -Milliseconds 10
    }
}
finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
    Write-Host ""
    Write-Host "串口已关闭。" -ForegroundColor DarkGray
}

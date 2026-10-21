# uart_listen.ps1 —— 监听串口并把收到的所有数据写进文件
param(
    [string]$ComPort = "COM7",
    [int]$Seconds   = 40,
    [string]$OutFile = "D:\fpga_build\uart_capture.txt"
)

$ErrorActionPreference = 'Stop'
$port = New-Object System.IO.Ports.SerialPort $ComPort,115200,'None',8,'One'
$port.ReadTimeout = 500
$sb = New-Object System.Text.StringBuilder

try {
    $port.Open()
    "" | Set-Content -Path $OutFile -Encoding UTF8
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        try {
            $chunk = $port.ReadExisting()
            if ($chunk.Length -gt 0) {
                [void]$sb.Append($chunk)
                Add-Content -Path $OutFile -Value $chunk -NoNewline -Encoding UTF8
            }
        } catch { }
        Start-Sleep -Milliseconds 50
    }
} catch {
    "PORT_ERROR: " + $_.Exception.Message | Set-Content -Path $OutFile -Encoding UTF8
} finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
}

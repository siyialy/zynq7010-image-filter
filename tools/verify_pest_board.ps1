param(
    [string]$ComPort = 'COM7',
    [ValidateRange(1,24)][int]$Sample = 14,
    [ValidateSet('1_3','1_4','1_5','1_6','1_7','2_0','2_1','2_2','2_3','2_4','2_5','2_6')][string]$Version = '2_6'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot 'build/pest_review'
$logPath = Join-Path $outDir "board_uart_v$Version.txt"
$downloadLog = Join-Path $outDir "board_download_v$Version.txt"
$elf = Join-Path $outDir "img_filter_app_v$Version.elf"
$stagedElf = "D:/fpga_build/bits/img_filter_app_v$Version.elf"
$displayVersion = $Version.Replace('_','.')
$bannerPattern = 'pest detector v' + [regex]::Escape($displayVersion)
$xsct = 'D:/XILINX/SDK/2018.3/bin/xsct.bat'
$bit = if ($Version -eq '2_6') { 'D:/fpga_build/bits/system_top_v2_6.bit' } elseif ($Version -eq '2_5') { 'D:/fpga_build/bits/system_top_v2_5.bit' } elseif ($Version -eq '2_4') { 'D:/fpga_build/bits/system_top_v2_4.bit' } elseif ($Version -eq '2_3') { 'D:/fpga_build/bits/system_top_v2_3.bit' } elseif ($Version -eq '2_2') { 'D:/fpga_build/bits/system_top_v2_2.bit' } elseif ($Version -eq '2_1') { 'D:/fpga_build/bits/system_top_v2_1.bit' } elseif ($Version -eq '2_0') { 'D:/fpga_build/bits/system_top_v2_0.bit' } elseif ($Version -in @('1_5','1_6','1_7','2_0','2_1','2_2','2_3','2_4','2_5','2_6')) { 'D:/fpga_build/bits/system_top_v1_5.bit' } else { 'D:/fpga_build/bits/system_top.bit' }
foreach ($required in @($elf,$xsct,$bit)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing: $required" }
}
$port = [System.IO.Ports.SerialPort]::new($ComPort,115200,'None',8,'One')
$port.ReadTimeout = 500
$port.WriteTimeout = 1000
$port.ReadBufferSize = 65536
$capture = [System.Text.StringBuilder]::new()
function Read-Until([string]$Pattern,[int]$Seconds) {
    $response = [System.Text.StringBuilder]::new()
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $chunk = $port.ReadExisting()
        if ($chunk.Length) {
            [void]$capture.Append($chunk)
            [void]$response.Append($chunk)
            Add-Content -LiteralPath $logPath -Value $chunk -NoNewline -Encoding UTF8
            if ($Pattern -and $response.ToString() -match $Pattern) { break }
        }
        Start-Sleep -Milliseconds 50
    }
    return $response.ToString()
}
Push-Location $repoRoot
try {
    # Open UART before resetting the board so the boot banner is captured.
    $port.Open()
    Set-Content -LiteralPath $logPath -Value "Board verification: $(Get-Date -Format o), $ComPort, 115200" -Encoding UTF8
    Copy-Item -LiteralPath $elf -Destination $stagedElf -Force
    Write-Host "Programming current bitstream and detector v$displayVersion ELF..."
    & $xsct 'build/run_app.tcl' $stagedElf $bit 2>&1 | Tee-Object -FilePath $downloadLog
    if ($LASTEXITCODE -ne 0) { throw "XSCT failed ($LASTEXITCODE). See $downloadLog" }
    $boot = Read-Until $bannerPattern 5
    if ($boot -notmatch $bannerPattern) {
        $port.Write('m')
        $boot += Read-Until $bannerPattern 5
    }
    Write-Host $boot
    if ($boot -notmatch $bannerPattern) { throw "Expected v$displayVersion UART banner not received." }
    $port.Write('s')
    $bench = Read-Until 'max detect time = \d+ us' $(if ($Version -in @('2_0','2_1','2_2','2_3','2_4','2_5','2_6')) { 180 } else { 45 })
    Write-Host $bench
    if ($bench -notmatch 'max detect time = \d+ us') { throw 'Sample benchmark timed out.' }
    if ($Version -in @('2_0','2_1','2_2','2_3','2_4','2_5','2_6') -and $bench -notmatch 'detector errors = 0') { throw 'PL hardware reported detector errors.' }
    $port.Write('p')
    $response = Read-Until 'verdict \([^\r\n]+\):' 10
    if ($response -notmatch 'sample 1/24') { throw 'Unexpected initial sample.' }
    for ($i = 2; $i -le $Sample; $i++) {
        $port.Write('n')
        $response = Read-Until 'verdict \([^\r\n]+\):' 10
        if ($response -notmatch "sample $i/24") { throw "Sample advance failed at $i" }
    }
    Write-Host $response
    Write-Host (Read-Until '' 1)
    Write-Host "Verification captured. Current sample: $Sample. Press board KEY1 if HDMI shows color bars."
    Write-Host "UART log: $logPath"
} finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
    Pop-Location
}

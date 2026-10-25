param([string]$ComPort='COM7')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$log=Join-Path $root 'build/pl_detector_v26/sample13_uart.txt'
$port=[System.IO.Ports.SerialPort]::new($ComPort,115200,'None',8,'One')
$port.ReadBufferSize=65536
$capture=[System.Text.StringBuilder]::new()
try {
    $port.Open();[void]$port.ReadExisting()
    # The preceding p/s/o regression deliberately leaves sample 14 selected.
    $port.Write('b')
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    while([DateTime]::UtcNow -lt $deadline){
        $chunk=$port.ReadExisting()
        if($chunk.Length){[void]$capture.Append($chunk)}
        if($capture.ToString() -match 'box0: screen [^\r\n]+area 633'){break}
        Start-Sleep -Milliseconds 30
    }
    $text=$capture.ToString()
    Set-Content -LiteralPath $log -Value $text -Encoding UTF8
    if($text -notmatch 'sample 13/24' -or $text -notmatch 'boxes=1\b' -or
       $text -notmatch 'display sample=13 result sample=13' -or
       $text -notmatch 'box0: screen \(595,285\)-\(664,390\) area 633'){
        throw "Sample 13 shadow regression failed; see $log"
    }
    Write-Host $text
    Write-Host 'PASS: sample 13 has exactly the retained leaf-lesion box; reported background box is absent. Overlay ON, UART released.'
} finally {if($port.IsOpen){$port.Close()};$port.Dispose()}

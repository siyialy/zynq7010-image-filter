param([string]$ComPort='COM7',[ValidateSet('2_4','2_5','2_6')][string]$Version='2_6')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$log=Join-Path $repo "build/pl_detector_v$($Version.Replace('_',''))/control_uart.txt"
$port=[System.IO.Ports.SerialPort]::new($ComPort,115200,'None',8,'One')
$port.ReadBufferSize=65536
function Read-Until([string]$pattern,[int]$seconds=15){
    $response=[System.Text.StringBuilder]::new()
    $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
    while([DateTime]::UtcNow -lt $deadline){
        $chunk=$port.ReadExisting()
        if($chunk){[void]$response.Append($chunk);Add-Content -LiteralPath $log -Value $chunk -NoNewline -Encoding UTF8}
        if($response.ToString() -match $pattern){return $response.ToString()}
        Start-Sleep -Milliseconds 30
    }
    throw "UART timeout: $pattern"
}
function Check-Current([string]$response){
    if($response -notmatch 'sample 14/24' -or $response -notmatch 'boxes=7' -or
       $response -notmatch 'display sample=14 result sample=14'){throw 'Displayed image and detector result did not match sample 14'}
}
try{
    $port.Open();[void]$port.ReadExisting()
    Set-Content -LiteralPath $log -Value "v$Version control regression $(Get-Date -Format o)" -Encoding UTF8
    $port.Write('p');$first=Read-Until 'verdict \([^\r\n]+\): DISEASED';Check-Current $first
    $port.Write('s');$bench=Read-Until 'max detect time = \d+ us' 90;Check-Current $bench
    if($bench -notmatch 'restoring displayed sample 14 after benchmark' -or $bench -notmatch 'detector errors = 0'){throw 'Benchmark restore failed'}
    $port.Write('o');[void](Read-Until 'box overlay OFF')
    $port.Write('s');$off=Read-Until 'max detect time = \d+ us' 90;Check-Current $off
    $port.Write('o');[void](Read-Until 'box overlay ON')
    $port.Write('p');$last=Read-Until 'verdict \([^\r\n]+\): DISEASED';Check-Current $last
    $times=[regex]::Matches($last,'whole sample work \(display \+ detect\): (\d+\.\d+) ms')
    if(!$times.Count){throw 'Repeat detection timing missing'}
    Write-Host "PASS: real board p/s/o sequence restored sample 14, preserved matching boxes and allowed overlay toggling."
    Write-Host "Cached sample 14 complete work: $($times[0].Groups[1].Value) ms"
    Write-Host "Current sample: 14. Overlay ON. Log: $log"
}finally{if($port.IsOpen){$port.Close()};$port.Dispose()}

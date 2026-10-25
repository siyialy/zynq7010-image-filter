param(
    [string]$ComPort='COM7',
    [ValidateSet('2_0','2_1','2_2','2_3','2_4','2_5','2_6')][string]$Version='2_6',
    [ValidateRange(1,24)][int]$Sample=14
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$xsct='D:/XILINX/SDK/2018.3/bin/xsct.bat'
$bit="D:/fpga_build/bits/system_top_v$Version.bit"
$elf=Join-Path $repoRoot "build/pest_review/img_filter_app_v$Version.elf"
$stagedElf="D:/fpga_build/bits/img_filter_app_v$Version.elf"
$psInit='D:/fpga_build/sdk_ws/hw0/ps7_init.tcl'
foreach($f in @($xsct,$bit,$elf,$psInit)){
    if(!(Test-Path -LiteralPath $f)){throw "Missing dependency: $f"}
}
if($Version -in @('2_5','2_6')) {
    $releasePath=Join-Path $repoRoot "build/pl_detector_v$($Version.Replace('_',''))/release_verified.json"
    if(!(Test-Path -LiteralPath $releasePath)){throw 'Selected release has not completed RTL, timing and board checks. Use the verified default release.'}
    $release=Get-Content -LiteralPath $releasePath -Raw | ConvertFrom-Json
    if(!$release.verified -or (Get-FileHash $bit -Algorithm SHA256).Hash.ToLowerInvariant() -ne $release.bit_sha256 -or
       (Get-FileHash $elf -Algorithm SHA256).Hash.ToLowerInvariant() -ne $release.elf_sha256){throw 'Selected release hashes changed; re-run validation before startup.'}
}
$port=[System.IO.Ports.SerialPort]::new($ComPort,115200,'None',8,'One')
$port.ReadBufferSize=65536
$port.WriteTimeout=1000
function Read-Until([string]$Pattern,[int]$Seconds){
    $buffer=[System.Text.StringBuilder]::new()
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    while([DateTime]::UtcNow -lt $deadline){
        $chunk=$port.ReadExisting()
        if($chunk.Length){
            [void]$buffer.Append($chunk)
            if($buffer.ToString() -match $Pattern){return $buffer.ToString()}
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for: $Pattern`n$($buffer.ToString())"
}
Push-Location $repoRoot
try{
    try{$port.Open()}catch{throw "Cannot open $ComPort. Close its serial terminal first, then run this launcher again."}
    Copy-Item -LiteralPath $elf -Destination $stagedElf -Force
    $displayVersion=$Version.Replace('_','.')
    Write-Host "Loading verified v$displayVersion PL bitstream and PS ARM application..."
    & $xsct build/run_app.tcl $stagedElf $bit
    if($LASTEXITCODE -ne 0){throw 'JTAG download failed'}
    [void](Read-Until ('pest detector v'+[regex]::Escape($displayVersion)) 10)
    $port.Write('p')
    $response=Read-Until 'verdict \([^\r\n]+\):[^\r\n]+' 15
    if($response -notmatch 'sample 1/24'){throw "Unexpected sample response: $response"}
    Write-Host "Detected sample 1/$Sample"
    for($i=2;$i -le $Sample;$i++){
        $port.Write('n')
        $response=Read-Until 'verdict \([^\r\n]+\):[^\r\n]+' 15
        if($response -notmatch "sample $i/24"){throw "Sample advance failed at $i`: $response"}
        Write-Host "Detected sample $i/$Sample"
    }
    Write-Host $response
    Write-Host "READY: sample $Sample. If HDMI shows colour bars, press board KEY1 once."
    Write-Host "$ComPort will now be released. You may reopen your serial terminal (115200,8N1)."
}finally{
    if($port.IsOpen){$port.Close()}
    $port.Dispose()
    Pop-Location
}

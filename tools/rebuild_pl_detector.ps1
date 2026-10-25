param(
    [switch]$SkipHardware,
    [ValidateSet('2_0','2_1','2_2','2_3','2_4','2_5','2_6')][string]$Version='2_6',
    [switch]$SkipProgram,
    [ValidateRange(1,24)][int]$Sample=14
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$vivado='D:/XILINX/Vivado/2018.3/bin/vivado.bat'
Push-Location $repoRoot
try {
    if($Version -eq '2_6'){
        & "$PSScriptRoot/rebuild_v26.ps1" -SkipHardware:$SkipHardware -SkipProgram:$SkipProgram -Sample $Sample
        return
    }
    if($Version -eq '2_5'){
        & "$PSScriptRoot/rebuild_v25.ps1" -SkipHardware:$SkipHardware -SkipProgram:$SkipProgram -Sample $Sample
        return
    }
    New-Item -ItemType Directory -Force build/pl_detector | Out-Null
    $modern=$Version -in @('2_2','2_3','2_4')
    $tag=$Version.Replace('_','')
    if($modern){ & python $(if($Version -eq '2_4'){'tools/pl_detector_v23_model.py'}else{"tools/pl_detector_v${tag}_model.py"}) }else{ & python tools/pl_detector_model.py }
    if($LASTEXITCODE -ne 0){throw 'Python reference failed'}
    if($modern){ & python "tools/prepare_pl_v${tag}_vectors.py" }else{ & python tools/prepare_pl_vectors.py }
    if($LASTEXITCODE -ne 0){throw 'Vector preparation failed'}
    if($Version -eq '2_4'){
        & python tools/run_v24_checks.py
        if($LASTEXITCODE -ne 0){throw 'PS host checks failed'}
    }
    if(!$SkipHardware){
        if($Version -eq '2_4'){
            & $vivado -mode batch -source build/sim_display_hold.tcl -log build/pl_detector_v24/hold.log -nojournal
            if($LASTEXITCODE -ne 0){throw 'Frame hold simulation failed'}
            $holdLog=Get-Content build/pl_detector_v24/hold.log -Raw
            if($holdLog -notmatch 'PASS: asynchronous hold' -or $holdLog -match 'Fatal:'){throw 'Frame hold assertions failed'}
        }
        if($modern){
            foreach($kind in @('small','many','full')){
                $simLog="build/pl_detector_v${tag}/rebuild_$kind.log"
                & $vivado -mode batch -source "build/sim_pl_v$tag.tcl" -log $simLog -nojournal -tclargs $kind
                if($LASTEXITCODE -ne 0){throw "RTL $kind simulation failed"}
                $simulation=Get-Content -LiteralPath $simLog -Raw
                $completion= switch($kind){small{'PASS: Python/RTL'};many{'PASS: 16 retained'};full{'PASS: full-size'}}
                if($simulation -notmatch $completion -or $simulation -match 'Fatal:|FAIL:'){throw "RTL $kind assertions failed"}
            }
        }else{
            & $vivado -mode batch -source build/sim_pl_detector.tcl -log build/pl_detector/rebuild_sim.log -journal build/pl_detector/rebuild_sim.jou
            if($LASTEXITCODE -ne 0){throw 'RTL simulation failed'}
            $simulation=Get-Content -LiteralPath build/pl_detector/rebuild_sim.log -Raw
            if($simulation -notmatch 'PASS: Python/RTL' -or $simulation -match 'Fatal:'){throw 'RTL assertions failed'}
        }
        & $vivado -mode batch -source build/build_pl_detector.tcl -log build/pl_detector/rebuild.log -journal build/pl_detector/rebuild.jou -tclargs $Version
        if($LASTEXITCODE -ne 0){throw 'Hardware build/timing failed'}
    }
    & "$PSScriptRoot/build_pest_app.ps1" -Version $Version
    if(!$SkipProgram){
        & "$PSScriptRoot/verify_pest_board.ps1" -Version $Version -Sample $Sample
        & python tools/check_pl_board.py --version $Version
        if($LASTEXITCODE -ne 0){throw 'Board/Python comparison failed'}
    }
}finally{Pop-Location}

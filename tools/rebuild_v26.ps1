param([switch]$SkipHardware,[switch]$SkipProgram,[string]$ComPort='COM7',[ValidateRange(1,24)][int]$Sample=13)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$vivado='D:/XILINX/Vivado/2018.3/bin/vivado.bat'
Push-Location $root
try {
    & python tools/test_v26_reference.py
    if($LASTEXITCODE -ne 0){throw 'Offline invariants failed'}
    & python tools/evaluate_v26.py
    if($LASTEXITCODE -ne 0){throw 'Annotation regression failed'}
    & python tools/prepare_pl_v26_vectors.py
    if($LASTEXITCODE -ne 0){throw 'Independent vectors failed'}
    & python tools/prepare_pl_v26_pool.py
    if($LASTEXITCODE -ne 0){throw 'Synthetic full-pool vectors failed'}
    & python tools/run_v24_checks.py
    if($LASTEXITCODE -ne 0){throw 'Shared PS regression failed'}
    $gcc='D:/XILINX/Vivado/2018.3/tps/mingw/6.2.0/win64.o/nt/bin/gcc.exe'
    & $gcc -O2 -Wall -Wextra -DPEST_USE_PL -DPEST_OPTIMIZED -DPEST_FULL_FRAME -DPEST_V25 -DPEST_V26 -Ibuild/pl_detector_v24/host_include -Ips_app tools/test_driver_v25.c -o build/pl_detector_v26/test_driver.exe
    if($LASTEXITCODE -ne 0){throw 'Driver test compilation failed'}
    & ./build/pl_detector_v26/test_driver.exe
    if($LASTEXITCODE -ne 0){throw 'Driver protocol failed'}
    & $gcc -O2 -Wall -Wextra -DPEST_USE_PL -DPEST_OPTIMIZED -DPEST_FAST_PL -DPEST_FULL_FRAME -DPEST_V25 -DPEST_V26 -Ibuild/pl_detector_v24/host_include -Ips_app tools/test_control_v24.c -o build/pl_detector_v26/test_control.exe
    if($LASTEXITCODE -ne 0){throw 'Controller test compilation failed'}
    & ./build/pl_detector_v26/test_control.exe
    if($LASTEXITCODE -ne 0){throw 'v26 current-image/control regression failed'}
    if(!$SkipHardware){
        foreach($kind in @('fusion','pool32','full')){
            $log=if($kind -eq 'full'){'build/pl_detector_v26/sim_full_pipeline.log'}elseif($kind -eq 'pool32'){'build/pl_detector_v26/sim_pool32_pipeline.log'}else{'build/pl_detector_v26/sim_fusion.log'}
            & $vivado -mode batch -source build/sim_pl_v26.tcl -log $log -nojournal -tclargs $kind
            if($LASTEXITCODE -ne 0){throw "v25 $kind simulation tool failed"}
            $text=Get-Content -LiteralPath $log -Raw
            if($text -match 'Fatal:|FAIL:' -or $text -notmatch $(if($kind -eq 'full'){'PASS: v26 full'}else{"PASS: v25 $kind"})){throw "v25 $kind assertions failed"}
        }
        & $vivado -mode batch -source build/build_pl_detector.tcl -log build/pl_detector_v26/build.log -nojournal -tclargs 2_6
        if($LASTEXITCODE -ne 0){throw 'Resource/setup/hold checks failed'}
    }
    & ./tools/build_pest_app.ps1 -Version 2_6
    if(!$SkipProgram){
        & ./tools/verify_pest_board.ps1 -Version 2_6 -Sample 14 -ComPort $ComPort
        & python tools/check_pl_board.py --version 2_6
        if($LASTEXITCODE -ne 0){throw 'Board differs from reference'}
        & ./tools/verify_control_v24.ps1 -Version 2_6 -ComPort $ComPort
        & ./tools/verify_shadow_v26.ps1 -ComPort $ComPort
        & python tools/finalize_v26.py
        if($LASTEXITCODE -ne 0){throw 'Release evidence incomplete'}
        if($Sample -ne 13){
            & ./tools/start_pl_demo.ps1 -Version 2_6 -Sample $Sample -ComPort $ComPort
        }
    }
} finally {Pop-Location}

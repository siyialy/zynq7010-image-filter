param(
    [string]$SdkRoot = 'D:/XILINX/SDK/2018.3',
    [string]$Workspace = 'D:/fpga_build/sdk_ws',
    [ValidateSet('1_3','1_4','1_5','1_6','1_7','2_0','2_1','2_2','2_3','2_4','2_5','2_6')][string]$Version = '2_6'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$gcc = Join-Path $SdkRoot 'gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe'
$bsp = Join-Path $Workspace 'img_filter_app_bsp/ps7_cortexa9_0'
$spec = Join-Path $Workspace 'img_filter_app/Release/Xilinx.spec'
$linker = Join-Path $Workspace 'img_filter_app/src/lscript.ld'
foreach ($required in @($gcc, $spec, $linker, (Join-Path $bsp 'lib/libxil.a'))) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing dependency: $required" }
}
Push-Location $repoRoot
try {
    New-Item -ItemType Directory -Path 'build/pest_review' -Force | Out-Null
    $compilerArgs = @(
        '-O2', '-Wall', '-Wextra', '-mcpu=cortex-a9', '-mfpu=vfpv3', '-mfloat-abi=hard',
        "-I$bsp/include", '-Ips_app', 'ps_app/main.c', 'ps_app/pest.c', 'ps_app/sw_filter.c', 'ps_app/pl_detector.c',
        '-Wl,-build-id=none', "-specs=$spec", "-Wl,-T,$linker", "-L$bsp/lib",
        '-Wl,--start-group,-lxil,-lgcc,-lc,--end-group',
        "-Wl,-Map,build/pest_review/img_filter_app_v$Version.map",
        '-o', "build/pest_review/img_filter_app_v$Version.elf"
    )
    if ($Version -in @('2_0','2_1','2_2','2_3','2_4','2_5','2_6')) { $compilerArgs += @('-DPEST_USE_PL','-ffunction-sections','-fdata-sections','-Wl,--gc-sections') }
    if ($Version -in @('2_1','2_2','2_3','2_4','2_5','2_6')) { $compilerArgs += '-DPEST_FAST_PL' }
    if ($Version -in @('2_2','2_3','2_4','2_5','2_6')) { $compilerArgs += @('-DPEST_PRECISION','-DPEST_FULL_FRAME') }
    if ($Version -in @('2_3','2_4','2_5','2_6')) { $compilerArgs += '-DPEST_RECALL' }
    if ($Version -in @('2_4','2_5','2_6')) { $compilerArgs += '-DPEST_OPTIMIZED' }
    if ($Version -in @('2_5','2_6')) { $compilerArgs += '-DPEST_V25' }
    if ($Version -eq '2_6') { $compilerArgs += '-DPEST_V26' }
    & $gcc @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "ARM build failed ($LASTEXITCODE)" }
    if ($Version -in @('2_5','2_6')) {
        $sourceHashes=@{}
        foreach($file in @('ps_app/main.c','ps_app/pest.c','ps_app/pest.h','ps_app/pl_detector.c','ps_app/pl_detector.h','ps_app/pv_samples.h','ps_app/sw_filter.c')) {
            $sourceHashes[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        @{version=$Version;elf_sha256=(Get-FileHash "build/pest_review/img_filter_app_v$Version.elf" -Algorithm SHA256).Hash.ToLowerInvariant();sources=$sourceHashes} |
            ConvertTo-Json -Depth 4 | Set-Content "build/pest_review/img_filter_app_v$Version.build.json" -Encoding UTF8
    }
    Write-Host "Built: build/pest_review/img_filter_app_v$Version.elf (Release -O2)"
} finally {
    Pop-Location
}

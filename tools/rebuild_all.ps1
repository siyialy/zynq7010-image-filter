# Compatibility entry: all builds use the isolated, timing-checked detector flow.
param([string]$ImagePath,[switch]$SkipHardware,[switch]$SkipProgram)
$ErrorActionPreference='Stop'
if($ImagePath){throw 'Image replacement is not supported here. Prepare RGB samples separately; this entry rebuilds the current detector.'}
& "$PSScriptRoot/rebuild_pl_detector.ps1" -SkipHardware:$SkipHardware -SkipProgram:$SkipProgram

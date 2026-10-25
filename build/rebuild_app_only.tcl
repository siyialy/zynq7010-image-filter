# =============================================================================
# rebuild_app_only.tcl —— 只重新编译 PS 应用（不重建 BSP 和硬件工程）
#
# 用法：
#   D:\XILINX\SDK\2018.3\bin\xsct.bat D:\FPGA比赛\build\rebuild_app_only.tcl
#
# 前提：D:\fpga_build\sdk_ws 里已经有 hw0 / img_filter_app 工程（跑过一次 build_app.tcl）
# =============================================================================

set ws  "D:/fpga_build/sdk_ws"
set src "D:/fpga_build/ps_src"

if {![file exists $ws]} { puts "ERROR: 没有 workspace $ws"; exit 1 }

setws $ws

# 把最新源码拷进应用工程
set app_src [file join $ws img_filter_app src]
file mkdir $app_src
foreach f {main.c sw_filter.c sw_filter.h pest.c pest.h pv_samples.h} {
    file copy -force [file join $src $f] $app_src
    puts "INFO: copied $f"
}

# 只编译
projects -build
puts "INFO: build finished"

set elf [glob -nocomplain [file join $ws img_filter_app Debug *.elf]]
if {[llength $elf] > 0} {
    puts "ELF: [lindex $elf 0]"
    puts "=== APP REBUILD DONE ==="
} else {
    puts "ERROR: 没有生成 .elf"
    exit 1
}

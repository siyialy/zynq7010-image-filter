# =============================================================================
# build_led.tcl —— 上板点灯工程：综合 + 实现 + 生成 bit 流
#
# 用法（在 D:\FPGA比赛 目录下）：
#   D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\build_led.tcl
#
# 产物：
#   D:/fpga_build/led_board/led_board.runs/impl_1/board_top_led.bit
#
# 【重要：为什么要把源码拷到 D:/fpga_build 再编译】
#   Vivado 2018.3 在 Windows 上遇到**中文路径**（D:\FPGA比赛\...）做综合时会崩：
#       TclStackFree: incorrect freePtr. Call out of sequence?
#   而且它不给出可读的错误，直接 SYNTH ERROR，非常难排查。
#   所以本脚本先把源码复制到纯英文目录再建工程 —— 这是最省心的规避方式。
#   函数仿真不受影响（xsim 能处理中文路径），只有综合/实现要这么做。
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_files [list \
    [file join $proj_root src rtl key_debounce.v] \
    [file join $proj_root src rtl board_top_led.v] ]
set xdc_file [file join $proj_root constr pin_led.xdc]

# 纯英文暂存/构建目录
set stage_root "D:/fpga_build"
set stage_src  "$stage_root/led_src"
set proj_dir   "$stage_root/led_board"

puts "INFO: proj_root = $proj_root"
puts "INFO: stage_src = $stage_src"
puts "INFO: proj_dir  = $proj_dir"

foreach f $rtl_files { if {![file exists $f]} { error "missing source: $f" } }
if {![file exists $xdc_file]} { error "missing xdc: $xdc_file" }

# ---------------------------------------------------------------------------
# 0. 拷贝源码到纯英文路径
# ---------------------------------------------------------------------------
file mkdir $stage_src
foreach f $rtl_files {
    file copy -force $f $stage_src
    puts "INFO: staged [file tail $f]"
}
file copy -force $xdc_file $stage_src

if {[file exists $proj_dir]} { file delete -force $proj_dir }

# ---------------------------------------------------------------------------
# 1. 建工程
# ---------------------------------------------------------------------------
create_project -force led_board $proj_dir -part xc7z010clg400-1
add_files -norecurse [glob -directory $stage_src *.v]
add_files -fileset constrs_1 -norecurse [file join $stage_src pin_led.xdc]
set_property top board_top_led [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# 2. 综合
# ---------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth status = $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    puts "SYNTH FAILED. See $proj_dir/led_board.runs/synth_1/runme.log"
    exit 1
}

# ---------------------------------------------------------------------------
# 3. 实现 + 生成 bit
# ---------------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl status = $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    puts "IMPL FAILED. See $proj_dir/led_board.runs/impl_1/runme.log"
    exit 1
}

# ---------------------------------------------------------------------------
# 4. 报告
# ---------------------------------------------------------------------------
open_run impl_1

set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "=================================================="
puts "TIMING: WNS = $wns ns"
if {$wns < 0} {
    puts "TIMING: FAILED (negative slack)"
} else {
    puts "TIMING: OK (met)"
}
report_utilization -file [file join $proj_dir util.rpt]
puts "UTIL: [file join $proj_dir util.rpt]"

set bit_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_file [glob -nocomplain [file join $bit_dir *.bit]]
puts "BITSTREAM: $bit_file"
puts "=================================================="
puts "=== BUILD DONE ==="

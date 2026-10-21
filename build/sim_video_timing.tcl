# =============================================================================
# sim_video_timing.tcl —— 一键跑"视频时序 + 彩条"仿真
# 用法（在 D:\FPGA比赛 目录下）：
#   D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_video_timing.tcl
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_files [list \
    [file join $proj_root src rtl video_timing_gen.v] \
    [file join $proj_root src rtl test_pattern.v] ]

set tb_file [file join $proj_root src sim tb_video_timing.v]

if {[llength $argv] > 0} {
    set proj_dir [lindex $argv 0]
} else {
    set proj_dir [file join $proj_root build video_timing_sim]
}

puts "INFO: proj_dir = $proj_dir"
foreach f $rtl_files { if {![file exists $f]} { error "找不到源文件: $f" } }
if {![file exists $tb_file]} { error "找不到测试文件: $tb_file" }

file mkdir [file dirname $proj_dir]
if {[file exists $proj_dir]} { file delete -force $proj_dir }

create_project -force video_timing_sim $proj_dir -part xc7z010clg400-1
foreach f $rtl_files { add_files -norecurse $f }
add_files -fileset sim_1 -norecurse $tb_file

set_property top     video_timing_gen  [get_filesets sources_1]
set_property top     tb_video_timing   [get_filesets sim_1]
set_property top_lib xil_defaultlib    [get_filesets sim_1]
# GUI 里点 Run Simulation 时默认只跑 1000ns，设成 all 让它一次跑完
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all

puts "INFO: simulation finished"
close_sim -quiet
puts "=== TCL SCRIPT DONE ==="

# =============================================================================
# sim_img_filter.tcl —— 一键跑"3x3 卷积滤波核"的黄金参考对比仿真
# 用法（在 D:\FPGA比赛 目录下）：
#   D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_img_filter.tcl
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_file [file join $proj_root src rtl img_filter_3x3.v]
set tb_file  [file join $proj_root src sim tb_img_filter_3x3.v]

if {[llength $argv] > 0} {
    set proj_dir [lindex $argv 0]
} else {
    set proj_dir [file join $proj_root build img_filter_sim]
}

puts "INFO: proj_dir = $proj_dir"
if {![file exists $rtl_file]} { error "找不到源文件: $rtl_file" }
if {![file exists $tb_file]}  { error "找不到测试文件: $tb_file" }

file mkdir [file dirname $proj_dir]
if {[file exists $proj_dir]} { file delete -force $proj_dir }

create_project -force img_filter_sim $proj_dir -part xc7z010clg400-1
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file

set_property top     img_filter_3x3    [get_filesets sources_1]
set_property top     tb_img_filter_3x3 [get_filesets sim_1]
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

# 临时诊断脚本：量出滤波核的流水线偏移
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]
set proj_dir   [file join $proj_root build probe_sim]

file delete -force $proj_dir
create_project -force probe_sim $proj_dir -part xc7z010clg400-1
add_files -norecurse [file join $proj_root src rtl img_filter_3x3.v]
add_files -fileset sim_1 -norecurse [file join $proj_root src sim tb_probe.v]
set_property top     img_filter_3x3 [get_filesets sources_1]
set_property top     tb_probe       [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim -quiet

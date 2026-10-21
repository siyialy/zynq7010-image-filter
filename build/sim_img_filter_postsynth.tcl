# =============================================================================
# sim_img_filter_postsynth.tcl —— 综合后仿真（netlist）
#
# 目的：查"均值模式（mode 1）在硬件上全黑、但行为仿真正常"的问题。
#   - 行为仿真（RTL）  → mode 1 通过 2867 像素
#   - 硬件            → 全黑
# 用综合后的 netlist 再跑一遍同一个 testbench：
#   如果 netlist 仿真也失败 → 是综合（DSP 推断等）改变了逻辑，可以本地调试
#   如果 netlist 仿真通过   → 问题在实现/时序，要上 ILA 抓波形
# =============================================================================
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_file [file join $proj_root src rtl img_filter_3x3.v]
set tb_file  [file join $proj_root src sim tb_img_filter_3x3.v]

if {[llength $argv] > 0} {
    set proj_dir [lindex $argv 0]
} else {
    set proj_dir "D:/fpga_build/img_filter_postsynth"
}

puts "INFO: proj_dir = $proj_dir"
file mkdir [file dirname $proj_dir]
if {[file exists $proj_dir]} { file delete -force $proj_dir }

create_project -force img_filter_ps $proj_dir -part xc7z010clg400-1
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file
set_property top     img_filter_3x3    [get_filesets sources_1]
set_property top     tb_img_filter_3x3 [get_filesets sim_1]
set_property top_lib xil_defaultlib    [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---- 先综合 ----
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "INFO: synth = [get_property STATUS [get_runs synth_1]]"

# ---- 综合后功能仿真：跑的是 netlist ----
launch_simulation -mode post-synthesis -type functional -simset sim_1
run all
close_sim -quiet
puts "=== POST-SYNTH SIM DONE ==="

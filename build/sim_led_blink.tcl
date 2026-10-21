# =============================================================================
# sim_led_blink.tcl —— 一键创建仿真工程并跑第一个仿真
#
# 用法（在 D:\FPGA比赛 目录下打开 PowerShell 或 CMD）：
#   D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_led_blink.tcl
#
# 如果因为中文路径导致报错，把工程输出到纯英文目录：
#   D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\sim_led_blink.tcl -tclargs D:/fpga_build/led_sim
# =============================================================================

# 1. 根据脚本自身位置推算仓库根目录（这样仓库整体移动也不影响）
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_file [file join $proj_root src rtl led_blink.v]
set tb_file  [file join $proj_root src sim tb_led_blink.v]

# 2. 工程输出目录：默认在仓库 build/ 下，也可由命令行参数指定
if {[llength $argv] > 0} {
    set proj_dir [lindex $argv 0]
} else {
    set proj_dir [file join $proj_root build led_sim]
}

puts "INFO: proj_root = $proj_root"
puts "INFO: proj_dir  = $proj_dir"
if {![file exists $rtl_file]} { error "找不到源文件: $rtl_file" }
if {![file exists $tb_file]}  { error "找不到测试文件: $tb_file" }

# 3. 重建工程（每次从零开始，保证可复现）
file mkdir [file dirname $proj_dir]
if {[file exists $proj_dir]} { file delete -force $proj_dir }

create_project -force led_sim $proj_dir -part xc7z010clg400-1

# 4. 加入源文件与测试文件
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file

set_property top      led_blink    [get_filesets sources_1]
set_property top      tb_led_blink [get_filesets sim_1]
set_property top_lib  xil_defaultlib [get_filesets sim_1]
# GUI 里点 Run Simulation 时默认只跑 1000ns，设成 all 让它一次跑完
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# 5. 仿真：behavioral 层次，跑到底（testbench 里有 $finish）
launch_simulation -simset sim_1 -mode behavioral
run all

puts "INFO: simulation finished"
close_sim -quiet
puts "=== TCL SCRIPT DONE ==="

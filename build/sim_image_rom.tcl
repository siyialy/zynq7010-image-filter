# =============================================================================
# sim_image_rom.tcl —— 图片 ROM 图像源仿真
#   vivado -mode batch -source build\sim_image_rom.tcl
#
# 注意：$readmemh 按"仿真运行目录"解析相对路径，
#       所以这里在 run all 之前把 image_gray.mem 拷到 xsim 的运行目录。
# =============================================================================
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_file [file join $proj_root src rtl image_rom_src.v]
set tb_file  [file join $proj_root src sim tb_image_rom_src.v]
set mem_file [file join $proj_root src rtl image_gray.mem]

if {[llength $argv] > 0} {
    set proj_dir [lindex $argv 0]
} else {
    set proj_dir [file join $proj_root build image_rom_sim]
}

puts "INFO: proj_dir = $proj_dir"
foreach f [list $rtl_file $tb_file $mem_file] {
    if {![file exists $f]} { error "missing file: $f" }
}

file mkdir [file dirname $proj_dir]
if {[file exists $proj_dir]} { file delete -force $proj_dir }

create_project -force image_rom_sim $proj_dir -part xc7z010clg400-1
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file

set_property top     image_rom_src      [get_filesets sources_1]
set_property top     tb_image_rom_src   [get_filesets sim_1]
set_property top_lib xil_defaultlib     [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# $readmemh 在仿真时间 0 就执行，而 launch_simulation 会先跑 1000ns，
# 所以必须在 launch_simulation **之前** 把 .mem 放到 xsim 运行目录里。
set xsim_dir [file join $proj_dir image_rom_sim.sim sim_1 behav xsim]
file mkdir $xsim_dir
file copy -force $mem_file [file join $xsim_dir image_gray.mem]
puts "INFO: mem copied to $xsim_dir (before launch)"

launch_simulation -simset sim_1 -mode behavioral

run all

puts "INFO: simulation finished"
close_sim -quiet
puts "=== TCL SCRIPT DONE ==="

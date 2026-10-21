# =============================================================================
# sim_axil_regs.tcl —— 一键跑 AXI4-Lite 寄存器组仿真
#   vivado -mode batch -source build\sim_axil_regs.tcl
# =============================================================================
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_file [file join $proj_root src rtl axil_regs.v]
set tb_file  [file join $proj_root src sim tb_axil_regs.v]

if {[llength $argv] > 0} {
    set proj_dir [lindex $argv 0]
} else {
    set proj_dir [file join $proj_root build axil_sim]
}

puts "INFO: proj_dir = $proj_dir"
if {![file exists $rtl_file]} { error "missing source: $rtl_file" }
if {![file exists $tb_file]}  { error "missing tb: $tb_file" }

file mkdir [file dirname $proj_dir]
if {[file exists $proj_dir]} { file delete -force $proj_dir }

create_project -force axil_sim $proj_dir -part xc7z010clg400-1
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file

set_property top     axil_regs    [get_filesets sources_1]
set_property top     tb_axil_regs [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all

puts "INFO: simulation finished"
close_sim -quiet
puts "=== TCL SCRIPT DONE ==="

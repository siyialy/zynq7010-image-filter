set root [file dirname [file dirname [file normalize [info script]]]]
create_project display_hold D:/fpga_build/hold_[clock seconds] -part xc7z010clg400-1
foreach f [glob [file join $root src rtl *.v]] {add_files -norecurse $f}
add_files -fileset sim_1 -norecurse [file join $root src sim tb_display_hold.v]
set_property top tb_display_hold [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
close_sim
close_project

set root [file dirname [file dirname [file normalize [info script]]]]
set kind [lindex $argv 0]
set simroot "D:/fpga_build/pl_v22_${kind}_[clock seconds]"
create_project pl_v22 $simroot/project -part xc7z010clg400-1
add_files -norecurse [file join $root src rtl pl_pest_detector.v]
set_property verilog_define {PL_RELEASE_22} [get_filesets sources_1]
if {$kind eq "full"} {
    set bench tb_pl_detector_full
} elseif {$kind eq "many"} {
    set bench tb_pl_many_boxes
    add_files -norecurse [file join $root src rtl box_overlay.v]
} else { set bench tb_pl_pest_detector }
add_files -fileset sim_1 -norecurse [file join $root src sim $bench.v]
set_property verilog_define {PL_RELEASE_22} [get_filesets sim_1]
set_property top $bench [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set simdir [file join $simroot project pl_v22.sim sim_1 behav xsim]
file mkdir $simdir
foreach f [glob [file join $root build pl_detector_v22 ${kind}_vectors *.mem]] { file copy -force $f $simdir }
launch_simulation
close_sim
close_project

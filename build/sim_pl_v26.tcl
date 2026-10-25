set root [file dirname [file dirname [file normalize [info script]]]]
set kind [lindex $argv 0]
set simroot "D:/fpga_build/pl_v26_${kind}_[clock seconds]"
create_project pl_v26 $simroot/project -part xc7z010clg400-1
foreach name {pl_pest_engine_v25.v pl_candidate_fusion.v pl_detector_v25.v box_overlay.v} {add_files -norecurse [file join $root src rtl $name]}
set defs {PL_RELEASE_22 PL_RELEASE_23 PL_RELEASE_24 PL_RELEASE_25 PL_RELEASE_26}
set_property verilog_define $defs [get_filesets sources_1]
set bench [expr {$kind eq "full"?"tb_pl_v26_full":"tb_pl_v25_$kind"}]
add_files -fileset sim_1 -norecurse [file join $root src sim $bench.v]
set_property verilog_define $defs [get_filesets sim_1]
set_property top $bench [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set simdir [file join $simroot project pl_v26.sim sim_1 behav xsim]
file mkdir $simdir
foreach f [glob [file join $root build pl_detector_v26 vectors *.mem]] {file copy -force $f $simdir}
launch_simulation
close_sim
close_project

set root [file dirname [file dirname [file normalize [info script]]]]
set simroot "D:/fpga_build/pl_full_sim_[clock seconds]"
create_project pl_full_sim $simroot/project -part xc7z010clg400-1
add_files -norecurse [file join $root src rtl pl_pest_detector.v]
add_files -fileset sim_1 -norecurse [file join $root src sim tb_pl_detector_full.v]
set_property top tb_pl_detector_full [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set simdir [file join $simroot project pl_full_sim.sim sim_1 behav xsim]
file mkdir $simdir
foreach f [glob [file join $root build pl_detector_v21 full_vectors *.mem]] { file copy -force $f $simdir }
launch_simulation
close_sim
close_project

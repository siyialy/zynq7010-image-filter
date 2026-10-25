set root [file dirname [file dirname [file normalize [info script]]]]
set simroot "D:/fpga_build/pl_detector_sim_[clock seconds]"
file mkdir $simroot
create_project pl_detector_sim $simroot/project -part xc7z010clg400-1
add_files -norecurse [file join $root src rtl pl_pest_detector.v]
add_files -fileset sim_1 -norecurse [file join $root src sim tb_pl_pest_detector.v]
set_property top tb_pl_pest_detector [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set simdir [file join $simroot project pl_detector_sim.sim sim_1 behav xsim]
file mkdir $simdir
foreach f [glob [file join $root build pl_detector vectors *.mem]] { file copy -force $f $simdir }
launch_simulation
close_sim
puts "PL DETECTOR SIMULATION FINISHED: $simroot"
close_project

set root [file dirname [file dirname [file normalize [info script]]]]
set simroot "D:/fpga_build/cdc_frame_sim_[clock seconds]"
create_project cdc_frame_sim $simroot -part xc7z010clg400-1
add_files -norecurse [file join $root src rtl cdc_boxes.v]
add_files -fileset sim_1 -norecurse [file join $root src sim tb_cdc_boxes_frame.v]
set_property top tb_cdc_boxes_frame [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
close_sim
close_project

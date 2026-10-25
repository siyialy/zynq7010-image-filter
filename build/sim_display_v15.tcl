set root [file dirname [file dirname [file normalize [info script]]]]
set simroot "D:/fpga_build/display_sim_[clock seconds]"
file mkdir $simroot
foreach f [list [file join $root src rtl image_rom_src.v] [file join $root src sim tb_display_source.v]] {
    file copy -force $f $simroot
}
create_project display_sim $simroot/project -part xc7z010clg400-1
add_files -norecurse $simroot/image_rom_src.v
add_files -fileset sim_1 -norecurse $simroot/tb_display_source.v
set_property top tb_display_source [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
close_sim
puts "DISPLAY SOURCE SIMULATION FINISHED: $simroot"

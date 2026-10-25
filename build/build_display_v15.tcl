# Clone the working project. Never reset or delete the original project/runs.
set repo [file dirname [file dirname [file normalize [info script]]]]
set stamp [clock seconds]
set destination "D:/fpga_build/display_v15_$stamp"
set staged "D:/fpga_build/display_v15_src_$stamp"
if {[file exists $destination] || [file exists $staged]} { error "Build destination already exists" }
file mkdir $staged
set changed {image_rom_src.v img_buf.v video_pipeline.v system_top.v}
foreach name $changed {
    file copy [file join $repo src rtl $name] [file join $staged $name]
}
open_project D:/fpga_build/sys/sys.xpr
save_project_as sys_display_v15 $destination
foreach name $changed {
    set old [get_files -all -quiet *$name]
    if {[llength $old] != 1} { error "Expected one project source for $name, got $old" }
    remove_files $old
    add_files -norecurse [file join $staged $name]
}
set_property top system_top [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
# readmemh resolves against the synthesis working directory; a cloned project
# does not inherit the original run folder's manually staged memory image.
set synth_dir [get_property DIRECTORY [get_runs synth_1]]
file mkdir $synth_dir
file copy -force [file join $repo src rtl image_gray.mem] [file join $synth_dir image_gray.mem]
file copy -force [file join $repo src rtl image_gray.mem] [file join $destination image_gray.mem]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[string first "Complete" [get_property STATUS [get_runs synth_1]]] < 0} { error "Synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[string first "Complete" [get_property STATUS [get_runs impl_1]]] < 0} { error "Implementation failed" }
open_run impl_1
report_timing_summary -file $destination/display_timing.rpt
report_utilization -file $destination/display_utilization.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "DISPLAY TIMING WNS: $wns ns"
if {$wns < 0} { error "Timing is not closed; do not program this build" }
set bit [file join [get_property DIRECTORY [get_runs impl_1]] system_top.bit]
file copy -force $bit D:/fpga_build/bits/system_top_v1_5.bit
puts "DISPLAY BUILD DONE: $destination"
puts "DISPLAY BITSTREAM: D:/fpga_build/bits/system_top_v1_5.bit"
close_project

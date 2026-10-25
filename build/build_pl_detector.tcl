# Build a separate recoverable project; keep all previous bitstreams intact.
set repo [file dirname [file dirname [file normalize [info script]]]]
set version 2_4
if {[llength $argv] > 0} { set version [lindex $argv 0] }
if {$version ni {2_0 2_1 2_2 2_3 2_4 2_5 2_6}} { error "Unsupported release: $version" }
set folder [expr {$version eq "2_6"?"pl_detector_v26":$version eq "2_5"?"pl_detector_v25":$version eq "2_4"?"pl_detector_v24":$version eq "2_3" ? "pl_detector_v23" : ($version eq "2_2" ? "pl_detector_v22" : ($version eq "2_1" ? "pl_detector_v21" : "pl_detector"))} ]
set output_dir [file join $repo build $folder]
file mkdir $output_dir
set stamp [clock seconds]
set destination "D:/fpga_build/pl_detector_$stamp"
set staged "D:/fpga_build/pl_detector_src_$stamp"
file mkdir $staged
set changed {image_rom_src.v img_buf.v video_pipeline.v system_top.v cdc_boxes.v box_overlay.v}
foreach name [concat $changed {pl_pest_detector.v}] {
    file copy [file join $repo src rtl $name] [file join $staged $name]
}
if {$version in {2_5 2_6}} {
    foreach name {pl_pest_engine_v25.v pl_candidate_fusion.v pl_detector_v25.v} {
        file copy [file join $repo src rtl $name] [file join $staged $name]
    }
}
open_project D:/fpga_build/sys/sys.xpr
save_project_as sys_pl_detector $destination
foreach name $changed {
    set old [get_files -all -quiet *$name]
    if {[llength $old] != 1} { error "Expected one source $name, got $old" }
    remove_files $old
    add_files -norecurse [file join $staged $name]
}
add_files -norecurse [file join $staged pl_pest_detector.v]
if {$version in {2_2 2_3 2_4 2_5 2_6}} { set_property verilog_define {PL_RELEASE_22} [get_filesets sources_1] }
if {$version in {2_3 2_4}} { set_property verilog_define {PL_RELEASE_22 PL_RELEASE_23} [get_filesets sources_1] }
if {$version eq "2_4"} { set_property verilog_define {PL_RELEASE_22 PL_RELEASE_23 PL_RELEASE_24} [get_filesets sources_1] }
if {$version in {2_5 2_6}} {
    foreach name {pl_pest_engine_v25.v pl_candidate_fusion.v pl_detector_v25.v} {add_files -norecurse [file join $staged $name]}
    set_property verilog_define {PL_RELEASE_22 PL_RELEASE_23 PL_RELEASE_24 PL_RELEASE_25} [get_filesets sources_1]
}
if {$version eq "2_6"} {set_property verilog_define {PL_RELEASE_22 PL_RELEASE_23 PL_RELEASE_24 PL_RELEASE_25 PL_RELEASE_26} [get_filesets sources_1]}
set_property top system_top [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
set synth_dir [get_property DIRECTORY [get_runs synth_1]]
file mkdir $synth_dir
file copy -force [file join $repo src rtl image_gray.mem] [file join $synth_dir image_gray.mem]
file copy -force [file join $repo src rtl image_gray.mem] [file join $destination image_gray.mem]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[string first "Complete" [get_property STATUS [get_runs synth_1]]] < 0} { error "Synthesis failed" }
open_run synth_1
report_utilization -file $destination/detector_synth_utilization.rpt
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[string first "Complete" [get_property STATUS [get_runs impl_1]]] < 0} { error "Implementation failed" }
open_run impl_1
report_timing_summary -file $destination/detector_timing.rpt
report_utilization -file $destination/detector_utilization.rpt
report_drc -file $destination/detector_drc.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "PL DETECTOR TIMING WNS: $wns ns"
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {($wns<0 || $whs<0) && $version in {2_1 2_2 2_3 2_4 2_5 2_6} && $wns>-0.5 && $whs>-0.2} {
    close_design
    set saved_argv $argv
    set argv [list $destination $version]
    set timing_result [catch {source [file join $repo build finish_pl_detector_timing.tcl]} timing_message]
    if {$timing_result != 0} {
        if {$version eq "2_6"} {
            set argv [list $destination $version]
            source [file join $repo build finish_pl_detector_incremental.tcl]
            set argv $saved_argv
            return
        }
        error $timing_message
    }
    set argv $saved_argv
    close_project
    return
}
if {$wns < 0 || $whs < 0} { error "Setup/hold timing failed; do not program" }
set bit [file join [get_property DIRECTORY [get_runs impl_1]] system_top.bit]
file copy -force $bit D:/fpga_build/bits/system_top_v$version.bit
set manifest [open [file join $output_dir build_path.txt] w]
puts $manifest $destination
close $manifest
puts "PL DETECTOR BUILD DONE: $destination"
close_project

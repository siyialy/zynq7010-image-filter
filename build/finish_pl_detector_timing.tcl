# Post-route physical optimization. Never relax timing constraints or publish
# a bitstream with failing setup/hold paths.
set repo [file dirname [file dirname [file normalize [info script]]]]
set project [lindex $argv 0]
set version 2_1
if {[llength $argv]>1} { set version [lindex $argv 1] }
set folder [expr {$version eq "2_6"?"pl_detector_v26":$version eq "2_5"?"pl_detector_v25":$version eq "2_4"?"pl_detector_v24":$version eq "2_3"?"pl_detector_v23":($version eq "2_2"?"pl_detector_v22":"pl_detector_v21")}]
open_checkpoint [file join $project sys_pl_detector.runs impl_1 system_top_routed.dcp]
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
report_timing_summary -file [file join $project detector_timing_final.rpt]
report_utilization -file [file join $project detector_utilization_final.rpt]
report_drc -file [file join $project detector_drc_final.rpt]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "FINAL SETUP: $setup ns; FINAL HOLD: $hold ns"
if {$setup<0 || $hold<0} { error "Final timing failed; bitstream not published" }
write_checkpoint -force [file join $project detector_timing_closed.dcp]
write_bitstream -force [file join $project system_top_fast_final.bit]
file copy -force [file join $project system_top_fast_final.bit] D:/fpga_build/bits/system_top_v$version.bit
set output [open [file join $repo build $folder build_path.txt] w]
puts $output $project
close $output
puts "TIMING-CLOSED FAST BITSTREAM READY"
close_design

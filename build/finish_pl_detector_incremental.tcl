# Reuse the verified v2.5 physical design for the small v2.6 shadow gate.
# Setup and hold checks remain mandatory; never publish a failing bitstream.
set incr_repo [file dirname [file dirname [file normalize [info script]]]]
set incr_project [lindex $argv 0]
set incr_version [lindex $argv 1]
if {$incr_version ne "2_6"} {error "Incremental shadow-fix flow is only defined for v2.6"}
set base_file [open [file join $incr_repo build pl_detector_v25 build_path.txt] r]
set base_project [string trim [read $base_file]]
close $base_file
set base_checkpoint [file join $base_project detector_timing_closed.dcp]
if {![file exists $base_checkpoint]} {error "Verified v2.5 timing checkpoint unavailable"}
catch {close_design}
catch {close_project}
open_project [file join $incr_project sys_pl_detector.xpr]
set incr_run "impl_shadow_[clock seconds]"
create_run $incr_run -parent_run synth_1 -flow [get_property FLOW [get_runs impl_1]] -strategy [get_property STRATEGY [get_runs impl_1]] -constrset [get_property CONSTRSET [get_runs impl_1]]
set_property INCREMENTAL_CHECKPOINT $base_checkpoint [get_runs $incr_run]
puts "V26 INCREMENTAL BASE: $base_checkpoint"
launch_runs $incr_run -to_step route_design -jobs 4
wait_on_run $incr_run
if {[string first "Complete" [get_property STATUS [get_runs $incr_run]]] < 0} {error "Incremental implementation failed"}
open_run $incr_run
set incr_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set incr_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$incr_setup<0 || $incr_hold<0} {
    phys_opt_design -directive AggressiveExplore
    route_design -directive Explore
}
report_timing_summary -file [file join $incr_project detector_timing_final.rpt]
report_utilization -file [file join $incr_project detector_utilization_final.rpt]
report_drc -file [file join $incr_project detector_drc_final.rpt]
set incr_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set incr_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "INCREMENTAL FINAL SETUP: $incr_setup ns; HOLD: $incr_hold ns"
if {$incr_setup<0 || $incr_hold<0} {error "Incremental setup/hold failed; bitstream not published"}
write_checkpoint -force [file join $incr_project detector_timing_closed.dcp]
write_bitstream -force [file join $incr_project system_top_incremental_final.bit]
file copy -force [file join $incr_project system_top_incremental_final.bit] D:/fpga_build/bits/system_top_v${incr_version}.bit
set out_file [open [file join $incr_repo build pl_detector_v26 build_path.txt] w]
puts $out_file $incr_project
close $out_file
puts "V26 INCREMENTAL TIMING-CLOSED BITSTREAM READY"
close_project

set project [lindex $argv 0]
open_checkpoint [file join $project sys_pl_detector.runs synth_1 system_top.dcp]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $project synth_hierarchy.rpt]
close_design

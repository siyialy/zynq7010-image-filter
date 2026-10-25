open_checkpoint [lindex $argv 0]
report_timing -max_paths 5 -file [lindex $argv 1]
close_design

# =============================================================================
# build_hdmi.tcl —— HDMI 输出工程（720p60，彩条 + 3x3 滤波）
#
# 用法（在 D:\FPGA比赛 目录下）：
#   D:\XILINX\Vivado\2018.3\bin\vivado.bat -mode batch -source build\build_hdmi.tcl
#
# 产物：
#   D:/fpga_build/hdmi/hdmi.runs/impl_1/hdmi_top.bit
#
# 说明：
#   1. 源码先拷到纯英文目录（中文路径会让 Vivado 综合崩溃）
#   2. clk_wiz 用 Tcl 现场创建，保证任何机器都能重建（不依赖 .xci 文件）
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set rtl_files [list \
    [file join $proj_root src rtl key_debounce.v] \
    [file join $proj_root src rtl video_timing_gen.v] \
    [file join $proj_root src rtl test_pattern.v] \
    [file join $proj_root src rtl img_filter_3x3.v] \
    [file join $proj_root src rtl image_rom_src.v] \
    [file join $proj_root src rtl video_pipeline.v] \
    [file join $proj_root src rtl asyn_rst_syn.v] \
    [file join $proj_root src rtl dvi_encoder.v] \
    [file join $proj_root src rtl serializer_10_to_1.v] \
    [file join $proj_root src rtl dvi_transmitter_top.v] \
    [file join $proj_root src rtl hdmi_top.v] ]
set xdc_file [file join $proj_root constr pin_hdmi.xdc]

set stage_root "D:/fpga_build"
set stage_src  "$stage_root/hdmi_src"
set proj_dir   "$stage_root/hdmi"

puts "INFO: proj_root = $proj_root"
puts "INFO: proj_dir  = $proj_dir"

foreach f $rtl_files { if {![file exists $f]} { error "missing source: $f" } }
if {![file exists $xdc_file]} { error "missing xdc: $xdc_file" }

# ---------------------------------------------------------------------------
# 0. 暂存到纯英文路径
# ---------------------------------------------------------------------------
file mkdir $stage_src
foreach f $rtl_files {
    file copy -force $f $stage_src
    puts "INFO: staged [file tail $f]"
}
file copy -force $xdc_file $stage_src

if {[file exists $proj_dir]} { file delete -force $proj_dir }

# ---------------------------------------------------------------------------
# 1. 建工程
# ---------------------------------------------------------------------------
create_project -force hdmi $proj_dir -part xc7z010clg400-1
add_files -norecurse [glob -directory $stage_src *.v]
add_files -fileset constrs_1 -norecurse [file join $stage_src pin_hdmi.xdc]
set_property top hdmi_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# 2. 生成时钟 IP：50MHz → 75MHz(像素) + 375MHz(5x)
#    MMCM: VCO = 50 x 22.5 = 1125MHz
#          clk_out1 = 1125/15 = 75MHz
#          clk_out2 = 1125/3  = 375MHz
# ---------------------------------------------------------------------------
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0 -dir $stage_src
set_property -dict [list \
    CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {50.000} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {75.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {375.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
    CONFIG.RESET_PORT {reset} \
    CONFIG.PRIMITIVE {MMCM} \
] [get_ips clk_wiz_0]

generate_target {synthesis implementation simulation} [get_ips clk_wiz_0]
puts "INFO: clk_wiz_0 generated"

update_compile_order -fileset sources_1

# 综合时 $readmemh 也按运行目录找文件，先拷到 synth 运行目录
set mem_file [file join $proj_root src rtl image_gray.mem]
if {[file exists $mem_file]} {
    set synth_dir [file join $proj_dir hdmi.runs synth_1]
    file mkdir $synth_dir
    file copy -force $mem_file [file join $synth_dir image_gray.mem]
    file copy -force $mem_file [file join $proj_dir image_gray.mem]
    puts "INFO: image_gray.mem copied to synth dir"
} else {
    puts "WARNING: image_gray.mem not found - image source will be blank"
}

# ---------------------------------------------------------------------------
# 3. 综合
# ---------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth status = $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    puts "SYNTH FAILED. See $proj_dir/hdmi.runs/synth_1/runme.log"
    exit 1
}

# ---------------------------------------------------------------------------
# 4. 实现 + bit
# ---------------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl status = $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    puts "IMPL FAILED. See $proj_dir/hdmi.runs/impl_1/runme.log"
    exit 1
}

# ---------------------------------------------------------------------------
# 5. 报告
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 5. reports (wrapped in catch: bitstream is already written by now)
# ---------------------------------------------------------------------------
if {[catch {
    open_run impl_1
    set wns [get_property SLACK [get_timing_paths -delay_type max]]
    puts "=================================================="
    puts "TIMING: WNS = $wns ns"
    if {$wns < 0} {
        puts "TIMING: FAILED (negative slack)"
    } else {
        puts "TIMING: OK (met)"
    }
    report_utilization -file [file join $proj_dir util.rpt]
    set bdir [get_property DIRECTORY [get_runs impl_1]]
    puts "BITSTREAM: [glob -nocomplain [file join $bdir *.bit]]"
} err]} {
    puts "INFO: report step failed (bitstream may still be fine): $err"
}
puts "=================================================="
puts "=== BUILD DONE ==="

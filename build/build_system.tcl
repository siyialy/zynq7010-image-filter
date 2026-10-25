# =============================================================================
# build_system.tcl —— Zynq 系统（PS + PL 协同）完整构建
#
# 用法：
#   vivado -mode batch -source build\build_system.tcl            # 完整流程（出 bit + xsa）
#   vivado -mode batch -source build\build_system.tcl -tclargs bd_only   # 只建 Block Design（快速验证）
#
# Block Design 内容：
#   PS7 (ARM + DDR3 512MB + UART0@MIO14/15)
#     └─ M_AXI_GP0 ── AXI Interconnect ── axil_regs（我们自己写的寄存器组）
#   对外引出：FCLK_CLK0、peripheral_aresetn、mode/threshold/filter_en/frame_cnt/status
# =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file dirname $script_dir]

set bd_only 0
if {[llength $argv] > 0 && [lindex $argv 0] eq "bd_only"} { set bd_only 1 }

set rtl_files [list \
    [file join $proj_root src rtl axil_regs.v] \
    [file join $proj_root src rtl key_debounce.v] \
    [file join $proj_root src rtl video_timing_gen.v] \
    [file join $proj_root src rtl test_pattern.v] \
    [file join $proj_root src rtl img_filter_3x3.v] \
    [file join $proj_root src rtl img_buf.v] \
    [file join $proj_root src rtl pl_pest_detector.v] \
    [file join $proj_root src rtl image_rom_src.v] \
    [file join $proj_root src rtl box_overlay.v] \
    [file join $proj_root src rtl video_pipeline.v] \
    [file join $proj_root src rtl cdc_cfg.v] \
    [file join $proj_root src rtl cdc_boxes.v] \
    [file join $proj_root src rtl cdc_frame_cnt.v] \
    [file join $proj_root src rtl asyn_rst_syn.v] \
    [file join $proj_root src rtl dvi_encoder.v] \
    [file join $proj_root src rtl serializer_10_to_1.v] \
    [file join $proj_root src rtl dvi_transmitter_top.v] \
    [file join $proj_root src rtl system_top.v] ]

set xdc_file [file join $proj_root constr pin_hdmi.xdc]
set xdc_timing [file join $proj_root constr sys_timing.xdc]
set mem_file [file join $proj_root src rtl image_gray.mem]

set stage_root "D:/fpga_build"
set stage_src  "$stage_root/sys_src"
set proj_dir   "$stage_root/sys"

puts "INFO: bd_only  = $bd_only"
puts "INFO: proj_dir = $proj_dir"

# ---------------------------------------------------------------------------
# 0. 暂存到纯英文路径
# ---------------------------------------------------------------------------
file mkdir $stage_src
foreach f $rtl_files {
    if {![file exists $f]} { error "missing source: $f" }
    file copy -force $f $stage_src
}
file copy -force $xdc_file $stage_src
if {[file exists $xdc_timing]} { file copy -force $xdc_timing $stage_src }
if {[file exists $mem_file]} { file copy -force $mem_file $stage_src }

if {[file exists $proj_dir]} { file delete -force $proj_dir }

# ---------------------------------------------------------------------------
# 1. 建工程
# ---------------------------------------------------------------------------
create_project -force sys $proj_dir -part xc7z010clg400-1
add_files -norecurse [glob -directory $stage_src *.v]

# ---------------------------------------------------------------------------
# 2. 建 Block Design
# ---------------------------------------------------------------------------
create_bd_design "system"

# ---- PS7 ----
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0

set_property -dict [list \
    CONFIG.PCW_IMPORT_BOARD_PRESET {None} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] [get_bd_cells ps7_0]

# ---- 把 DDR / FIXED_IO 引到 BD 外部 ----
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable"} \
    [get_bd_cells ps7_0]

# ---- 我们的 AXI4-Lite 寄存器组（作为 RTL 模块加进 BD）----
create_bd_cell -type module -reference axil_regs axil_regs_0

# ---- 用 automation 自动生成 AXI Interconnect 并连好时钟/复位 ----
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
              Master {/ps7_0/M_AXI_GP0} Slave {/axil_regs_0/S_AXI} \
              ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0} } \
    [get_bd_intf_pins axil_regs_0/S_AXI]

# ---- 用户寄存器引出到 BD 外（名字会带 _0 后缀，下面改名）----
set bd_user_pins {mode threshold filter_en frame_cnt status \
                  img_we img_addr img_data box_bus commit_tog}
foreach p $bd_user_pins {
    make_bd_pins_external [get_bd_pins axil_regs_0/$p]
}
foreach p $bd_user_pins {
    set np [get_bd_ports -quiet ${p}_0]
    if {[llength $np] > 0} { set_property name $p $np }
}

# ---- 时钟/复位：FCLK 和 reset 已经连到互连器，不能再 make_external，
#      改用 create_bd_port + connect_bd_net 挂到同一条网络上 ----
create_bd_port -dir O -type clk axi_clk
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_ports axi_clk]

set rst_cells [get_bd_cells -quiet -filter {VLNV =~ "*proc_sys_reset*"}]
if {[llength $rst_cells] == 0} { error "automation did not create proc_sys_reset" }
create_bd_port -dir O -type rst axi_rst_n
connect_bd_net [get_bd_pins [lindex $rst_cells 0]/peripheral_aresetn] [get_bd_ports axi_rst_n]

regenerate_bd_layout
validate_bd_design

save_bd_design
puts "INFO: block design validated"

# ---- 生成 wrapper ----
set bd_file [get_files system.bd]
make_wrapper -files $bd_file -top
# 2018.3 把 wrapper 生成在 *.srcs 下（不是 *.gen），两个位置都找一下
set wrp [glob -nocomplain [file join $proj_dir sys.srcs sources_1 bd system hdl system_wrapper.v]]
if {[llength $wrp] == 0} {
    set wrp [glob -nocomplain [file join $proj_dir sys.gen sources_1 bd system hdl system_wrapper.v]]
}
if {[llength $wrp] == 0} { error "make_wrapper 没生成 system_wrapper.v" }
add_files -norecurse [lindex $wrp 0]
puts "INFO: wrapper = [lindex $wrp 0]"

# ---------------------------------------------------------------------------
# 3. 时钟 IP + 约束 + 顶层
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

add_files -fileset constrs_1 -norecurse [file join $stage_src pin_hdmi.xdc]
if {[file exists [file join $stage_src sys_timing.xdc]]} { add_files -fileset constrs_1 -norecurse [file join $stage_src sys_timing.xdc] }
set_property top system_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# 综合时 $readmemh 需要 .mem 在运行目录
set synth_dir [file join $proj_dir sys.runs synth_1]
file mkdir $synth_dir
file copy -force $mem_file [file join $synth_dir image_gray.mem]
file copy -force $mem_file [file join $proj_dir image_gray.mem]
puts "INFO: image_gray.mem copied"

if {$bd_only} {
    puts "=== BD ONLY DONE (block design + wrapper ok) ==="
    exit 0
}

# ---------------------------------------------------------------------------
# 4. 综合 / 实现 / bit
# ---------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth status = $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    puts "SYNTH FAILED. See $proj_dir/sys.runs/synth_1/runme.log"
    exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl status = $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    puts "IMPL FAILED. See $proj_dir/sys.runs/impl_1/runme.log"
    exit 1
}

# ---------------------------------------------------------------------------
# 5. 导出 .xsa（给 SDK/Vitis 用）
# ---------------------------------------------------------------------------
write_hwdef -force [file join $proj_dir system.hwdef]
write_sysdef -hwdef [file join $proj_dir system.hwdef] \
              -bitfile [file join $proj_dir sys.runs impl_1 system_top.bit] \
              -file [file join $proj_dir system.hdf] -force
puts "INFO: hdf exported (for SDK 2018.3)"

if {[catch {
    open_run impl_1
    set wns [get_property SLACK [get_timing_paths -delay_type max]]
    puts "TIMING: WNS = $wns ns"
} err]} { puts "INFO: report step: $err" }

puts "=== SYSTEM BUILD DONE ==="

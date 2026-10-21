# =============================================================================
# run_app.tcl —— 一键把 bit 流 + ARM 程序下载到板子并运行
#
# 用法（在 D:\FPGA比赛 目录下）：
#   D:\XILINX\SDK\2018.3\bin\xsct.bat build\run_app.tcl
#
# 前提：
#   1. 板子上电、JTAG 排线接好、BOOT CFG = ON/ON
#   2. Vivado 的 Hardware Manager 已经关闭（否则硬件被占用，xsct 连不上）
#   3. USB 串口线接在板子 "USB UART" 口
#   4. 串口终端：115200, 8-N-1
# =============================================================================

set bit "D:/fpga_build/bits/system_top.bit"
set elf "D:/fpga_build/sdk_ws/img_filter_app/Release/img_filter_app.elf"
if {![file exists $elf]} {
    set elf "D:/fpga_build/sdk_ws/img_filter_app/Debug/img_filter_app.elf"
    puts "INFO: Release ELF not found, using Debug"
} else {
    puts "INFO: using Release ELF (-O2)"
}

foreach f [list $bit $elf] {
    if {![file exists $f]} { puts "ERROR: missing $f"; exit 1 }
}

puts "=== connecting to hw_server ==="
connect

puts "=== targets ==="
puts [targets]

# Zynq 的 APU（ARM 核）
targets -set -nocase -filter {name =~ "*APU*"}
puts "=== system reset ==="
rst -system
after 3000

# 初始化 PS（DDR3、时钟、MIO）—— 不做这一步，dow ELF 会报
# "Cannot access DDR: the controller is held in reset"
set ps7_init "D:/fpga_build/sdk_ws/hw0/ps7_init.tcl"
if {![file exists $ps7_init]} { puts "ERROR: missing $ps7_init"; exit 1 }
puts "=== ps7_init (DDR / clocks / MIO) ==="
source $ps7_init
targets -set -nocase -filter {name =~ "*APU*"}
ps7_init
ps7_post_config
after 1000

# 下载 PL bit 流
puts "=== programming PL ==="
targets -set -nocase -filter {name =~ "*APU*"}
fpga $bit
after 2000

# 下载 ARM 程序并运行
puts "=== downloading ELF ==="
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
dow $elf

puts "=== running ==="
con

puts ""
puts "======================================================"
puts " APP IS RUNNING."
puts " Open a serial terminal on the USB-UART port:"
puts "   115200 bps, 8 data bits, no parity, 1 stop bit"
puts " You should see the menu:"
puts "   0/1/2/3 : filter mode    h : hw fps    c : sw baseline"
puts "======================================================"

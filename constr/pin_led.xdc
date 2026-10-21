# =============================================================================
# pin_led.xdc —— 上板点灯工程的引脚约束（正点原子启明星 ZYNQ7010 V2）
#
# 引脚来源：官方 PHOSPHOR_ZYNQ_IO.xdc + 《启明星ZYNQ开发板 IO引脚分配总表.xlsx》
# 全部 LVCMOS33，bank 电压 3.3V
#
# 注意：这里只保留本工程用到的端口。官方那个 xdc 里有 LCD/HDMI/摄像头等
# 全部端口约束，如果直接拿来用，Vivado 会因为"找不到对应端口"报 ERROR。
# =============================================================================

#------------------------ 系统时钟 50MHz ------------------------
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

#------------------------ PL 复位按键（低有效）------------------------
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]

#------------------------ 2 个 PL 按键 ------------------------
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {key[0]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {key[1]}]

#------------------------ 2 个底板 PL LED ------------------------
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]

# 说明：CFGBVS/CONFIG_VOLTAGE 由 build_led.tcl 在工程里设置，
# 写在这里会导致综合阶段读约束时报 current_design 找不到。

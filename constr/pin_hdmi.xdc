# =============================================================================
# pin_hdmi.xdc —— HDMI 输出工程引脚约束（启明星 ZYNQ7010 V2）
#
# 引脚来源：
#   1. 官方 PHOSPHOR_ZYNQ_IO.xdc
#   2. 《启明星ZYNQ开发板 IO引脚分配总表.xlsx》
#   3. 启明星ZYNQ底板原理图_V2.3.2.pdf（TMDS 差分对的 N 侧）
#   4. 官方例程 22_hdmi_colorbar 的 hdmi_colorbar.xdc
# =============================================================================

#------------------------ 系统时钟 50MHz ------------------------
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

#------------------------ PL 复位按键 ------------------------
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]

#------------------------ PL 按键 / LED ------------------------
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {key[0]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {key[1]}]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]

#------------------------ HDMI TMDS 数据通道 ------------------------
# D2 通道：P=J20  N=H20
set_property -dict {PACKAGE_PIN J20 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[2]}]
set_property -dict {PACKAGE_PIN H20 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[2]}]
# D1 通道：P=K19  N=J19
set_property -dict {PACKAGE_PIN K19 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[1]}]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[1]}]
# D0 通道：P=G19  N=G20
set_property -dict {PACKAGE_PIN G19 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[0]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[0]}]
# 时钟通道：P=J18  N=H18
set_property -dict {PACKAGE_PIN J18 IOSTANDARD TMDS_33} [get_ports tmds_clk_p]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD TMDS_33} [get_ports tmds_clk_n]

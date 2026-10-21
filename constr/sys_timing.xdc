# ============================================================================
# sys_timing.xdc —— Zynq 系统的时钟约束
#
# 【为什么要这个文件】
#   本设计里有 4 个时钟，分属 3 个完全异步的域：
#     - sys_clk(50MHz, 外部晶振)  → clk_wiz 产生 75MHz(像素) / 375MHz(TMDS)
#     - clk_fpga_0(100MHz, PS 的 FCLK_CLK0) → AXI 总线
#
#   跨域的两条路：
#     mode/threshold/filter_en : 100MHz → 75MHz
#     帧计数 toggle            : 75MHz  → 100MHz
#
#   这两条路都是用两级触发器同步的（同步器本身就是为了处理异步），
#   所以**不应该**让 Vivado 按"同步时序"去分析它们——否则它会拿一个
#   毫无意义的公共周期（比如 3.333ns）来要求，然后报出假违例。
#
#   不加这个约束时的真实报错：
#     Slack (VIOLATED): -0.291ns
#     Source: u_frm/tog_pix_reg      (clk_out1, 75MHz)
#     Destination: u_frm/tog_sync_reg[0] (clk_fpga_0, 100MHz)
#   这就是典型的"假违例"——跨异步域本来就不该有建立时间要求。
# ============================================================================

# ---- 声明三组时钟互不相关（异步）----
# 注意：不能用通配符把 clk_out1/clk_out2 合并（它们同源，彼此是同步的）
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_fpga_0] \
    -group [get_clocks -include_generated_clocks clk_out1_clk_wiz_0] \
    -group [get_clocks -include_generated_clocks clk_out2_clk_wiz_0]

# ---- 跨域路径加最大延迟约束（防止工具把它们优化掉/过度优化）----
# 这两条不是"任意路径"，而是"经过同步器的数据"，给一个宽松上限即可
set_max_delay -datapath_only -from [get_clocks clk_out1_clk_wiz_0] \
    -to [get_clocks clk_fpga_0] 10.000
set_max_delay -datapath_only -from [get_clocks clk_fpga_0] \
    -to [get_clocks clk_out1_clk_wiz_0] 10.000

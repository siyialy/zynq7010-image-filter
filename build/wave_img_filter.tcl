# =============================================================================
# wave_img_filter.tcl —— 一键加信号 + 跑完仿真 + 缩放
#
# 用法（Vivado 的 Tcl Console 里，仿真已经启动的情况下）：
#   source D:/FPGA比赛/build/wave_img_filter.tcl
#
# 它做三件事：
#   1. 只加"有用的信号"（不加 testbench 里那几个巨大的像素存储数组）
#   2. run all —— 跑完整个仿真，不然会停在默认的 1000ns
#   3. 缩放到全局
#
# 说明：每条 add_wave 都包了 catch，万一某个信号名不对也只是跳过，
#       不会让整个脚本中断。
#
# 为什么不要加 cap_d / cap_x / cap_y：
#   它们是 testbench 里存 4 帧像素的数组（9 万~19 万 bit），
#   加进波形会报 "exceeds the display limit of 65536 bits" —— 那是正常的，跳过即可。
# =============================================================================

proc w {sig} {
    if {[catch {add_wave $sig} err]} {
        puts "skip $sig : $err"
    }
}

# ---------- 输入侧 ----------
catch { add_wave_divider "INPUT" }
w /tb_img_filter_3x3/clk
w /tb_img_filter_3x3/rst_n
w /tb_img_filter_3x3/mode
w /tb_img_filter_3x3/in_de
w /tb_img_filter_3x3/in_x
w /tb_img_filter_3x3/in_y
w /tb_img_filter_3x3/in_rgb

# ---------- 输出侧（滤波结果） ----------
catch { add_wave_divider "OUTPUT (filtered)" }
w /tb_img_filter_3x3/out_de
w /tb_img_filter_3x3/out_x
w /tb_img_filter_3x3/out_y
w /tb_img_filter_3x3/out_rgb

# ---------- 跑完整个仿真 ----------
puts "=== running to completion ... ==="
run all
catch { zoom fit }
puts "=== done: 看 Tcl Console 里的 PASS 行 ==="

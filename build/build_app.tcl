# =============================================================================
# build_app.tcl —— 用 SDK 2018.3 批量创建 BSP + 编译 PS 端 C 程序
#
# 用法（先跑完 build_system.tcl，确保有 system.hdf）：
#   D:\XILINX\SDK\2018.3\bin\xsdk.bat -batch -source build\build_app.tcl
#
# 产物：
#   D:/fpga_build/sdk_ws/img_filter_app/Debug/img_filter_app.elf
# =============================================================================

set hdf "D:/fpga_build/sys/system.hdf"
set ws  "D:/fpga_build/sdk_ws"
set src "D:/fpga_build/ps_src"

if {![file exists $hdf]} {
    puts "ERROR: 找不到 $hdf，先跑 build_system.tcl"
    exit 1
}
if {![file exists $src]} {
    puts "ERROR: 找不到源码目录 $src（应包含 main.c / sw_filter.c / sw_filter.h）"
    exit 1
}

file mkdir $ws
setws $ws

# ---- 硬件平台 / BSP / 应用：用 catch 重复执行也不报错 ----
if {[catch {createhw -name hw0 -hwspec $hdf} err]} {
    puts "INFO: createhw skipped ($err)"
} else { puts "INFO: hardware project created" }

if {[catch {createbsp -name bsp0 -hwproject hw0 -proc ps7_cortexa9_0 -os standalone} err]} {
    puts "INFO: createbsp skipped ($err)"
} else { puts "INFO: bsp created" }

if {[catch {createapp -name img_filter_app -hwproject hw0 -proc ps7_cortexa9_0 -os standalone -lang C -app {Empty Application}} err]} {
    puts "INFO: app create skipped ($err)"
} else { puts "INFO: app created" }

# 直接拷源码到应用的 src 目录（比 importsources 更稳，各版本 SDK 都适用）
set app_src [file join $ws img_filter_app src]
file mkdir $app_src
foreach f {main.c sw_filter.c sw_filter.h} {
    file copy -force [file join $src $f] $app_src
    puts "INFO: copied $f"
}

# ---- 编译 ----
projects -build
puts "INFO: build finished"

# ---- 检查 elf ----
set elf [glob -nocomplain [file join $ws img_filter_app Debug *.elf]]
if {[llength $elf] > 0} {
    puts "ELF: [lindex $elf 0]"
    puts "=== APP BUILD DONE ==="
} else {
    puts "ERROR: 没有生成 .elf，看上面的编译错误"
    exit 1
}

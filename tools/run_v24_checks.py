"""Reproducible host checks for the optimized PS controller and RGB preprocessing."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
out=root/'build/pl_detector_v24';shim=out/'host_include'
shim.mkdir(parents=True,exist_ok=True)
COMMON='#ifndef HOST_SDK_H\n#define HOST_SDK_H\n#include <stdint.h>\ntypedef uint8_t u8;typedef uint16_t u16;typedef uint32_t u32;typedef uintptr_t INTPTR;typedef unsigned long long XTime;\n#define COUNTS_PER_SECOND 1000000ULL\nvoid Xil_Out32(uintptr_t,u32);u32 Xil_In32(uintptr_t);void XTime_GetTime(XTime*);void usleep(unsigned);unsigned sleep(unsigned);void xil_printf(const char*,...);unsigned char inbyte(void);void Xil_DCacheEnable(void);void Xil_DCacheFlushRange(INTPTR,unsigned);\n#endif\n'
(shim/'host_sdk.h').write_text(COMMON)
for name in ('xil_types.h','xparameters.h','xil_io.h','xil_printf.h','xil_cache.h','xtime_l.h','sleep.h'):
    (shim/name).write_text('#include "host_sdk.h"\n')
gcc='D:/XILINX/Vivado/2018.3/tps/mingw/6.2.0/win64.o/nt/bin/gcc.exe'
def run(args):subprocess.run(args,cwd=root,check=True)
run([gcc,'-shared','-O2','-DPL_PREPROCESS_ONLY','-DPEST_FULL_FRAME','-Ibuild/pl_detector_v24/host_include','-Ips_app','ps_app/pl_detector.c','-o','build/pl_detector_v24/preprocess.dll'])
run([sys.executable,'tools/test_preprocess_v24.py'])
run([gcc,'-O2','-DPEST_USE_PL','-DPEST_OPTIMIZED','-DPEST_FAST_PL','-DPEST_FULL_FRAME','-Ibuild/pl_detector_v24/host_include','-Ips_app','tools/test_control_v24.c','-o','build/pl_detector_v24/test_control.exe'])
run([str(out/'test_control.exe')])

#ifndef PL_DETECTOR_H
#define PL_DETECTOR_H
#include "pest.h"
/* Returns zero on timeout/protocol error. Never falls back to PS detection. */
int pl_pest_detect(const u8 *rgb, pest_result_t *result);
u32 pl_detector_cycles(void);
u32 pl_detector_prepare_us(void);
u32 pl_detector_upload_us(void);
u32 pl_detector_wait_us(void);
void pl_display_hold(int hold);
void pl_preprocess_frame(const u8 *rgb, u32 *packed);
/* Pure preprocessor, shared with host-side verification. No lesion decisions. */
u32 pl_preprocess_pixel(const u8 *rgb, int x, int y);
#endif

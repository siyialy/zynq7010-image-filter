// v1.7: enclosed faded lesions and bounded growth from accepted cores.
#include "pest.h"
#include <string.h>

u32 g_brown_thr     = 15;    // R-G 门限
u32 g_v_max         = 140;   // 亮度上限
u32 g_frac_thr_x100 = 50;    // 判定阈值 0.50%
u32 g_min_area      = 8;     // 框的最小面积（病斑在 256x256 里通常只有几个到几十像素）
u32 g_max_area      = 65536;

void pest_set_params(u32 brown_thr, u32 v_max, u32 frac_thr_x100)
{
    g_brown_thr     = brown_thr;
    g_v_max         = v_max;
    g_frac_thr_x100 = frac_thr_x100;
}

// ---------------------------------------------------------------------------
// 工具：亮度（BT.601 定点）
// ---------------------------------------------------------------------------
static inline u32 luma(const u8 *p)
{
    return ((u32)p[0] * 77u + (u32)p[1] * 150u + (u32)p[2] * 29u) >> 8;
}

// ---------------------------------------------------------------------------
// 背景色：四条边的逐通道中位数（256 桶，避免旧版 32 灰阶量化误差）
// ---------------------------------------------------------------------------
static void estimate_bg(const u8 *rgb, u8 bg[3])
{
    u32 hist[3][256];
    int c, i, total = 0, acc, bin;
    const int W = PV_IMG_W, H = PV_IMG_H;

    memset(hist, 0, sizeof(hist));

    // 四条边，每 4 个像素取一个（够用且快）
    for (i = 0; i < W; i += 4) {
        const u8 *pt = rgb + (u32)i * 3;                        // 上边
        const u8 *pb = rgb + (u32)((H - 1) * W + i) * 3;        // 下边
        for (c = 0; c < 3; c++) {
            hist[c][pt[c]]++;
            hist[c][pb[c]]++;
        }
        total += 2;
    }
    for (i = 0; i < H; i += 4) {
        const u8 *pl = rgb + (u32)i * W * 3;                    // 左边
        const u8 *pr = rgb + (u32)(i * W + W - 1) * 3;          // 右边
        for (c = 0; c < 3; c++) {
            hist[c][pl[c]]++;
            hist[c][pr[c]]++;
        }
        total += 2;
    }

    // 仅作为背景诊断值，不用量化后的颜色距离决定叶片分母。
    for (c = 0; c < 3; c++) {
        acc = 0;
        for (bin = 0; bin < 256; bin++) {
            acc += hist[c][bin];
            if (acc * 2 >= total) break;
        }
        bg[c] = (u8)bin;
    }
}

// ---------------------------------------------------------------------------
// 结果初始化；所有病斑统计共用 make_leaf 生成的叶片范围。
// ---------------------------------------------------------------------------
#define MAX_LABEL (PV_IMG_W * PV_IMG_H)
static void initialize_result(const u8 *rgb, pest_result_t *res)
{
    memset(res, 0, sizeof(*res));
    estimate_bg(rgb,res->bg);
}

/* Static workspace: 704 KiB; no heap or recursive flood fill. */
#define N MAX_LABEL
static u8 sm[N][3], leaf[N], work[N], temp[N], brown[N];
static u16 queue[N];
static u8 luminance[N], envelope[N];

static int clamp(int v, int lo, int hi)
{
    return v < lo ? lo : (v > hi ? hi : v);
}

static void smooth_rgb(const u8 *rgb)
{
    int x, y, dx, dy, c;
    for (y = 0; y < PV_IMG_H; y++) for (x = 0; x < PV_IMG_W; x++) {
        u32 sum[3] = {0,0,0};
        for (dy = -1; dy <= 1; dy++) for (dx = -1; dx <= 1; dx++) {
            const u8 *p = rgb+(clamp(y+dy,0,PV_IMG_H-1)*PV_IMG_W+clamp(x+dx,0,PV_IMG_W-1))*3;
            for (c = 0; c < 3; c++) sum[c] += p[c];
        }
        for (c = 0; c < 3; c++) sm[y*PV_IMG_W+x][c] = (u8)(sum[c]/9U);
    }
}

static void morph(const u8 *in, u8 *out, int dilate)
{
    int x, y, dx, dy;
    for (y = 0; y < PV_IMG_H; y++) for (x = 0; x < PV_IMG_W; x++) {
        int v = !dilate;
        for (dy = -1; dy <= 1; dy++) for (dx = -1; dx <= 1; dx++) {
            int bit = in[clamp(y+dy,0,PV_IMG_H-1)*PV_IMG_W+clamp(x+dx,0,PV_IMG_W-1)] != 0;
            if (dilate) v |= bit; else v &= bit;
        }
        out[y*PV_IMG_W+x] = (u8)v;
    }
}

/* queue retains all indices; mark on enqueue so each pixel enters at most once. */
static int flood(u8 *mask, int start)
{
    int head = 0, tail = 1;
    queue[0] = (u16)start; mask[start] = 2;
    while (head < tail) {
        int p = queue[head++], x = p%PV_IMG_W, y = p/PV_IMG_W, dx, dy;
        for (dy = -1; dy <= 1; dy++) for (dx = -1; dx <= 1; dx++) {
            int nx = x+dx, ny = y+dy, idx;
            if (nx < 0 || nx >= PV_IMG_W || ny < 0 || ny >= PV_IMG_H) continue;
            idx = ny*PV_IMG_W+nx;
            if (mask[idx] == 1) { mask[idx] = 2; queue[tail++] = (u16)idx; }
        }
    }
    return tail;
}

static void make_leaf(void)
{
    int i, largest = 0, head, tail;
    for (i = 0; i < N; i++) {
        int r = sm[i][0], g = sm[i][1], b = sm[i][2];
        int hi = r > g ? r : g, lo = r < g ? r : g;
        if (b > hi) hi = b;
        if (b < lo) lo = b;
        /* Low-chroma cast shadows are not leaf tissue. Keep green/yellow and
           saturated brown seeds, then fill holes enclosed by the main leaf. */
        work[i] = ((g-b > 12 || r-b > 25) && hi-lo > 20);
    }
    morph(work,temp,1); morph(temp,work,0);
    memset(leaf,0,sizeof(leaf));
    for (i = 0; i < N; i++) if (work[i] == 1) {
        int count = flood(work,i), j;
        if (count > largest) {
            largest = count; memset(leaf,0,sizeof(leaf));
            for (j = 0; j < count; j++) leaf[queue[j]] = 1;
        }
    }
    /* Flood outside from all edges; fill only holes enclosed by the leaf. */
    memcpy(work,leaf,sizeof(work)); head = tail = 0;
    for (i = 0; i < N; i++) {
        int x = i%PV_IMG_W, y = i/PV_IMG_W;
        if ((x == 0 || x == PV_IMG_W-1 || y == 0 || y == PV_IMG_H-1) && !work[i]) {
            work[i] = 2; queue[tail++] = (u16)i;
        }
    }
    while (head < tail) {
        int p = queue[head++], x = p%PV_IMG_W, y = p/PV_IMG_W, k;
        for (k = 0; k < 4; k++) {
            int nx = x+(k==0)-(k==1), ny = y+(k==2)-(k==3), idx;
            if (nx < 0 || nx >= PV_IMG_W || ny < 0 || ny >= PV_IMG_H) continue;
            idx = ny*PV_IMG_W+nx;
            if (!work[idx]) { work[idx] = 2; queue[tail++] = (u16)idx; }
        }
    }
    for (i = 0; i < N; i++) leaf[i] = work[i] != 2;
    /* Use the same conservative interior for statistics and localization. */
    morph(leaf,temp,0); memcpy(leaf,temp,sizeof(leaf));
}

static void measure_leaf_stats(pest_result_t *res)
{
    int i;
    for (i = 0; i < N; i++) if (leaf[i]) {
        res->leaf_px++;
        if ((int)sm[i][0]-(int)sm[i][1] > (int)g_brown_thr && luma(sm[i]) < g_v_max)
            res->brown_px++;
    }
    res->frac_x100 = res->leaf_px ? res->brown_px*10000U/res->leaf_px : 0;
    res->diseased = res->leaf_px >= 400 && res->frac_x100 >= g_frac_thr_x100;
    /* Never fall back to whole-frame colour counts when segmentation is weak. */
}

static int green_support(int x0, int y0, int x1, int y1)
{
    int x, y, count = 0, green = 0;
    x0 = clamp(x0,0,PV_IMG_W); x1 = clamp(x1,0,PV_IMG_W);
    y0 = clamp(y0,0,PV_IMG_H); y1 = clamp(y1,0,PV_IMG_H);
    for (y = y0; y < y1; y++) for (x = x0; x < x1; x++) {
        const u8 *p = sm[y*PV_IMG_W+x];
        count++; green += (int)p[1]-(int)p[0] > 8 && (int)p[1]-(int)p[2] > 8;
    }
    return count ? green*100/count : 0;
}

/* Inclusive source rectangle -> displayed crop; reject before unsigned casts. */
int pest_map_box(int x0, int y0, int x1, int y1, u32 area, pest_box_t *out)
{
    int bx0, by0, bx1, by1;
    if (x0 > x1 || y0 > y1 || x1 < 0 || x0 >= PV_IMG_W ||
        y1 < SRC_CROP_Y0 || y0 >= SRC_CROP_Y0+SRC_CROP_H) return 0;
    x0 = clamp(x0,0,PV_IMG_W-1); x1 = clamp(x1,0,PV_IMG_W-1);
    y0 = clamp(y0,SRC_CROP_Y0,SRC_CROP_Y0+SRC_CROP_H-1);
    y1 = clamp(y1,SRC_CROP_Y0,SRC_CROP_Y0+SRC_CROP_H-1);
#ifdef PEST_FULL_FRAME
    bx0=clamp((x0*15+15)/16+38,40,279);bx1=clamp(((x1+1)*15+15)/16+41,40,279);
    by0=clamp((y0*15+15)/16-2,0,239);by1=clamp(((y1+1)*15+15)/16+1,0,239);
    out->x0=(u16)bx0;out->x1=(u16)bx1;out->y0=(u16)by0;out->y1=(u16)by1;
#else
    /* Invert renderer floor(x*4/5), including the last source pixel; margin 2. */
    bx0 = (x0*5+3)/4-2; bx1 = ((x1+1)*5+3)/4-1+2;
    by0 = ((y0-SRC_CROP_Y0)*5+3)/4-2;
    by1 = ((y1-SRC_CROP_Y0+1)*5+3)/4-1+2;
    out->x0 = (u16)clamp(bx0,0,DISP_W-1); out->x1 = (u16)clamp(bx1,0,DISP_W-1);
    out->y0 = (u16)clamp(by0,0,DISP_H-1); out->y1 = (u16)clamp(by1,0,DISP_H-1);
#endif
    out->area = area;
    return 1;
}

void pest_insert_box(pest_result_t *res, const pest_box_t *box)
{
    u32 pos = 0, j, count = res->num_box;
    while (pos < count && res->box[pos].area >= box->area) pos++;
    if (pos >= PV_MAX_BOX) return;
    if (count < PV_MAX_BOX) count++;
    for (j = count-1; j > pos; j--) res->box[j] = res->box[j-1];
    res->box[pos] = *box; res->num_box = count;
}

static void classify_enclosed(pest_result_t *res)
{
    int i;
    for (i = 0; i < N; i++) {
        int r = sm[i][0], g = sm[i][1], b = sm[i][2];
        int dark = luma(sm[i]) < g_v_max;
        int brown_cut = (int)g_brown_thr-7; /* default localization threshold 8 */
        int neutral = r*100 >= g*80 && b*100 >= g*95 && dark;
        if (brown_cut < 1) brown_cut = 1;
        brown[i] = r-g > brown_cut && r-b > 8 && (r-g)*100 >= (r-b)*40 && dark;
        work[i] = leaf[i] && (brown[i] || neutral);
    }
    morph(work,temp,1); morph(temp,work,0);
    for (i = 0; i < N; i++) work[i] &= leaf[i];
    for (i = 0; i < N; i++) if (work[i] == 1) {
        int area = flood(work,i), j, enclosed;
        int x0 = PV_IMG_W, y0 = PV_IMG_H, x1 = 0, y1 = 0, w, h, s[4];
        pest_box_t box;
        for (j = 0; j < area; j++) {
            int p = queue[j], x = p%PV_IMG_W, y = p/PV_IMG_W;
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
        }
        w = x1-x0+1; h = y1-y0+1;
        if ((u32)area < g_min_area || (u32)area > g_max_area || w < 2 || h < 2 ||
            w > 8*h || h > 8*w || area*100 < w*h*15) continue;
        s[0] = green_support(x0-2,y0-4,x1+3,y0);
        s[1] = green_support(x0-2,y1+1,x1+3,y1+5);
        s[2] = green_support(x0-4,y0,x0,y1+1);
        s[3] = green_support(x1+1,y0,x1+5,y1+1);
        enclosed = area >= 20 && s[0]>=35 && s[1]>=35 && s[2]>=35 && s[3]>=35 &&
                   s[0]+s[1]+s[2]+s[3] >= 280;
        if (!enclosed) continue;
        if (!pest_map_box(x0,y0,x1,y1,(u32)area,&box)) continue;
        res->diseased = 1;
        return;
    }
}

/* Separable 31x31 greyscale closing. Monotone queues make each pass O(N),
   not 31 comparisons per pixel. Replicated image borders match offline review. */
#define LOCAL_RADIUS 15
static void grey_extreme(const u8 *in, u8 *out, int vertical, int maximum)
{
    int line, t;
    for (line = 0; line < PV_IMG_W; line++) {
        int qi[PV_IMG_W+2*LOCAL_RADIUS], head = 0, tail = 0;
        u8 qv[PV_IMG_W+2*LOCAL_RADIUS];
        for (t = 0; t < PV_IMG_W+2*LOCAL_RADIUS; t++) {
            int p = clamp(t-LOCAL_RADIUS,0,PV_IMG_W-1), dst;
            u8 value = in[vertical ? p*PV_IMG_W+line : line*PV_IMG_W+p];
            while (tail > head && (maximum ? qv[tail-1] <= value : qv[tail-1] >= value)) tail--;
            qi[tail] = t; qv[tail++] = value;
            while (tail > head && qi[head] < t-2*LOCAL_RADIUS) head++;
            if (t < 2*LOCAL_RADIUS) continue;
            dst = t-2*LOCAL_RADIUS;
            out[vertical ? dst*PV_IMG_W+line : line*PV_IMG_W+dst] = qv[head];
        }
    }
}

static int tissue_support(int x0, int y0, int x1, int y1)
{
    int x, y, count = 0, tissue = 0;
    x0 = clamp(x0,0,PV_IMG_W); x1 = clamp(x1,0,PV_IMG_W);
    y0 = clamp(y0,0,PV_IMG_H); y1 = clamp(y1,0,PV_IMG_H);
    for (y = y0; y < y1; y++) for (x = x0; x < x1; x++) {
        const u8 *p = sm[y*PV_IMG_W+x];
        count++;
        /* Include yellow tissue around brown lesions; exclude neutral background. */
        tissue += (int)p[1]-(int)p[2] > 10 && (int)p[1]*100 > (int)p[0]*70;
    }
    return count ? tissue*100/count : 0;
}

/* Confidence-ranked top eight, suppressing duplicate boxes over the same spot.
   Public result.area remains the true component area, not a hidden score. */
static int duplicate_box(const pest_box_t *b, const pest_box_t *box)
{
    int x0 = b->x0 > box->x0 ? b->x0 : box->x0;
    int y0 = b->y0 > box->y0 ? b->y0 : box->y0;
    int x1 = b->x1 < box->x1 ? b->x1 : box->x1;
    int y1 = b->y1 < box->y1 ? b->y1 : box->y1;
    u32 a = (b->x1-b->x0+1U)*(b->y1-b->y0+1U);
    u32 other = (box->x1-box->x0+1U)*(box->y1-box->y0+1U);
    u32 smaller = a < other ? a : other;
    return x1 >= x0 && y1 >= y0 && (u32)((x1-x0+1)*(y1-y0+1))*100U > smaller*60U;
}

static void keep_local(pest_result_t *selected, u32 *scores, const pest_box_t *box, u32 score)
{
    u32 i = 0, j, pos, count = selected->num_box;
    /* Reject before mutating: one new box may overlap several old candidates. */
    for (i = 0; i < count; i++) {
        if (duplicate_box(&selected->box[i],box) && scores[i] >= score) return;
    }
    i = 0;
    while (i < count) {
        if (duplicate_box(&selected->box[i],box)) {
            for (j = i+1; j < count; j++) { selected->box[j-1] = selected->box[j]; scores[j-1] = scores[j]; }
            count--;
        } else i++;
    }
    pos = 0;
    while (pos < count && scores[pos] >= score) pos++;
    if (pos < PV_MAX_BOX) {
        if (count < PV_MAX_BOX) count++;
        for (j = count-1; j > pos; j--) { selected->box[j] = selected->box[j-1]; scores[j] = scores[j-1]; }
        selected->box[pos] = *box; scores[pos] = score;
    }
    selected->num_box = count;
}

/* Recover faded margins only around an accepted core. Three bounded growth
   steps cannot introduce independent vein/shadow detections elsewhere. */
static void grow_lesion(int area, int *x0, int *y0, int *x1, int *y1)
{
    int lo_x=clamp(*x0-3,0,PV_IMG_W-1),hi_x=clamp(*x1+3,0,PV_IMG_W-1);
    int lo_y=clamp(*y0-3,0,PV_IMG_H-1),hi_y=clamp(*y1+3,0,PV_IMG_H-1);
    int x,y,j,step;
    for(y=lo_y;y<=hi_y;y++) for(x=lo_x;x<=hi_x;x++) temp[y*PV_IMG_W+x]=0;
    for(j=0;j<area;j++)temp[queue[j]]=1;
    for(step=0;step<3;step++) {
        for(y=lo_y;y<=hi_y;y++) for(x=lo_x;x<=hi_x;x++) {
            int p=y*PV_IMG_W+x,dx,dy,near=0;
            int r=sm[p][0],g=sm[p][1],b=sm[p][2],v=luminance[p];
            if(temp[p] || !leaf[p] || r*100<g*80 || b*100<g*65 ||
               v<30 || v>=(int)g_v_max+5 || (int)envelope[p]-v<12) continue;
            for(dy=-1;dy<=1;dy++)for(dx=-1;dx<=1;dx++) {
                int nx=x+dx,ny=y+dy;
                if(nx>=lo_x && nx<=hi_x && ny>=lo_y && ny<=hi_y && temp[ny*PV_IMG_W+nx]==1)near=1;
            }
            if(near)temp[p]=2;
        }
        for(y=lo_y;y<=hi_y;y++)for(x=lo_x;x<=hi_x;x++) if(temp[y*PV_IMG_W+x]==2)temp[y*PV_IMG_W+x]=1;
    }
    for(y=lo_y;y<=hi_y;y++)for(x=lo_x;x<=hi_x;x++)if(temp[y*PV_IMG_W+x]) {
        if(x<*x0)*x0=x;
        if(x>*x1)*x1=x;
        if(y<*y0)*y0=y;
        if(y>*y1)*y1=y;
    }
}

void pest_detect(const u8 *rgb, pest_result_t *res)
{
    int i;
    pest_result_t selected;
    u32 scores[PV_MAX_BOX] = {0};
    initialize_result(rgb,res);
    smooth_rgb(rgb); make_leaf();
    measure_leaf_stats(res);
    if (!res->diseased) classify_enclosed(res);
    /* A disease decision does not justify drawing a box on an uncertain pixel. */
    /* Local evidence is evaluated even when the global brown fraction is low. */
    memset(&selected,0,sizeof(selected));
    for (i = 0; i < N; i++) luminance[i] = (u8)luma(sm[i]);
    grey_extreme(luminance,temp,0,1);
    grey_extreme(temp,envelope,1,1);
    grey_extreme(envelope,temp,0,0);
    grey_extreme(temp,envelope,1,0);
    for (i = 0; i < N; i++) {
        int r = sm[i][0], g = sm[i][1], b = sm[i][2], v = luminance[i];
        int cut = (int)g_brown_thr-9;
        int neutral = r*100 >= g*80 && b*100 >= g*90;
        if (cut < 1) cut = 1;
        brown[i] = r-g > cut && r-b > 5 && (r-g)*100 > (r-b)*45;
        work[i] = leaf[i] && (brown[i] || neutral) && v >= 30 && v < (int)g_v_max+5 &&
                  (int)envelope[i]-v >= 12;
    }
    /* Opening severs thin vein/edge bridges before closing small spot cracks. */
    morph(work,temp,0); morph(temp,work,1);
    morph(work,temp,1); morph(temp,work,0);
    for (i = 0; i < N; i++) work[i] &= leaf[i];
    for (i = 0; i < N; i++) if (work[i] == 1) {
        int area = flood(work,i), j, x0 = PV_IMG_W, y0 = PV_IMG_H, x1 = 0, y1 = 0;
        int w, h, s[4], supported = 0, support_sum = 0, chroma_sum = 0;
        int green_sum, green_sides, enclosed_faded;
        u32 contrast_sum = 0, score;
        pest_box_t box;
        for (j = 0; j < area; j++) {
            int p = queue[j], x = p%PV_IMG_W, y = p/PV_IMG_W;
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
            contrast_sum += envelope[p]-luminance[p];
            chroma_sum += (int)sm[p][0]-(int)sm[p][2];
        }
        w = x1-x0+1; h = y1-y0+1;
        if (area < 10 || (u32)area < g_min_area || (u32)area > g_max_area || w < 3 || h < 3 ||
            w > 4*h || h > 4*w || area*100 < w*h*25) continue;
        /* Local spot mode: broad bands exceeding twice the background window
           cannot be reliably localized as one lesion by this estimator. */
        if (w > 4*LOCAL_RADIUS+5 || h > 4*LOCAL_RADIUS+5) continue;
        s[0] = tissue_support(x0-2,y0-5,x1+3,y0);
        s[1] = tissue_support(x0-2,y1+1,x1+3,y1+6);
        s[2] = tissue_support(x0-5,y0,x0,y1+1);
        s[3] = tissue_support(x1+1,y0,x1+6,y1+1);
        for (j = 0; j < 4; j++) { supported += s[j] > 25; support_sum += s[j]; }
        if (supported < 3 || support_sum < 180) continue;
        s[0] = green_support(x0-2,y0-5,x1+3,y0);
        s[1] = green_support(x0-2,y1+1,x1+3,y1+6);
        s[2] = green_support(x0-5,y0,x0,y1+1);
        s[3] = green_support(x1+1,y0,x1+6,y1+1);
        green_sum = green_sides = 0;
        for (j = 0; j < 4; j++) { green_sum += s[j]; green_sides += s[j]>=25; }
        /* A grey/brown cast shadow has neither saturated tissue colour nor
           green tissue enclosing it. Frame colour alone cannot validate it. */
        enclosed_faded = area >= 20 && supported == 4 && support_sum >= 290 &&
                         green_sum >= 60 && contrast_sum >= (u32)area*18U;
        if (chroma_sum <= area*25 && green_sum < 120 && !enclosed_faded) continue;
        if (!res->diseased && (green_sides < 3 || green_sum < 180) && !enclosed_faded) continue;
        grow_lesion(area,&x0,&y0,&x1,&y1);
        if (!pest_map_box(x0,y0,x1,y1,(u32)area,&box)) continue;
        score = contrast_sum;
        keep_local(&selected,scores,&box,score);
    }
    for (i = 0; i < (int)selected.num_box; i++) pest_insert_box(res,&selected.box[i]);
    /* DISEASED requires at least one retained local lesion, not an unrelated
       full-frame colour statistic. No candidate means no reliable lesion found. */
    res->diseased = res->num_box > 0;
}

/* Display processing is independent of pest_detect. Reuse its scratch buffers
   after detection finishes; never filter the input RGB used for classification. */
static void prepare_display(const u8 *rgb)
{
    int i, x, y, dx, dy;
    for (i = 0; i < N; i++) luminance[i] = (u8)luma(rgb+i*3);
    /* A 3x3 median suppresses isolated grain without averaging across edges. */
    for (y = 0; y < PV_IMG_H; y++) for (x = 0; x < PV_IMG_W; x++) {
        u8 v[9];
        int count = 0, a, b;
        for (dy = -1; dy <= 1; dy++) for (dx = -1; dx <= 1; dx++)
            v[count++] = luminance[clamp(y+dy,0,PV_IMG_H-1)*PV_IMG_W+clamp(x+dx,0,PV_IMG_W-1)];
        for (a = 1; a < 9; a++) {
            u8 value = v[a];
            for (b = a; b > 0 && v[b-1] > value; b--) v[b] = v[b-1];
            v[b] = value;
        }
        envelope[y*PV_IMG_W+x] = v[4];
    }
    /* Small integer bilateral filter: smooth similar tones, retain strong edges. */
    for (y = 0; y < PV_IMG_H; y++) for (x = 0; x < PV_IMG_W; x++) {
        int center = envelope[y*PV_IMG_W+x];
        u32 sum = 0, weights = 0;
        for (dy = -2; dy <= 2; dy++) for (dx = -2; dx <= 2; dx++) {
            int value = envelope[clamp(y+dy,0,PV_IMG_H-1)*PV_IMG_W+clamp(x+dx,0,PV_IMG_W-1)];
            int diff = value-center;
            int ax = dx < 0 ? -dx : dx, ay = dy < 0 ? -dy : dy;
            u32 weight;
            if (diff < 0) diff = -diff;
            if (diff > 36) continue;
            weight = (u32)((3-ax)*(3-ay))*(diff <= 8 ? 4U : (diff <= 20 ? 2U : 1U));
            sum += (u32)value*weight; weights += weight;
        }
        temp[y*PV_IMG_W+x] = (u8)((sum+weights/2U)/weights);
    }
}

void pest_render(const u8 *rgb, const pest_result_t *res, u8 *out320x240)
{
    int x, y;
    (void)res;
    prepare_display(rgb);
#ifdef PEST_FULL_FRAME
    /* Fit the entire 256-square source into a 240-square view, with 40 soft
       columns on each side. Detection and display use exactly this geometry. */
    for(y=0;y<240;y++)for(x=0;x<240;x++) {
        int sx=x*16/15,sy=y*16/15,fx=x*16%15,fy=y*16%15;
        int sx1=clamp(sx+1,0,255),sy1=clamp(sy+1,0,255);
        u32 a=(u32)temp[sy*256+sx]*(15-fx)+(u32)temp[sy*256+sx1]*fx;
        u32 b=(u32)temp[sy1*256+sx]*(15-fx)+(u32)temp[sy1*256+sx1]*fx;
        out320x240[y*320+x+40]=(u8)(((a*(15-fy)+b*fy+112U)/225U)>>1);
    }
    for(y=0;y<240;y++) {
        u32 left=0,right=0;int dx,dy;
        for(dy=-4;dy<=4;dy++)for(dx=0;dx<16;dx++) {
            int row=clamp(y+dy,0,239)*320;
            left+=out320x240[row+40+dx];right+=out320x240[row+264+dx];
        }
        left=((left+72U)/144U*3U+64U+2U)/4U;
        right=((right+72U)/144U*3U+64U+2U)/4U;
        for(x=0;x<40;x++){out320x240[y*320+x]=(u8)left;out320x240[y*320+280+x]=(u8)right;}
    }
#else
    /* Same crop and scale as v1.4; interpolate rather than repeat source pixels. */
    for (y = 0; y < DISP_H; y++) {
        int sy = SRC_CROP_Y0+y*4/5, fy = y*4%5;
        int sy1 = clamp(sy+1,SRC_CROP_Y0,SRC_CROP_Y0+SRC_CROP_H-1);
        for (x = 0; x < DISP_W; x++) {
            int sx = x*4/5, fx = x*4%5, sx1 = clamp(sx+1,0,PV_IMG_W-1);
            u32 a = (u32)temp[sy*PV_IMG_W+sx]*(5-fx)+(u32)temp[sy*PV_IMG_W+sx1]*fx;
            u32 b = (u32)temp[sy1*PV_IMG_W+sx]*(5-fx)+(u32)temp[sy1*PV_IMG_W+sx1]*fx;
            u32 grey = (a*(5-fy)+b*fy+12U)/25U;
            out320x240[y*DISP_W+x] = (u8)(grey >> 1); // bit7 stays zero
        }
    }
#endif
}

void pest_render_background(const u8 *display, u8 *background)
{
    int x, y, dx, dy;
    for (y = 0; y < BG_H; y++) for (x = 0; x < BG_W; x++) {
        int col = x%16;
        int cx = x < 16 ? (15-col)*4 : DISP_W-1-col*4;
        int cy = y*4+2;
        u32 sum = 0;
        /* Broad blur of mirrored edge strips; little texture survives at 16x60. */
        for (dy = -6; dy <= 6; dy++) for (dx = -10; dx <= 10; dx++)
            sum += display[clamp(cy+dy,0,DISP_H-1)*DISP_W+clamp(cx+dx,0,DISP_W-1)];
        sum = (sum+136U)/273U;
        background[y*BG_W+x] = (u8)((sum*3U+64U+2U)/4U);
    }
}

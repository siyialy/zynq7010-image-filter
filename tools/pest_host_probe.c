/* Host-only validation access to the real C greyscale window implementation. */
#include "../ps_app/pest.c"

void pest_review_closing(const u8 *input, u8 *output)
{
    grey_extreme(input,temp,0,1);
    grey_extreme(temp,envelope,1,1);
    grey_extreme(envelope,temp,0,0);
    grey_extreme(temp,output,1,0);
}

void pest_review_keep(pest_result_t *selected, u32 *scores, const pest_box_t *box, u32 score)
{
    keep_local(selected,scores,box,score);
}

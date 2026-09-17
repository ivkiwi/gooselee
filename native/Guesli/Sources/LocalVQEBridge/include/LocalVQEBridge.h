#ifndef GUESLI_LOCALVQE_BRIDGE_H
#define GUESLI_LOCALVQE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GuesliLocalVQEContext GuesliLocalVQEContext;

GuesliLocalVQEContext *guesli_localvqe_create(
    const char *model_path,
    const char *library_path,
    int threads,
    char *error_buffer,
    int error_buffer_length
);

void guesli_localvqe_destroy(GuesliLocalVQEContext *context);
void guesli_localvqe_reset(GuesliLocalVQEContext *context);

int guesli_localvqe_process_frame_f32(
    GuesliLocalVQEContext *context,
    const float *mic,
    const float *reference,
    int hop_samples,
    float *output
);

int guesli_localvqe_sample_rate(GuesliLocalVQEContext *context);
int guesli_localvqe_hop_length(GuesliLocalVQEContext *context);
const char *guesli_localvqe_last_error(GuesliLocalVQEContext *context);

#ifdef __cplusplus
}
#endif

#endif

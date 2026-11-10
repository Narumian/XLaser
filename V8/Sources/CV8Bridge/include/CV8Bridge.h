#ifndef XLASER_CV8_BRIDGE_H
#define XLASER_CV8_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct XLaserV8Runtime XLaserV8Runtime;
typedef struct {
    const double *values;
    const uint16_t *modes;
    const uint32_t *shapes;
    size_t vertex_count;
    size_t shape_count;
} XLaserV8Input;
typedef struct {
    const double *values;
    const uint16_t *modes;
    const uint32_t *shapes;
    size_t vertex_count;
    size_t shape_count;
} XLaserV8Output;
XLaserV8Runtime *xlv8_create(const char *runtime, const char *source);
void xlv8_destroy(XLaserV8Runtime *runtime);
int xlv8_read(XLaserV8Runtime *runtime, double time, double sample_rate, double frame_length,
              const XLaserV8Input *inputs, size_t input_count, XLaserV8Output *output);
const char *xlv8_error(void);

#ifdef __cplusplus
}
#endif
#endif

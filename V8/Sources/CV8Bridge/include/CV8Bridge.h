#ifndef XLASER_CV8_BRIDGE_H
#define XLASER_CV8_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif

typedef struct XLaserV8Runtime XLaserV8Runtime;
XLaserV8Runtime *xlv8_create(const char *runtime, const char *source);
void xlv8_destroy(XLaserV8Runtime *runtime);
const char *xlv8_read(XLaserV8Runtime *runtime, const char *context_json, const char *inputs_json);
const char *xlv8_error(void);

#ifdef __cplusplus
}
#endif
#endif

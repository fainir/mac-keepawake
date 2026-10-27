// dsbright - read/set the built-in display's brightness on macOS (incl. Apple Silicon)
// using the private DisplayServices framework, loaded at runtime via dlopen so
// no special linking is required.
//
//   dsbright g          prints current brightness (0.0000 - 1.0000)
//   dsbright s <value>  sets brightness to <value> (0.0 - 1.0)
//
// Only the built-in panel is touched, never an external monitor (with the lid
// closed in clamshell mode an external display becomes the "main" display).
// Exit codes: 0 ok, 2 usage, 3/4 DisplayServices unavailable, 5 no built-in
// display online, 6 DisplayServices call failed.
//
// Build: clang -O2 -o dsbright dsbright.c -framework CoreGraphics
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

typedef int (*getfn)(CGDirectDisplayID, float *);
typedef int (*setfn)(CGDirectDisplayID, float);

static int usage(void) { fprintf(stderr, "usage: dsbright g | dsbright s <0.0-1.0>\n"); return 2; }

static int builtin_display(CGDirectDisplayID *out) {
    CGDirectDisplayID ids[16];
    uint32_t n = 0;
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess) return 0;
    for (uint32_t i = 0; i < n; i++) if (CGDisplayIsBuiltin(ids[i])) { *out = ids[i]; return 1; }
    return 0;
}

int main(int argc, char **argv) {
    int get = argc == 2 && argv[1][0] == 'g';
    int set = argc == 3 && argv[1][0] == 's';
    if (!get && !set) return usage();

    double v = 0;
    if (set) {
        char *end = NULL;
        v = strtod(argv[2], &end);
        if (end == argv[2] || *end != '\0' || !isfinite(v) || v < 0.0 || v > 1.0) {
            fprintf(stderr, "dsbright: brightness must be a number from 0.0 to 1.0, got '%s'\n", argv[2]);
            return 2;
        }
    }

    void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    if (!h) { fprintf(stderr, "dsbright: cannot load DisplayServices\n"); return 3; }
    getfn ds_get = (getfn)dlsym(h, "DisplayServicesGetBrightness");
    setfn ds_set = (setfn)dlsym(h, "DisplayServicesSetBrightness");
    if (!ds_get || !ds_set) { fprintf(stderr, "dsbright: DisplayServices symbols missing\n"); return 4; }

    CGDirectDisplayID d;
    if (!builtin_display(&d)) { fprintf(stderr, "dsbright: no built-in display online\n"); return 5; }

    if (get) {
        float b = -1.0f;
        int err = ds_get(d, &b);
        if (err != 0) { fprintf(stderr, "dsbright: DisplayServicesGetBrightness failed (%d)\n", err); return 6; }
        printf("%.4f\n", b);
        return 0;
    }
    int err = ds_set(d, (float)v);
    if (err != 0) { fprintf(stderr, "dsbright: DisplayServicesSetBrightness failed (%d)\n", err); return 6; }
    return 0;
}

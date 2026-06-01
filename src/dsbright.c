// dsbright - read/set the main display's brightness on macOS (incl. Apple Silicon)
// using the private DisplayServices framework, loaded at runtime via dlopen so
// no special linking is required.
//
//   dsbright g          prints current brightness (0.0000 - 1.0000)
//   dsbright s <value>  sets brightness to <value> (0.0 - 1.0)
//
// Build: clang -O2 -o dsbright dsbright.c -framework CoreGraphics
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef int (*getfn)(CGDirectDisplayID, float *);
typedef int (*setfn)(CGDirectDisplayID, float);

int main(int argc, char **argv) {
    void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    if (!h) { fprintf(stderr, "dsbright: cannot load DisplayServices\n"); return 3; }
    getfn ds_get = (getfn)dlsym(h, "DisplayServicesGetBrightness");
    setfn ds_set = (setfn)dlsym(h, "DisplayServicesSetBrightness");
    if (!ds_get || !ds_set) { fprintf(stderr, "dsbright: DisplayServices symbols missing\n"); return 4; }
    CGDirectDisplayID d = CGMainDisplayID();
    if (argc >= 2 && argv[1][0] == 'g') { float b = -1.0f; ds_get(d, &b); printf("%.4f\n", b); return 0; }
    if (argc >= 3 && argv[1][0] == 's') { return ds_set(d, (float)atof(argv[2])); }
    fprintf(stderr, "usage: dsbright g | dsbright s <0.0-1.0>\n"); return 2;
}

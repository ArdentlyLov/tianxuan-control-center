#include <stdbool.h>
#include <stdint.h>
#include <math.h>
static int live, released, shutdowns, mode;
static uint64_t sequence;
void MockReset(void) { live = released = shutdowns = mode = 0; sequence = 0; }
void MockMode(int value) { mode = value; }
int MockLive(void) { return live; }
int MockReleased(void) { return released; }
int MockShutdowns(void) { return shutdowns; }
bool PG_Initialize(void) { return true; }
bool PG_Shutdown(void) { ++shutdowns; return true; }
bool PG_GetNumPackages(int *count) { *count = mode == 4 ? 0 : 1; return true; }
bool PG_ReadSample(int package, uint64_t *sample) {
    if (package != 0 || mode == 2) return false;
    *sample = ++sequence; ++live; return true;
}
bool PGSample_Release(uint64_t sample) { --live; ++released; return true; }
bool PGSample_GetPackageTemperature(uint64_t sample, double *value) {
    *value = mode == 1 ? -1 : 57; return mode != 3;
}
bool PGSample_GetPackagePower(uint64_t first, uint64_t second, double *watts, double *joules) {
    *watts = mode == 1 ? NAN : 18.5; *joules = 1;
    return first < second && mode != 3;
}
bool PGSample_GetIAFrequency(uint64_t first, uint64_t second, double *mean, double *min, double *max) {
    *mean = mode == 1 ? INFINITY : (mode == 5 ? 400 : 2350);
    *min = 300; *max = mode == 1 ? NAN : (mode == 6 ? INFINITY : 4500);
    return first < second && mode != 3;
}

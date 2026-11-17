#include "PrivateBridge.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>

static void *sky;
static int (*connection)(void);
static CFArrayRef (*copyDisplays)(int);
static void (*moveWindows)(int, CFArrayRef, uint64_t);
static CFArrayRef (*copyWindowSpaces)(int, int, CFArrayRef);
static int (*axWindowID)(CFTypeRef, uint32_t *);
bool MGSpacesAvailable(void) {
    if (!sky) {
        sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
        if (!sky) return false;
        connection = dlsym(sky, "CGSMainConnectionID");
        copyDisplays = dlsym(sky, "CGSCopyManagedDisplaySpaces");
        moveWindows = dlsym(sky, "CGSMoveWindowsToManagedSpace");
        copyWindowSpaces = dlsym(sky, "CGSCopySpacesForWindows");
        void *ax = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY | RTLD_LOCAL);
        if (ax) axWindowID = dlsym(ax, "_AXUIElementGetWindow");
    }
    return connection && copyDisplays && moveWindows && copyWindowSpaces && axWindowID;
}
CFArrayRef MGCopyDisplays(void) { return MGSpacesAvailable() ? copyDisplays(connection()) : NULL; }
static CFArrayRef windowArray(uint32_t window) {
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt64Type, &(int64_t){window});
    CFArrayRef a = CFArrayCreate(NULL, (const void **)&n, 1, &kCFTypeArrayCallBacks);
    CFRelease(n); return a;
}
bool MGWindowInSpace(uint32_t window, uint64_t space) {
    if (!MGSpacesAvailable()) return false;
    CFArrayRef a = windowArray(window);
    CFArrayRef spaces = copyWindowSpaces(connection(), 7, a);
    CFRelease(a);
    bool found = false;
    if (spaces) {
        for (CFIndex i = 0; i < CFArrayGetCount(spaces); i++) {
            int64_t value = 0;
            CFNumberRef number = CFArrayGetValueAtIndex(spaces, i);
            if (CFGetTypeID(number) == CFNumberGetTypeID() && CFNumberGetValue(number, kCFNumberSInt64Type, &value) && (uint64_t)value == space) found = true;
        }
        CFRelease(spaces);
    }
    return found;
}
bool MGMoveWindow(uint32_t window, uint64_t space) {
    if (!MGSpacesAvailable()) return false;
    CFArrayRef a = windowArray(window);
    moveWindows(connection(), a, space); CFRelease(a);
    return MGWindowInSpace(window, space);
}
uint32_t MGAXWindowID(CFTypeRef window) {
    uint32_t n = 0;
    if (MGSpacesAvailable()) axWindowID(window, &n);
    return n;
}

// MultitouchSupport's reverse-engineered 96-byte contact ABI. See THIRD_PARTY.md.
typedef struct { float x, y; } MGPoint;
typedef struct { MGPoint position, velocity; } MGVector;
typedef struct {
    int frame; double timestamp; int identifier, state, finger, hand;
    MGVector normalized; float total, pressure, angle, major, minor;
    MGVector absolute; int field14, field15; float density;
} Touch;
_Static_assert(sizeof(Touch) == 96, "Unsupported touch ABI");
typedef void (*FrameCallback)(void *, Touch *, int, double, int);
static void *multitouch, *device;
static void *(*createDevice)(void);
static bool (*available)(void);
static int (*startDevice)(void *, int);
static int (*stopDevice)(void *);
static void (*releaseDevice)(void *);
static void (*registerCallback)(void *, FrameCallback);
static void (*unregisterCallback)(void *, FrameCallback);
static MGTouchCallback recipient;
static pthread_mutex_t callbackLock = PTHREAD_MUTEX_INITIALIZER;
static void frame(void *sender, Touch *touches, int count, double time, int frameNumber) {
    (void)sender; (void)frameNumber;
    if (count < 0 || count > 32 || (count && !touches)) return;
    int active = 0; double x = 0, y = 0; uint64_t identity = 0;
    for (int i = 0; i < count; i++) {
        if (touches[i].state != 3 && touches[i].state != 4) continue;
        active++; x += touches[i].normalized.position.x; y += touches[i].normalized.position.y;
        // Order-independent identity fingerprint.
        uint64_t id = (uint32_t)touches[i].identifier;
        identity += (id + 1) * 0x9e3779b97f4a7c15ULL;
    }
    pthread_mutex_lock(&callbackLock);
    MGTouchCallback fn = recipient;
    if (fn) fn(active, identity, active ? x / active : 0, active ? y / active : 0, time);
    pthread_mutex_unlock(&callbackLock);
}
bool MGTouchAvailable(void) {
    if (!multitouch) {
        multitouch = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL);
        if (!multitouch) return false;
        createDevice = dlsym(multitouch, "MTDeviceCreateDefault");
        available = dlsym(multitouch, "MTDeviceIsAvailable");
        startDevice = dlsym(multitouch, "MTDeviceStart");
        stopDevice = dlsym(multitouch, "MTDeviceStop");
        releaseDevice = dlsym(multitouch, "MTDeviceRelease");
        registerCallback = dlsym(multitouch, "MTRegisterContactFrameCallback");
        unregisterCallback = dlsym(multitouch, "MTUnregisterContactFrameCallback");
    }
    return createDevice && available && startDevice && stopDevice && releaseDevice && registerCallback && unregisterCallback && available();
}
bool MGStartTouches(MGTouchCallback callback) {
    MGStopTouches();
    if (!MGTouchAvailable() || !(device = createDevice())) return false;
    pthread_mutex_lock(&callbackLock); recipient = callback; pthread_mutex_unlock(&callbackLock);
    registerCallback(device, frame);
    if (startDevice(device, 0) != 0) { MGStopTouches(); return false; }
    return true;
}
void MGStopTouches(void) {
    pthread_mutex_lock(&callbackLock); recipient = NULL; pthread_mutex_unlock(&callbackLock);
    if (device) { unregisterCallback(device, frame); stopDevice(device); releaseDevice(device); device = NULL; }
}

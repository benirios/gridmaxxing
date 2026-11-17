#include "PrivateBridge.h"
#include <ApplicationServices/ApplicationServices.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

// Adapted from noswoosh and InstantSpaceSwitcher (MIT). The Dock owns Space
// state; macOS 27 requires a serialized IOHID payload on synthetic swipes.
#pragma pack(push, 1)
typedef struct { uint64_t time, sender; uint32_t options, attributes, count; } QueueHeader;
typedef struct { uint32_t size, type, options; uint8_t depth, reserved[3]; } HIDBase;
typedef struct {
    HIDBase base; int32_t x, y, z; uint32_t mask;
    uint16_t motion, flavor; int32_t progress;
} FluidGesture;
typedef struct { HIDBase base; int32_t x, y, z; } Velocity;
#pragma pack(pop)
_Static_assert(sizeof(QueueHeader) == 28, "queue ABI");
_Static_assert(sizeof(FluidGesture) == 40, "gesture ABI");
_Static_assert(sizeof(Velocity) == 28, "velocity ABI");

static int32_t fixed(double n) { return (int32_t)(n * 65536.0); }
static bool supported(void) {
    char version[32] = {0}; size_t size = sizeof(version);
    return sysctlbyname("kern.osproductversion", version, &size, NULL, 0) == 0 && atoi(version) >= 27;
}
static double scrollingSign(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("com.apple.swipescrolldirection"), kCFPreferencesAnyApplication);
    bool natural = !value || (CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value));
    if (value) CFRelease(value);
    return natural ? 1.0 : -1.0;
}
static CGEventRef makeEvent(int phase, double sign) {
    // The smallest nonzero 16.16 progress leaves virtually no horizontal
    // distance for the Dock to animate; the terminal velocity commits it.
    const double progress = 0.000016;
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return NULL;
    CGEventSetIntegerValueField(event, (CGEventField)55, 30);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)132, phase);
    CGEventSetIntegerValueField(event, (CGEventField)134, phase);
    CGEventSetIntegerValueField(event, (CGEventField)123, 1);
    CGEventSetDoubleValueField(event, (CGEventField)124, sign * progress);
    CGEventSetDoubleValueField(event, (CGEventField)125, 0.1);
    CGEventSetDoubleValueField(event, (CGEventField)138, 3.0);
    CGEventSetDoubleValueField(event, (CGEventField)169, (double)mach_absolute_time());
    if (phase == 4) CGEventSetDoubleValueField(event, (CGEventField)129, sign * 9999.0);
    CFDataRef original = CGEventCreateData(NULL, event);
    if (!original) { CFRelease(event); return NULL; }
    const UInt8 *source = CFDataGetBytePtr(original);
    CFIndex length = CFDataGetLength(original);
    if (length < 4 || source[0] || source[1] || source[2] || source[3] != 2) {
        CFRelease(original); CFRelease(event); return NULL;
    }
    bool ended = phase == 4;
    QueueHeader header = {CGEventGetTimestamp(event), 0, 0, 0, ended ? 2 : 1};
    if (!header.time) header.time = mach_absolute_time();
    FluidGesture gesture = {
        {sizeof(FluidGesture), 23, (uint32_t)(phase << 24), 0, {0, 0, 0}},
        fixed(0.1), 0, 0, 0, 1, 3, fixed(sign * progress)
    };
    Velocity velocity = {{sizeof(Velocity), 9, 0, 1, {0, 0, 0}}, fixed(sign * 9999.0), 0, 0};
    size_t payload = sizeof(header) + sizeof(gesture) + (ended ? sizeof(velocity) : 0);
    size_t total = (size_t)length + 4 + payload;
    UInt8 *bytes = malloc(total);
    if (!bytes) { CFRelease(original); CFRelease(event); return NULL; }
    memcpy(bytes, source, (size_t)length);
    bytes[length] = (UInt8)(payload >> 8); bytes[length + 1] = (UInt8)payload;
    bytes[length + 2] = 0x10; bytes[length + 3] = 0x6d; // field 4205
    UInt8 *cursor = bytes + length + 4;
    memcpy(cursor, &header, sizeof(header)); cursor += sizeof(header);
    memcpy(cursor, &gesture, sizeof(gesture)); cursor += sizeof(gesture);
    if (ended) memcpy(cursor, &velocity, sizeof(velocity));
    CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)total);
    free(bytes); CFRelease(original); CFRelease(event);
    if (!data) return NULL;
    CGEventRef result = CGEventCreateFromData(NULL, data);
    CFRelease(data);
    return result;
}

bool MGInstantSwitch(int steps, bool right) {
    if (!supported() || steps < 1 || steps > 4) return false;
    CGEventRef dock[12] = {0}, companion[12] = {0};
    int count = steps * 3;
    double sign = (right ? -1.0 : 1.0) * scrollingSign();
    for (int i = 0; i < count; i++) {
        dock[i] = makeEvent(i % 3 == 0 ? 1 : (i % 3 == 1 ? 2 : 4), sign);
        companion[i] = CGEventCreate(NULL);
        if (!dock[i] || !companion[i]) goto failed;
        CGEventSetIntegerValueField(companion[i], (CGEventField)55, 29);
    }
    for (int i = 0; i < count; i++) {
        CGEventPost(kCGSessionEventTap, dock[i]);
        CGEventPost(kCGSessionEventTap, companion[i]);
    }
    for (int i = 0; i < count; i++) { CFRelease(dock[i]); CFRelease(companion[i]); }
    return true;
failed:
    for (int i = 0; i < count; i++) {
        if (dock[i]) CFRelease(dock[i]);
        if (companion[i]) CFRelease(companion[i]);
    }
    return false;
}

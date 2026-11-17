#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

// All private API and ABI assumptions are confined to this module.
bool MGSpacesAvailable(void);
CFArrayRef MGCopyDisplays(void) CF_RETURNS_RETAINED;
bool MGMoveWindow(uint32_t window, uint64_t space);
bool MGWindowInSpace(uint32_t window, uint64_t space);
uint32_t MGAXWindowID(CFTypeRef window);
typedef void (*MGTouchCallback)(int count, uint64_t identity, double x, double y, double time);
bool MGStartTouches(MGTouchCallback callback);
void MGStopTouches(void);
bool MGTouchAvailable(void);
bool MGInstantSwitch(int steps, bool right);

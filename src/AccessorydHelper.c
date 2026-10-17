// Loaded into accessoryd on iOS 15, where the kernel lets only accessoryd open the Lightning port manager's user
// client: cuts or restores the port current limit on request from chargelimitd.
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <notify.h>
#include <stdlib.h>

#include "Port.h"

typedef mach_port_t io_service_t;
extern const mach_port_t kIOMasterPortDefault;
CFMutableDictionaryRef IOServiceMatching(const char *name);
io_service_t IOServiceGetMatchingService(mach_port_t master, CFDictionaryRef matching);
kern_return_t IOServiceOpen(io_service_t service, task_port_t task, uint32_t type, mach_port_t *connect);
kern_return_t IOServiceClose(mach_port_t connect);
kern_return_t IOObjectRelease(mach_port_t object);
extern kern_return_t IOAccessoryManagerSetUSBCurrentLimitBase(mach_port_t connect, uint32_t limit);
extern kern_return_t IOAccessoryManagerRestoreUSBCurrentLimitBase(mach_port_t connect);

static int resultToken;
static uint32_t sequence;

static void HandleRequest(int charge) {
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOAccessoryManager"));
    mach_port_t connect = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &connect);
    IOObjectRelease(service);
    if (!kr) {
        kr = charge ? IOAccessoryManagerRestoreUSBCurrentLimitBase(connect) : IOAccessoryManagerSetUSBCurrentLimitBase(connect, 0);
        IOServiceClose(connect);
    }
    notify_set_state(resultToken, (uint64_t)++sequence << 32 | (uint32_t)kr);
}

__attribute__((constructor)) static void Init(void) {
    int token;
    // A random start, so an answer after an accessoryd restart never repeats the last sequence number.
    sequence = arc4random();
    notify_register_check(PORT_RESULT, &resultToken);
    notify_register_dispatch(PORT_CUT, &token, dispatch_get_main_queue(), ^(int t) { HandleRequest(0); });
    notify_register_dispatch(PORT_RESTORE, &token, dispatch_get_main_queue(), ^(int t) { HandleRequest(1); });
}

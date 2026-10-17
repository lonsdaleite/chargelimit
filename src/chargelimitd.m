// chargelimitd: keeps the battery between two levels by cutting the current the Lightning port draws from the
// charger. At the stop level the port current limit goes to 0 and the device runs on battery (holding); at the
// resume level the system's own limit is restored and charging resumes. Holding ends early, with charging resumed,
// on a cable re-plug (the system resets the port limit), a settings change, a respring, a reboot or a daemon
// restart; the stop level still applies afterwards. Settings come from the Settings app (PreferenceLoader page,
// domain com.lonsdaleite.chargelimit).
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <notify.h>
#include <signal.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
typedef mach_port_t io_connect_t;
extern const mach_port_t kIOMasterPortDefault;
CFMutableDictionaryRef IOServiceMatching(const char *name);
io_service_t IOServiceGetMatchingService(mach_port_t master, CFDictionaryRef matching);
CFTypeRef IORegistryEntryCreateCFProperty(io_service_t entry, CFStringRef key, CFAllocatorRef allocator, uint32_t options);
kern_return_t IOServiceOpen(io_service_t service, task_port_t task, uint32_t type, io_connect_t *connect);
kern_return_t IOServiceClose(io_connect_t connect);
kern_return_t IOObjectRelease(io_object_t object);

// libIOAccessoryManager. The setters take an open user client connection, not the service.
extern kern_return_t IOAccessoryManagerGetUSBCurrentLimitBase(io_service_t service, uint32_t *limit);
extern kern_return_t IOAccessoryManagerSetUSBCurrentLimitBase(io_connect_t connect, uint32_t limit);
extern kern_return_t IOAccessoryManagerRestoreUSBCurrentLimitBase(io_connect_t connect);

#define PREFS_DOMAIN "com.lonsdaleite.chargelimit"
static NSString *const LogPath = @"/var/mobile/Library/Logs/chargelimit.log";
static const int DefaultStop = 80;
static const int DefaultResume = 60;
static const NSTimeInterval CheckInterval = 60;

static void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], [[NSString alloc] initWithFormat:format arguments:args]];
    va_end(args);
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([[fm attributesOfItemAtPath:LogPath error:nil] fileSize] > 64 * 1024) {
        [fm removeItemAtPath:LogPath error:nil];
    }
    if (![fm fileExistsAtPath:LogPath]) {
        [fm createFileAtPath:LogPath contents:nil attributes:@{NSFileOwnerAccountName: @"mobile"}];
    }
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:LogPath];
    [file seekToEndOfFile];
    [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static io_service_t PortService(void) {
    static io_service_t service;
    if (!service) {
        service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOAccessoryManager"));
    }
    return service;
}

// Battery level in percent, -1 if unknown.
static int BatteryLevel(void) {
#ifdef CL_DEBUG
    // Development only: a level written to /tmp/chargelimit.level replaces the battery's.
    NSString *fake = [NSString stringWithContentsOfFile:@"/tmp/chargelimit.level" encoding:NSUTF8StringEncoding error:nil];
    if (fake.length) {
        return fake.intValue;
    }
#endif
    io_service_t battery = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPMPowerSource"));
    if (!battery) {
        return -1;
    }
    NSNumber *level = (__bridge_transfer NSNumber *)IORegistryEntryCreateCFProperty(battery, CFSTR("CurrentCapacity"),
                                                                                     kCFAllocatorDefault, 0);
    IOObjectRelease(battery);
    return level ? level.intValue : -1;
}

// Current limit base of the port in mA, -1 if unknown.
static long PortLimit(void) {
    uint32_t limit = 0;
    return IOAccessoryManagerGetUSBCurrentLimitBase(PortService(), &limit) ? -1 : (long)limit;
}

// charge: NO cuts the port current to 0, YES restores the system's limit.
static void SetCharging(BOOL charge) {
    io_connect_t connect = 0;
    kern_return_t kr = IOServiceOpen(PortService(), mach_task_self(), 0, &connect);
    if (kr) {
        Log(@"IOServiceOpen failed: 0x%x", kr);
        return;
    }
    kr = charge ? IOAccessoryManagerRestoreUSBCurrentLimitBase(connect) : IOAccessoryManagerSetUSBCurrentLimitBase(connect, 0);
    IOServiceClose(connect);
    Log(@"%@ at %d%%: kr 0x%x, port limit now %ld mA", charge ? @"charge" : @"stop", BatteryLevel(), kr, PortLimit());
}

static id Pref(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyValue((__bridge CFStringRef)key, CFSTR(PREFS_DOMAIN), CFSTR("mobile"),
                                                        kCFPreferencesAnyHost);
}

static BOOL holding;

// Ends holding and gives the port its normal limit back if it is cut.
static void Release(NSString *reason) {
    if (holding) {
        Log(@"holding ended: %@", reason);
    }
    holding = NO;
    if (PortLimit() == 0) {
        SetCharging(YES);
    }
}

static void Evaluate(void) {
    CFPreferencesSynchronize(CFSTR(PREFS_DOMAIN), CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL enabled = [Pref(@"enabled") boolValue];
    NSNumber *stopPref = Pref(@"limit"), *resumePref = Pref(@"resume");
    int stop = stopPref ? stopPref.intValue : DefaultStop;
    int resume = resumePref ? resumePref.intValue : DefaultResume;
    if (resume >= stop) {
        resume = stop - 10;
    }
    int level = BatteryLevel();
    long port = PortLimit();
    if (level < 0 || port < 0) {
        return;
    }
    if (!enabled || stop >= 100) {
        Release(@"disabled");
        return;
    }
    if (holding) {
        if (port != 0) {
            // The system resets the limit when the cable is plugged in again.
            Release(@"charger re-plugged");
        } else if (level <= resume) {
            Release([NSString stringWithFormat:@"reached %d%%", resume]);
            return;
        } else {
            return;
        }
    }
    if (level >= stop) {
        holding = YES;
        SetCharging(NO);
        Log(@"holding until %d%%", resume);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // `chargelimitd restore`: give the port its normal limit back and exit (package removal: launchctl
        // unload kills the daemon without SIGTERM).
        if (argc == 2 && [@(argv[1]) isEqualToString:@"restore"]) {
            if (PortLimit() == 0) {
                SetCharging(YES);
            }
            return 0;
        }
        Log(@"started, battery %d%%, port limit %ld mA", BatteryLevel(), PortLimit());
        // A cut limit left from before (daemon crash or restart) does not survive a restart: holding is reset.
        Release(@"daemon started");
        dispatch_queue_t queue = dispatch_get_main_queue();
        int token;
        // Battery level, power source and settings changes, plus a periodic check: the port limit is reset when
        // the cable is plugged in again.
        notify_register_dispatch("com.apple.system.powersources", &token, queue, ^(int t) { Evaluate(); });
        notify_register_dispatch(PREFS_DOMAIN ".changed", &token, queue, ^(int t) {
            Release(@"settings changed");
            Evaluate();
        });
        notify_register_dispatch("com.apple.springboard.finishedstartup", &token, queue, ^(int t) {
            Release(@"respring");
            Evaluate();
        });
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, (uint64_t)(CheckInterval * NSEC_PER_SEC), NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{ Evaluate(); });
        dispatch_resume(timer);
        // Never leave the device without charging when the daemon stops (package removal, shutdown).
        signal(SIGTERM, SIG_IGN);
        dispatch_source_t term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, queue);
        dispatch_source_set_event_handler(term, ^{
            if (PortLimit() == 0) {
                SetCharging(YES);
            }
            Log(@"stopped");
            exit(0);
        });
        dispatch_resume(term);
        dispatch_main();
    }
}

// Darwin notifications between chargelimitd and the helper loaded into accessoryd (iOS 15: only accessoryd may
// open the Lightning port manager's user client).
#pragma once

#define PORT_CUT "com.lonsdaleite.chargelimit.port.cut"
#define PORT_RESTORE "com.lonsdaleite.chargelimit.port.restore"
// The helper answers each request by setting the state of this name: a sequence number in the high 32 bits,
// the call's kern_return_t in the low ones.
#define PORT_RESULT "com.lonsdaleite.chargelimit.port.result"

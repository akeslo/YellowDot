@import Darwin;
@import CoreGraphics;
@import Cocoa;

typedef int        CGSConnection;
typedef long       CGSWindow;
typedef int        CGSValue;

extern CGSConnection CGSMainConnectionID(void);
extern OSStatus CGSSetWindowListBrightness(const CGSConnection cid, CGSWindow *wids, float *brightness, int count);
extern OSStatus CGSSetWindowAlpha(const CGSConnection cid, CGSWindow wid, float alpha);
extern OSStatus CGSSetWindowLevel(const CGSConnection cid, CGSWindow wid, int32_t level);
extern bool CGSIsMenuBarVisibleOnSpace(CGSConnection cid, long spaceNum);
extern long CGSManagedDisplayGetCurrentSpace(CGSConnection cid, CFStringRef uuid);
extern CFStringRef CGSCopyManagedDisplayForWindow(CGSConnection cid, CGSWindow wid);

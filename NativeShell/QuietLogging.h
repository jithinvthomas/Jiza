#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif
// Upstream logs complete command lines. Never put terminal input into device logs.
#define NSLog(...) ((void)0)

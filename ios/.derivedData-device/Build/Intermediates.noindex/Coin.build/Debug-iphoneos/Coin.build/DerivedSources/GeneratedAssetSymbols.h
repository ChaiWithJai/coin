#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "CornerMark" asset catalog image resource.
static NSString * const ACImageNameCornerMark AC_SWIFT_PRIVATE = @"CornerMark";

#undef AC_SWIFT_PRIVATE

//
//  PINCache+PINRemoteImageCaching.h
//  Pods
//
//  Created by Aleksei Shevchenko on 7/28/16.
//
//

#if BAZEL
#import "PINCache/Source/PINCache.h"
#else
#if SWIFT_PACKAGE
@import PINCache;
#else
#import <PINCache/PINCache.h>
#endif
#endif

#import "PINRemoteImageCaching.h"
#import "PINRemoteImageManager.h"

@interface PINCache (PINRemoteImageCaching) <PINRemoteImageCaching>

@end

@interface PINRemoteImageManager (PINCache)

@property (nonatomic, nullable, readonly) PINCache <PINRemoteImageCaching> *pinCache;

@end

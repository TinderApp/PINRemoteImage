//
//  PINAnimatedImageView.m
//  Pods
//
//  Created by Garrett Moon on 4/17/18.
//

#import "Source/Classes/include/PINAnimatedImageView.h"

#import "Source/Classes/PINRemoteLock.h"
#import "Source/Classes/PINDisplayLink.h"
#import "Source/Classes/Categories/PINImage+DecodedImage.h"
#import "Source/Classes/PINRemoteWeakProxy.h"

@interface PINAnimatedImageView ()
{
    CFTimeInterval _playHead;
    NSUInteger _playedLoops;
    NSUInteger _lastSuccessfulFrameIndex;
    CFTimeInterval *_durations;
}

@property (nonatomic, assign) CGImageRef frameImage;
@property (nonatomic, strong) PINDisplayLink *displayLink;

@property (nonatomic, assign) CFTimeInterval lastDisplayLinkFire;

@end

@implementation PINAnimatedImageView

@synthesize animatedImage = _animatedImage;
@synthesize displayLink = _displayLink;
@synthesize playbackPaused = _playbackPaused;
@synthesize animatedImageRunLoopMode = _animatedImageRunLoopMode;

- (instancetype)initWithAnimatedImage:(PINCachedAnimatedImage *)animatedImage
{
    if (self = [super initWithFrame:CGRectZero]) {
        [self commonInit:animatedImage];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commonInit:nil];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self commonInit:nil];
    }
    return self;
}

- (void)commonInit:(PINCachedAnimatedImage *)animatedImage
{
    _animatedImage = animatedImage;
    _animatedImageRunLoopMode = NSRunLoopCommonModes;
    _durations = NULL;

    if (animatedImage) {
        [self initializeAnimatedImage:animatedImage];
    }
}

- (void)initializeAnimatedImage:(nonnull PINCachedAnimatedImage *)animatedImage
{
    PINWeakify(self);
    animatedImage.coverImageReadyCallback = ^(PINImage *coverImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            PINStrongify(self);
            // In this case the lock is already gone we have to call the unlocked version therefore
            [self coverImageCompleted:coverImage];
        });
    };

    animatedImage.playbackReadyCallback = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // In this case the lock is already gone we have to call the unlocked version therefore
            PINStrongify(self);
            [self checkIfShouldAnimate];
        });
    };
    if (animatedImage.playbackReady) {
        [self checkIfShouldAnimate];
    }

    [self resetDurationsWithAnimatedImage:animatedImage];
}

- (void)dealloc
{
    if (_frameImage) {
        CGImageRelease(_frameImage);
    }
    if (_durations) {
        free(_durations);
    }
}

#pragma mark - Public

- (void)setAnimatedImage:(PINCachedAnimatedImage *)animatedImage
{
    PINAssertMain();
    if (_animatedImage == animatedImage && animatedImage.playbackReady) {
        return;
    }

    PINCachedAnimatedImage *previousAnimatedImage = _animatedImage;

    _animatedImage = animatedImage;

    if (animatedImage != nil) {
        [self initializeAnimatedImage:animatedImage];
    } else {
        // Clean up after ourselves.
        self.layer.contents = nil;
        [self setCoverImage:nil];
    }

    // Animated Image can take a while to dealloc, let's try and do it off main.
    __block PINCachedAnimatedImage *strongAnimatedImage = previousAnimatedImage;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        strongAnimatedImage = nil;
    });
}

- (PINCachedAnimatedImage *)animatedImage
{
    PINAssertMain();
    return _animatedImage;
}

- (NSString *)animatedImageRunLoopMode
{
    PINAssertMain();
    return _animatedImageRunLoopMode;
}

- (void)setAnimatedImageRunLoopMode:(NSString *)newRunLoopMode
{
    PINAssertMain();

    NSString *runLoopMode = newRunLoopMode ?: NSRunLoopCommonModes;

    if (_displayLink != nil) {
        [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:_animatedImageRunLoopMode];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:runLoopMode];
    }
    _animatedImageRunLoopMode = runLoopMode;
}

- (BOOL)isPlaybackPaused
{
    PINAssertMain();
    return _playbackPaused;
}

- (void)setPlaybackPaused:(BOOL)playbackPaused
{
    PINAssertMain();

    _playbackPaused = playbackPaused;
    [self checkIfShouldAnimate];
}

- (void)coverImageCompleted:(PINImage *)coverImage
{
    PINAssertMain();
    BOOL setCoverImage = (_displayLink == nil) || _displayLink.paused;

    if (setCoverImage) {
        [self setCoverImage:coverImage];
    }
}

- (void)setCoverImage:(PINImage *)coverImage
{
    PINAssertMain();
    if (_frameImage) {
        CGImageRelease(_frameImage);
    }
    _frameImage = CGImageRetain([coverImage CGImage]);
}

#pragma mark - Animating

- (void)checkIfShouldAnimate
{
    PINAssertMain();
    BOOL shouldAnimate = _playbackPaused == NO && _animatedImage.playbackReady && [self canBeVisible];
    if (shouldAnimate) {
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}

- (void)startAnimating
{
    PINAssertMain();

    if (_playbackPaused) {
        return;
    }

    if (_animatedImage.playbackReady == NO) {
        return;
    }

    if ([self canBeVisible] == NO) {
        return;
    }

    NSUInteger frameInterval = self.animatedImage.frameInterval;

    if (_displayLink == nil) {
        _playHead = 0;
        _displayLink = [PINDisplayLink displayLinkWithTarget:[PINRemoteWeakProxy weakProxyWithTarget:self] selector:@selector(displayLinkFired:)];
#if PIN_TARGET_IOS
        if (@available(iOS 10.0, tvOS 10.0, *)) {
            // Convert from display link fractional value to fps (note: frameInterval is always at least 1)
            NSInteger frameRate = ceil([PINAnimatedImage maximumFramesPerSecond] / ((double) frameInterval));
            _displayLink.preferredFramesPerSecond = frameRate;
        } else {
#endif
            _displayLink.frameInterval = frameInterval;
#if PIN_TARGET_IOS
        }
#endif
        _lastSuccessfulFrameIndex = NSUIntegerMax;

        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:self.animatedImageRunLoopMode];
    } else {
        _displayLink.paused = NO;
    }
}

- (void)stopAnimating
{
    PINAssertMain();

    _displayLink.paused = YES;
    _lastDisplayLinkFire = 0;

    [_animatedImage clearAnimatedImageCache];
}

#pragma mark - Overrides

- (PINImage *)image
{
    PINAssertMain();
    if (_animatedImage) {
        return [PINImage imageWithCGImage:_frameImage];
    }
    return [super image];
}

- (CGImageRef)imageRef
{
    PINAssertMain();
    PINImage *underlyingImage = nil;
    if (_animatedImage) {
        return _frameImage;
    } else if ((underlyingImage = [super image])) {
        return (CGImageRef)CFAutorelease(CFRetain([underlyingImage CGImage]));
    }
    return nil;
}

- (void)setImage:(PINImage *)image
{
    PINAssertMain();
    if (image) {
        self.animatedImage = nil;
    }

    super.image = image;
}

- (void)displayLayer:(CALayer *)layer
{
    PINAssertMain();
    layer.contents = (__bridge id)[self imageRef];
}

#if PIN_TARGET_MAC

- (void)_setImage:(PINImage *)image
{
    super.image = image;
}

- (void)setAlphaValue:(CGFloat)alphaValue
{
    [super setAlphaValue:alphaValue];
    [self updateAnimationForPossibleVisibility];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateAnimationForPossibleVisibility];
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    [self updateAnimationForPossibleVisibility];
}
#else
- (void)setAlpha:(CGFloat)alpha
{
    [super setAlpha:alpha];
    [self updateAnimationForPossibleVisibility];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    [self updateAnimationForPossibleVisibility];
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    [self updateAnimationForPossibleVisibility];
}
#endif

- (void)setHidden:(BOOL)hidden
{
    [super setHidden:hidden];
    [self updateAnimationForPossibleVisibility];
}

#pragma mark - Display Link Callbacks

- (BOOL)canBeVisible
{
#if PIN_TARGET_MAC
    return self.window && self.superview && self.isHidden == NO && self.alphaValue > 0.0;
#else
    return self.window && self.superview && self.isHidden == NO && self.alpha > 0.0;
#endif
}

- (void)updateAnimationForPossibleVisibility
{
    [self checkIfShouldAnimate];
}

- (void)displayLinkFired:(PINDisplayLink *)displayLink
{
    PINAssertMain();
    CFTimeInterval timeBetweenLastFire;
    if (_lastDisplayLinkFire == 0) {
        timeBetweenLastFire = 0;
    } else {
        timeBetweenLastFire = CACurrentMediaTime() - self.lastDisplayLinkFire;
    }

    self.lastDisplayLinkFire = CACurrentMediaTime();

    _playHead += timeBetweenLastFire;

    while (_playHead > self.animatedImage.totalDuration) {
        // Set playhead to zero to keep from showing different frames on different playthroughs
        _playHead = 0;
        _playedLoops++;
    }

    if (self.animatedImage.loopCount > 0 && _playedLoops >= self.animatedImage.loopCount) {
        [self stopAnimating];
        return;
    }

    NSUInteger frameIndex = [self frameIndexAtPlayHeadPosition:_playHead];
    if (frameIndex == _lastSuccessfulFrameIndex) {
        return;
    }
    CGImageRef frameImage = [self.animatedImage imageAtIndex:frameIndex];

    if (frameImage == nil) {
        //Pause the display link until we get a file ready notification
        displayLink.paused = YES;
        self.lastDisplayLinkFire = 0;
    } else {
        if (_frameImage) {
            CGImageRelease(_frameImage);
        }
        _frameImage = CGImageRetain(frameImage);
        _lastSuccessfulFrameIndex = frameIndex;
#if PIN_TARGET_MAC
        [self _setImage:[NSImage imageWithCGImage:_frameImage]];
#else
        [self.layer setNeedsDisplay];
#endif
    }
}

- (void)resetDurationsWithAnimatedImage:(PINCachedAnimatedImage *)animatedImage
{
    PINAssertMain();
    if (!animatedImage) {
        return;
    }
    if (_durations) {
        free(_durations);
    }
    _durations = malloc(sizeof(CFTimeInterval) * animatedImage.frameCount);
    CFTimeInterval sum = 0.0f;
    for (int i = 0; i < animatedImage.frameCount; i++) {
        sum += [animatedImage durationAtIndex:i];
        _durations[i] = sum;
    }
}

- (NSUInteger)frameIndexAtPlayHeadPosition:(CFTimeInterval)playHead
{
    PINAssertMain();
    int low = 0, high = (int)_animatedImage.frameCount - 1;

    while (low <= high) {
        int mid = low + (high - low) / 2;
        if (_durations[mid] < playHead) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return MAX(MIN(low, (int)_animatedImage.frameCount - 1), 0);
}

@end

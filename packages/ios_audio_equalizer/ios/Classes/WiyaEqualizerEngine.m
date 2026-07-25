#import "WiyaEqualizerEngine.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import <objc/runtime.h>

static const NSInteger kWiyaEqBandCount = 5;
static const float kWiyaEqMinDb = -12.0f;
static const float kWiyaEqMaxDb = 12.0f;
static const float kWiyaEqDefaultQ = 1.0f;

typedef struct {
  float b0, b1, b2, a1, a2;
  float z1, z2;
} WiyaBiquad;

typedef struct {
  WiyaBiquad bands[kWiyaEqBandCount];
  float gainsDb[kWiyaEqBandCount];
  float centersHz[kWiyaEqBandCount];
  BOOL enabled;
  float sampleRate;
} WiyaEqTapContext;

static float clampf(float v, float lo, float hi) {
  return fmaxf(lo, fminf(hi, v));
}

static void wiya_biquad_peaking(WiyaBiquad *f, float sampleRate, float freqHz,
                                float gainDb, float q) {
  if (sampleRate <= 0 || freqHz <= 0 || fabsf(gainDb) < 0.01f) {
    f->b0 = 1;
    f->b1 = 0;
    f->b2 = 0;
    f->a1 = 0;
    f->a2 = 0;
    return;
  }

  const float A = powf(10.0f, gainDb / 40.0f);
  const float w0 = 2.0f * (float)M_PI * (freqHz / sampleRate);
  const float alpha = sinf(w0) / (2.0f * q);
  const float cosw0 = cosf(w0);

  const float b0 = 1.0f + alpha * A;
  const float b1 = -2.0f * cosw0;
  const float b2 = 1.0f - alpha * A;
  const float a0 = 1.0f + alpha / A;
  const float a1 = -2.0f * cosw0;
  const float a2 = 1.0f - alpha / A;

  f->b0 = b0 / a0;
  f->b1 = b1 / a0;
  f->b2 = b2 / a0;
  f->a1 = a1 / a0;
  f->a2 = a2 / a0;
}

static float wiya_biquad_process(WiyaBiquad *f, float x) {
  const float y = f->b0 * x + f->z1;
  f->z1 = f->b1 * x - f->a1 * y + f->z2;
  f->z2 = f->b2 * x - f->a2 * y;
  return y;
}

static void wiya_eq_rebuild(WiyaEqTapContext *ctx) {
  for (NSInteger i = 0; i < kWiyaEqBandCount; i++) {
    wiya_biquad_peaking(&ctx->bands[i], ctx->sampleRate, ctx->centersHz[i],
                        ctx->enabled ? ctx->gainsDb[i] : 0.0f, kWiyaEqDefaultQ);
    ctx->bands[i].z1 = 0;
    ctx->bands[i].z2 = 0;
  }
}

static void wiya_eq_tap_init(MTAudioProcessingTapRef tap, void *clientInfo,
                             void **tapStorageOut) {
  WiyaEqTapContext *ctx = (WiyaEqTapContext *)calloc(1, sizeof(WiyaEqTapContext));
  WiyaEqualizerEngine *engine = (__bridge WiyaEqualizerEngine *)clientInfo;
  NSArray<NSNumber *> *centers = engine.centerFrequenciesHz;
  NSArray<NSNumber *> *gains = [engine currentGainsDb];
  for (NSInteger i = 0; i < kWiyaEqBandCount; i++) {
    ctx->centersHz[i] = centers[i].floatValue;
    ctx->gainsDb[i] = gains[i].floatValue;
  }
  ctx->enabled = engine.enabled;
  ctx->sampleRate = 44100.0f;
  wiya_eq_rebuild(ctx);
  *tapStorageOut = ctx;
}

static void wiya_eq_tap_finalize(MTAudioProcessingTapRef tap) {
  WiyaEqTapContext *ctx =
      (WiyaEqTapContext *)MTAudioProcessingTapGetStorage(tap);
  free(ctx);
}

static void wiya_eq_tap_prepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames,
                                const AudioStreamBasicDescription *asbd) {
  WiyaEqTapContext *ctx =
      (WiyaEqTapContext *)MTAudioProcessingTapGetStorage(tap);
  ctx->sampleRate = (float)asbd->mSampleRate;
  wiya_eq_rebuild(ctx);
}

static void wiya_eq_tap_unprepare(MTAudioProcessingTapRef tap) {}

static void wiya_eq_tap_process(
    MTAudioProcessingTapRef tap, CMItemCount numberFrames,
    MTAudioProcessingTapFlags flags, AudioBufferList *bufferListInOut,
    CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut) {
  MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut,
                                     NULL, numberFramesOut);

  WiyaEqTapContext *ctx =
      (WiyaEqTapContext *)MTAudioProcessingTapGetStorage(tap);

  WiyaEqualizerEngine *engine = [WiyaEqualizerEngine shared];
  NSArray<NSNumber *> *gains = [engine currentGainsDb];
  BOOL enabled = engine.enabled;
  BOOL dirty = ctx->enabled != enabled;
  ctx->enabled = enabled;
  for (NSInteger i = 0; i < kWiyaEqBandCount; i++) {
    const float g = gains[i].floatValue;
    if (fabsf(ctx->gainsDb[i] - g) > 0.01f) {
      ctx->gainsDb[i] = g;
      dirty = YES;
    }
  }
  if (dirty) {
    wiya_eq_rebuild(ctx);
  }
  if (!ctx->enabled) {
    return;
  }

  for (UInt32 b = 0; b < bufferListInOut->mNumberBuffers; b++) {
    float *samples = (float *)bufferListInOut->mBuffers[b].mData;
    if (samples == NULL) continue;
    const UInt32 frames = (UInt32)(*numberFramesOut);
    const UInt32 channels =
        bufferListInOut->mBuffers[b].mNumberChannels > 0
            ? bufferListInOut->mBuffers[b].mNumberChannels
            : 1;

    if (channels == 1) {
      for (UInt32 i = 0; i < frames; i++) {
        float x = samples[i];
        for (NSInteger band = 0; band < kWiyaEqBandCount; band++) {
          x = wiya_biquad_process(&ctx->bands[band], x);
        }
        samples[i] = x;
      }
    } else {
      WiyaBiquad chFilters[2][kWiyaEqBandCount];
      for (int ch = 0; ch < 2; ch++) {
        memcpy(chFilters[ch], ctx->bands, sizeof(ctx->bands));
      }
      for (UInt32 i = 0; i < frames; i++) {
        for (UInt32 ch = 0; ch < channels && ch < 2; ch++) {
          float x = samples[i * channels + ch];
          for (NSInteger band = 0; band < kWiyaEqBandCount; band++) {
            x = wiya_biquad_process(&chFilters[ch][band], x);
          }
          samples[i * channels + ch] = x;
        }
      }
      memcpy(ctx->bands, chFilters[0], sizeof(ctx->bands));
    }
  }
}

@interface WiyaEqualizerEngine ()
@property (nonatomic, strong) NSHashTable<AVPlayerItem *> *trackedItems;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *gainsDb;
@property (nonatomic, strong) NSArray<NSNumber *> *centerFrequenciesHz;
@property (nonatomic, assign) float minDecibels;
@property (nonatomic, assign) float maxDecibels;
@end

@interface AVQueuePlayer (WiyaEqualizer)
- (void)wiya_eq_insertItem:(AVPlayerItem *)item afterItem:(AVPlayerItem *)afterItem;
@end

@interface AVPlayer (WiyaEqualizer)
- (void)wiya_eq_replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item;
@end

@implementation WiyaEqualizerEngine

+ (instancetype)shared {
  static WiyaEqualizerEngine *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[WiyaEqualizerEngine alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _enabled = NO;
    _minDecibels = kWiyaEqMinDb;
    _maxDecibels = kWiyaEqMaxDb;
    _centerFrequenciesHz = @[ @60, @230, @910, @3600, @14000 ];
    _gainsDb = [NSMutableArray arrayWithArray:@[ @0, @0, @0, @0, @0 ]];
    _trackedItems = [NSHashTable weakObjectsHashTable];
  }
  return self;
}

- (NSArray<NSNumber *> *)currentGainsDb {
  @synchronized(self) {
    return [_gainsDb copy];
  }
}

- (void)setGainDb:(float)gainDb forBand:(NSInteger)index {
  if (index < 0 || index >= kWiyaEqBandCount) return;
  @synchronized(self) {
    self.gainsDb[index] = @(clampf(gainDb, self.minDecibels, self.maxDecibels));
  }
  // Gains are read live inside the audio tap; no need to rebuild mixes.
}

- (void)setGainsDb:(NSArray<NSNumber *> *)gainsDb {
  @synchronized(self) {
    for (NSInteger i = 0; i < kWiyaEqBandCount && i < (NSInteger)gainsDb.count;
         i++) {
      self.gainsDb[i] =
          @(clampf(gainsDb[i].floatValue, self.minDecibels, self.maxDecibels));
    }
  }
}

- (void)resetGains {
  @synchronized(self) {
    for (NSInteger i = 0; i < kWiyaEqBandCount; i++) {
      self.gainsDb[i] = @0;
    }
  }
}

- (void)setEnabled:(BOOL)enabled {
  if (_enabled == enabled) return;
  _enabled = enabled;
  [self refreshAllTrackedItems];
}

- (AVAudioMix *)_buildAudioMixForTrack:(AVAssetTrack *)audioTrack {
  if (audioTrack == nil) return nil;

  MTAudioProcessingTapCallbacks callbacks;
  callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
  callbacks.clientInfo = (__bridge void *)self;
  callbacks.init = wiya_eq_tap_init;
  callbacks.prepare = wiya_eq_tap_prepare;
  callbacks.process = wiya_eq_tap_process;
  callbacks.unprepare = wiya_eq_tap_unprepare;
  callbacks.finalize = wiya_eq_tap_finalize;

  MTAudioProcessingTapRef tap = NULL;
  OSStatus status = MTAudioProcessingTapCreate(
      kCFAllocatorDefault, &callbacks,
      kMTAudioProcessingTapCreationFlag_PostEffects, &tap);
  if (status != noErr || tap == NULL) {
    return nil;
  }

  AVMutableAudioMixInputParameters *inputParams =
      [AVMutableAudioMixInputParameters
          audioMixInputParametersWithTrack:audioTrack];
  inputParams.audioTapProcessor = tap;
  CFRelease(tap);

  AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
  mix.inputParameters = @[ inputParams ];
  return mix;
}

/// Never call AVAsset tracks APIs on the calling thread — they can deadlock
/// playback. Always load keys asynchronously first.
- (void)applyToPlayerItem:(AVPlayerItem *)item {
  if (item == nil) return;

  @synchronized(self) {
    [self.trackedItems addObject:item];
  }

  // When EQ is off, clear any previous mix and skip work so playback stays fast.
  if (!self.enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (item.audioMix != nil) {
        item.audioMix = nil;
      }
    });
    return;
  }

  AVAsset *asset = item.asset;
  __weak typeof(self) weakSelf = self;
  [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ]
                       completionHandler:^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (strongSelf == nil) return;

                         NSError *error = nil;
                         AVKeyValueStatus status =
                             [asset statusOfValueForKey:@"tracks" error:&error];
                         if (status != AVKeyValueStatusLoaded) {
                           return;
                         }

                         AVAssetTrack *audioTrack =
                             [[asset tracksWithMediaType:AVMediaTypeAudio]
                                 firstObject];
                         if (audioTrack == nil || !strongSelf.enabled) {
                           return;
                         }

                         AVAudioMix *mix =
                             [strongSelf _buildAudioMixForTrack:audioTrack];
                         if (mix == nil) return;

                         dispatch_async(dispatch_get_main_queue(), ^{
                           BOOL stillTracked = NO;
                           @synchronized(strongSelf) {
                             stillTracked =
                                 [strongSelf.trackedItems containsObject:item];
                           }
                           if (stillTracked && strongSelf.enabled) {
                             item.audioMix = mix;
                           }
                         });
                       }];
}

- (void)refreshAllTrackedItems {
  NSArray<AVPlayerItem *> *items;
  @synchronized(self) {
    items = [self.trackedItems allObjects];
  }
  for (AVPlayerItem *item in items) {
    [self applyToPlayerItem:item];
  }
}

+ (void)load {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class queueCls = [AVQueuePlayer class];
    Method originalInsert = class_getInstanceMethod(
        queueCls, @selector(insertItem:afterItem:));
    Method swizzledInsert = class_getInstanceMethod(
        queueCls, @selector(wiya_eq_insertItem:afterItem:));
    if (originalInsert && swizzledInsert) {
      method_exchangeImplementations(originalInsert, swizzledInsert);
    }

    Class playerCls = [AVPlayer class];
    Method originalReplace = class_getInstanceMethod(
        playerCls, @selector(replaceCurrentItemWithPlayerItem:));
    Method swizzledReplace = class_getInstanceMethod(
        playerCls, @selector(wiya_eq_replaceCurrentItemWithPlayerItem:));
    if (originalReplace && swizzledReplace) {
      method_exchangeImplementations(originalReplace, swizzledReplace);
    }
    // Do NOT swizzle -play: applying mixes there blocked the main thread.
  });
}

@end

@implementation AVQueuePlayer (WiyaEqualizer)

- (void)wiya_eq_insertItem:(AVPlayerItem *)item afterItem:(AVPlayerItem *)afterItem {
  [self wiya_eq_insertItem:item afterItem:afterItem];
  // Track only; async apply when EQ enabled. Never block insert/play.
  [[WiyaEqualizerEngine shared] applyToPlayerItem:item];
}

@end

@implementation AVPlayer (WiyaEqualizer)

- (void)wiya_eq_replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
  [self wiya_eq_replaceCurrentItemWithPlayerItem:item];
  if (item != nil) {
    [[WiyaEqualizerEngine shared] applyToPlayerItem:item];
  }
}

@end

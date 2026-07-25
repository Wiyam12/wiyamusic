#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared EQ state + helpers that attach an MTAudioProcessingTap mix to AVPlayerItems.
@interface WiyaEqualizerEngine : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, readonly) NSArray<NSNumber *> *centerFrequenciesHz;
@property (nonatomic, readonly) float minDecibels;
@property (nonatomic, readonly) float maxDecibels;

- (NSArray<NSNumber *> *)currentGainsDb;
- (void)setGainDb:(float)gainDb forBand:(NSInteger)index;
- (void)setGainsDb:(NSArray<NSNumber *> *)gainsDb;
- (void)resetGains;
- (void)applyToPlayerItem:(AVPlayerItem *)item;
- (void)refreshAllTrackedItems;

@end

NS_ASSUME_NONNULL_END

#import "IosAudioEqualizerPlugin.h"
#import "WiyaEqualizerEngine.h"

@implementation IosAudioEqualizerPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel
      methodChannelWithName:@"com.wiyamusic/ios_audio_equalizer"
            binaryMessenger:[registrar messenger]];
  IosAudioEqualizerPlugin *instance =
      [[IosAudioEqualizerPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];

  // Ensure the EQ engine singleton (and AVPlayer swizzles) are loaded.
  (void)[WiyaEqualizerEngine shared];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
  WiyaEqualizerEngine *engine = [WiyaEqualizerEngine shared];

  if ([call.method isEqualToString:@"getParameters"]) {
    NSMutableArray *bands = [NSMutableArray array];
    NSArray<NSNumber *> *centers = engine.centerFrequenciesHz;
    NSArray<NSNumber *> *gains = [engine currentGainsDb];
    for (NSInteger i = 0; i < (NSInteger)centers.count; i++) {
      [bands addObject:@{
        @"index" : @(i),
        @"centerFrequency" : centers[i],
        @"gain" : gains[i],
      }];
    }
    result(@{
      @"minDecibels" : @(engine.minDecibels),
      @"maxDecibels" : @(engine.maxDecibels),
      @"enabled" : @(engine.enabled),
      @"bands" : bands,
    });
    return;
  }

  if ([call.method isEqualToString:@"setEnabled"]) {
    NSNumber *enabled = call.arguments[@"enabled"];
    engine.enabled = enabled.boolValue;
    result(nil);
    return;
  }

  if ([call.method isEqualToString:@"setBandGain"]) {
    NSNumber *index = call.arguments[@"index"];
    NSNumber *gain = call.arguments[@"gain"];
    [engine setGainDb:gain.floatValue forBand:index.integerValue];
    result(nil);
    return;
  }

  if ([call.method isEqualToString:@"setBandGains"]) {
    NSArray *gains = call.arguments[@"gains"];
    if ([gains isKindOfClass:[NSArray class]]) {
      [engine setGainsDb:gains];
    }
    result(nil);
    return;
  }

  if ([call.method isEqualToString:@"resetBands"]) {
    [engine resetGains];
    result(nil);
    return;
  }

  result(FlutterMethodNotImplemented);
}

@end

#import "FlutterMidiProPlugin.h"
#import <flutter_midi_pro/flutter_midi_pro-Swift.h>

@implementation FlutterMidiProPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterMidiProPlugin registerWithRegistrar:registrar];
}
@end

#import "GeneratedPluginRegistrant.h"
#import <Flutter/Flutter.h>

// FlutterSceneDelegate implements these UIWindowSceneDelegate methods but does
// not declare them in its public header. Declaring them here lets the Swift
// subclass override them and still forward to Flutter's implementation.
@interface FlutterSceneDelegate (UlashForwarding)
- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions;
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;
@end

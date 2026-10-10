#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <CoreMedia/CoreMedia.h>
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include "ios_host.h"
#include "host.h"
#include "room_bridge.h"
#include "xiso.h"
#include "tvos_host.h"
#include <SDL3/SDL.h>
/* No on-screen controls on Apple TV; the Siri Remote and game controllers go through SDL. */

/* GameController applies a controller's input on the main queue and SDL reads
   the controller's state once a frame (60 a second on a TV), so a quick tap
   whose press and release both fall between two reads never reached the game
   (seen with a DualSense D-pad). Every press is latched here, under the player
   index SDL gives the controller, and reported at the next read of that
   button. */
#define LATCH_PLAYERS 8
static uint32_t latched[LATCH_PLAYERS];
static uint32_t pressed_buttons(GCExtendedGamepad *g) {
    uint32_t b=0;
#define PRESSED(input,button) if((input).isPressed)b|=1u<<(button)
    PRESSED(g.buttonA,SDL_GAMEPAD_BUTTON_SOUTH);PRESSED(g.buttonB,SDL_GAMEPAD_BUTTON_EAST);
    PRESSED(g.buttonX,SDL_GAMEPAD_BUTTON_WEST);PRESSED(g.buttonY,SDL_GAMEPAD_BUTTON_NORTH);
    PRESSED(g.leftShoulder,SDL_GAMEPAD_BUTTON_LEFT_SHOULDER);PRESSED(g.rightShoulder,SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER);
    PRESSED(g.leftThumbstickButton,SDL_GAMEPAD_BUTTON_LEFT_STICK);PRESSED(g.rightThumbstickButton,SDL_GAMEPAD_BUTTON_RIGHT_STICK);
    PRESSED(g.buttonMenu,SDL_GAMEPAD_BUTTON_START);PRESSED(g.buttonOptions,SDL_GAMEPAD_BUTTON_BACK);
    PRESSED(g.dpad.up,SDL_GAMEPAD_BUTTON_DPAD_UP);PRESSED(g.dpad.down,SDL_GAMEPAD_BUTTON_DPAD_DOWN);
    PRESSED(g.dpad.left,SDL_GAMEPAD_BUTTON_DPAD_LEFT);PRESSED(g.dpad.right,SDL_GAMEPAD_BUTTON_DPAD_RIGHT);
    if([g isKindOfClass:GCDualSenseGamepad.class])PRESSED(((GCDualSenseGamepad *)g).touchpadButton,SDL_GAMEPAD_BUTTON_TOUCHPAD);
    else if([g isKindOfClass:GCDualShockGamepad.class])PRESSED(((GCDualShockGamepad *)g).touchpadButton,SDL_GAMEPAD_BUTTON_TOUCHPAD);
#undef PRESSED
    return b;
}
static void latch_presses(GCController *controller) {
    controller.extendedGamepad.valueChangedHandler=^(GCExtendedGamepad *gamepad,GCControllerElement *element) {
        (void)element;
        NSInteger player=gamepad.controller.playerIndex;
        if(player>=0 && player<LATCH_PLAYERS)latched[player]|=pressed_buttons(gamepad);
    };
}
void host_ios_touch_initialize(void) {
    for(GCController *controller in GCController.controllers)latch_presses(controller);
    [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {latch_presses(note.object);}];
}

/* The game draws standard dynamic range. With Settings > Video and Audio >
   Match Content > Match Dynamic Range on, tvOS switches the TV to SDR while
   the game is in front, as it does for SDR video, and back for the Home screen
   and other apps; HDR video elsewhere still plays in HDR. The request names
   the refresh rate the TV has at launch (the Format setting's), so Match Frame
   Rate leaves it as it is; the game's Frame Rate setting paces its frames
   within it. Without matching, tvOS ignores this and keeps the Format
   setting's mode. */
static void request_sdr_display(UIWindow *window) {
    NSDictionary *bt709=@{
        (__bridge NSString *)kCMFormatDescriptionExtension_ColorPrimaries:(__bridge NSString *)kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
        (__bridge NSString *)kCMFormatDescriptionExtension_TransferFunction:(__bridge NSString *)kCMFormatDescriptionTransferFunction_ITU_R_709_2,
        (__bridge NSString *)kCMFormatDescriptionExtension_YCbCrMatrix:(__bridge NSString *)kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2};
    CMVideoFormatDescriptionRef format=NULL;
    if(CMVideoFormatDescriptionCreate(kCFAllocatorDefault,kCMVideoCodecType_H264,1920,1080,(__bridge CFDictionaryRef)bt709,&format)!=noErr)return;
    AVDisplayManager *manager=window.avDisplayManager;
    NSInteger refresh=window.windowScene.screen.maximumFramesPerSecond;
    if(refresh<=0)refresh=60;
    manager.preferredDisplayCriteria=[[AVDisplayCriteria alloc] initWithRefreshRate:(float)refresh formatDescription:format];
    CFRelease(format);
    host_logf(HOST_LOG_INFO,"display: asked for SDR at %ld Hz, the current refresh rate (Match Content %s)",(long)refresh,
        manager.displayCriteriaMatchingEnabled?"on":"off: the request is ignored");
    [NSNotificationCenter.defaultCenter addObserverForName:AVDisplayManagerModeSwitchEndNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            host_logf(HOST_LOG_INFO,"display: mode switch finished");
        }];
}
void host_ios_touch_attach(SDL_Window *window) {
    UIWindow *native=(__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER,NULL);
    /* Retire SDL's temporary launch window before entering the non-returning game loop. */
    for(UIWindow *candidate in native.windowScene.windows) {
        if(candidate!=native && [NSStringFromClass(candidate.rootViewController.class) hasPrefix:@"SDLLaunch"])
            candidate.hidden=YES;
    }
    [native makeKeyAndVisible];
    request_sdr_display(native);
    UIView *root=native.rootViewController.view;
    host_logf(HOST_LOG_INFO,"window attached, %.0fx%.0f",root.bounds.size.width,root.bounds.size.height);
}
void host_ios_touch_reset(void) {}
void host_ios_touch_focus(void) {}
int host_ios_gamepads(uint32_t *out,int capacity){int count=0;SDL_JoystickID *ids=SDL_GetGamepads(&count);int n=MIN(count,capacity);for(int i=0;i<n;i++)out[i]=ids[i];SDL_free(ids);return n;}
int host_ios_gamepad_type(SDL_Gamepad *pad){return SDL_GetGamepadType(pad);}
int host_ios_gamepad_axis(SDL_Gamepad *pad,int axis){return SDL_GetGamepadAxis(pad,(SDL_GamepadAxis)axis);}
int host_ios_gamepad_button(SDL_Gamepad *pad,int button){
    int down=SDL_GetGamepadButton(pad,(SDL_GamepadButton)button),player=SDL_GetGamepadPlayerIndex(pad);
    if(player>=0 && player<LATCH_PLAYERS && button>=0 && button<32) {
        uint32_t bit=1u<<button;
        if(!down && (latched[player]&bit)) {
            down=1;
            host_logf(HOST_LOG_INFO,"controller: a tap between two reads of button %d, passed on",button);
        }
        latched[player]&=~bit;
    }
    return down;
}

/* Browser rooms need WebKit, which tvOS lacks. */
void host_ios_room_prepare(void) {}
void host_ios_room_tick(void) {}
void host_ios_room_report(const char *json) {(void)json;}
void host_ios_room_test_navigation_consumed(void) {}
void host_ios_room_open(void) {
    host_logf(HOST_LOG_ERROR,"Browser rooms are not available on Apple TV");
    const uint32_t command[4]={2,1,0,0};ios_room_queue_command(command);
}

static void copy_path(char *out,size_t size,NSString *path) {
    snprintf(out,size,"%s",path.fileSystemRepresentation);
}
void host_tv_prepare_game_data(const char *documents, char *data_root, size_t data_size,
    char *maps_root, size_t maps_size, char *custom_root, size_t custom_size) {
    NSFileManager *files=NSFileManager.defaultManager;
    NSString *bundleGame=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameData"];
    NSString *bundleMaps=[bundleGame stringByAppendingPathComponent:@"maps"];
    char error[256]="";
    if(!xiso_maps_ready(bundleMaps.fileSystemRepresentation,error,sizeof error))
        host_fatal("This build has no game data. Build it with tools/tvos_build.py --game-data <folder with the Xbox maps>.");
    NSString *docs=[NSString stringWithUTF8String:documents];
    NSString *game=[docs stringByAppendingPathComponent:@"game"];
    [files createDirectoryAtPath:game withIntermediateDirectories:YES attributes:nil error:nil];
    /* the game reads d:\maps\ from the bundle (paths.maps); tvOS does not let
       the app link to its bundle from Caches */
    copy_path(data_root,data_size,game);
    copy_path(maps_root,maps_size,bundleMaps);
    NSString *custom=[bundleGame stringByAppendingPathComponent:@"CustomEdition"];
    BOOL directory=NO;
    if(!([files fileExistsAtPath:[custom stringByAppendingPathComponent:@"maps"] isDirectory:&directory] && directory)) {
        custom=[docs stringByAppendingPathComponent:@"CustomEdition"];
        [files createDirectoryAtPath:[custom stringByAppendingPathComponent:@"maps"] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    copy_path(custom_root,custom_size,custom);
    host_logf(HOST_LOG_INFO,"game data %s, custom edition %s",data_root,custom_root);
}

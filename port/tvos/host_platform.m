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
void host_ios_touch_initialize(void) {}
void host_ios_touch_attach(SDL_Window *window) {
    UIWindow *native=(__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER,NULL);
    /* Retire SDL's temporary launch window before entering the non-returning game loop. */
    for(UIWindow *candidate in native.windowScene.windows) {
        if(candidate!=native && [NSStringFromClass(candidate.rootViewController.class) hasPrefix:@"SDLLaunch"])
            candidate.hidden=YES;
    }
    [native makeKeyAndVisible];
    UIView *root=native.rootViewController.view;
    host_logf(HOST_LOG_INFO,"window attached, %.0fx%.0f",root.bounds.size.width,root.bounds.size.height);
}
void host_ios_touch_reset(void) {}
void host_ios_touch_focus(void) {}
int host_ios_gamepads(uint32_t *out,int capacity){int count=0;SDL_JoystickID *ids=SDL_GetGamepads(&count);int n=MIN(count,capacity);for(int i=0;i<n;i++)out[i]=ids[i];SDL_free(ids);return n;}
int host_ios_gamepad_type(SDL_Gamepad *pad){return SDL_GetGamepadType(pad);}
int host_ios_gamepad_axis(SDL_Gamepad *pad,int axis){return SDL_GetGamepadAxis(pad,(SDL_GamepadAxis)axis);}
int host_ios_gamepad_button(SDL_Gamepad *pad,int button){return SDL_GetGamepadButton(pad,(SDL_GamepadButton)button);}

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

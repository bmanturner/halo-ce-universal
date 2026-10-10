#include <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#include "host_debug.h"
int halo_metalfx_supported(void) {return 0;}
int halo_metalfx_enabled(void) {return 0;}
void halo_metalfx_set_enabled(int enabled) {(void)enabled;}
unsigned int host_ios_render_height(void) {return 0;}
int host_ios_metalfx_present(unsigned int t,unsigned int w,unsigned int h,unsigned int ow,unsigned int oh) {(void)t;(void)w;(void)h;(void)ow;(void)oh;return 0;}
#else
/* Optional ANGLE Metal -> IOSurface -> MetalFX presentation. ANGLE blits the
   game's frame into one of two shared IOSurface textures and signals an
   MTLSharedEvent on the GPU; the MetalFX command buffer waits for that value on
   the GPU, scales straight into the CAMetalLayer drawable and presents it. The
   CPU never waits for a frame, only (through a counting semaphore) for the
   command buffer from two frames earlier, which also keeps a shared texture from
   being overwritten while MetalFX still reads it. Without the event extension
   the hand-off falls back to glFinish. */
#if HALO_MACOS
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif
#include <GLES3/gl32.h>
#include <GLES2/gl2ext.h>
#include <stdatomic.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <MetalFX/MTLFXSpatialScaler.h>
#import <QuartzCore/QuartzCore.h>
#include "ios_host.h"
#include "host_gl_dispatch.h"
#include "host_debug.h"

#define DEFAULT_INPUT_HEIGHT 720
static const MTLPixelFormat drawableFormat=MTLPixelFormatBGRA8Unorm;

/* Latched by halo_metalfx_set_enabled at launch: the game's render targets are
   sized for it once, so it never changes while the app runs. */
static BOOL enabled;
/* Set when presentation failed; frames then use the normal ANGLE path. */
static BOOL failed;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static id<MTLFXSpatialScaler> scaler;
static id<MTLSharedEvent> sharedEvent;
static uint64_t eventValue;
static dispatch_semaphore_t inFlight;
static atomic_bool commandFailed;

static CVMetalTextureCacheRef metalCache;
static CVPixelBufferRef pixels[HALO_GRAPHICS_SHARED_SLOTS];
static CVMetalTextureRef metalImage[HALO_GRAPHICS_SHARED_SLOTS];
static GLuint sharedTexture[HALO_GRAPHICS_SHARED_SLOTS];
static unsigned frameSlot;
/* Only used when a drawable cannot be the scaler's output. */
static id<MTLTexture> output;
static int outputPath; /* 0 not yet chosen, 1 scaler writes the drawable, 2 scaler writes `output`, then a copy */
#if HALO_MACOS
@interface HaloMetalSurface : NSView
@end
@implementation HaloMetalSurface
-(NSView *)hitTest:(NSPoint)point {(void)point;return nil;}
@end
static NSView *surface;
#else
static UIView *surface;
#endif
static CAMetalLayer *layer;
static CGRect placedFrame;
static CGFloat placedScale;
static GLuint readFBO,writeFBO;
static unsigned inputW,inputH,outputW,outputH;

int halo_metalfx_supported(void) {
    if(!device)device=MTLCreateSystemDefaultDevice();
    return device && [MTLFXSpatialScalerDescriptor supportsDevice:device];
}
int halo_metalfx_enabled(void) {return enabled;}
void halo_metalfx_set_enabled(int value) {
    enabled=value && halo_graphics_metal() && halo_metalfx_supported();
    host_logf(HOST_LOG_INFO,"MetalFX spatial upscaling %s",enabled?"enabled":"disabled");
}
/* The game's default MetalFX input height; display.render_height overrides it
   in screen_mode_choose. */
unsigned int host_ios_render_height(void) {return enabled?DEFAULT_INPUT_HEIGHT:0;}
/* Wait for every submitted frame; only for reconfiguration and failure. */
static void drain(void) {
    if(!inFlight)return;
    for(int i=0;i<HALO_GRAPHICS_SHARED_SLOTS;i++)dispatch_semaphore_wait(inFlight,DISPATCH_TIME_FOREVER);
    for(int i=0;i<HALO_GRAPHICS_SHARED_SLOTS;i++)dispatch_semaphore_signal(inFlight);
}
static void releaseImages(void) {
    drain();
    halo_graphics_shared_destroy();
    for(int i=0;i<HALO_GRAPHICS_SHARED_SLOTS;i++) {
        sharedTexture[i]=0;
        if(metalImage[i]){CFRelease(metalImage[i]);metalImage[i]=NULL;}
        if(pixels[i]){CFRelease(pixels[i]);pixels[i]=NULL;}
    }
    if(metalCache)CVMetalTextureCacheFlush(metalCache,0);
    scaler=nil;output=nil;outputPath=0;frameSlot=0;inputW=inputH=outputW=outputH=0;
}
static BOOL configure(unsigned w,unsigned h,unsigned ow,unsigned oh) {
    releaseImages();
    if(!queue)queue=[device newCommandQueue];
    if(!queue)return NO;
    if(!inFlight)inFlight=dispatch_semaphore_create(HALO_GRAPHICS_SHARED_SLOTS);
    if(halo_graphics_shared_event_supported() && !sharedEvent)sharedEvent=[device newSharedEvent];
    if(!metalCache && CVMetalTextureCacheCreate(NULL,NULL,device,NULL,&metalCache)!=kCVReturnSuccess)return NO;
    MTLFXSpatialScalerDescriptor *desc=[MTLFXSpatialScalerDescriptor new];
    desc.inputWidth=w;desc.inputHeight=h;desc.outputWidth=ow;desc.outputHeight=oh;
    desc.colorTextureFormat=MTLPixelFormatBGRA8Unorm;desc.outputTextureFormat=drawableFormat;
    desc.colorProcessingMode=MTLFXSpatialScalerColorProcessingModePerceptual;
    scaler=[desc newSpatialScalerWithDevice:device];if(!scaler)return NO;
    NSDictionary *attributes=@{(id)kCVPixelBufferIOSurfacePropertiesKey:@{},(id)kCVPixelBufferMetalCompatibilityKey:@YES};
    NSDictionary *textureAttributes=@{(id)kCVMetalTextureUsage:@(scaler.colorTextureUsage)};
    for(unsigned i=0;i<HALO_GRAPHICS_SHARED_SLOTS;i++) {
        if(CVPixelBufferCreate(NULL,w,h,kCVPixelFormatType_32BGRA,(__bridge CFDictionaryRef)attributes,&pixels[i])!=kCVReturnSuccess)return NO;
        sharedTexture[i]=halo_graphics_shared_create(i,CVPixelBufferGetIOSurface(pixels[i]),w,h);
        if(!sharedTexture[i])return NO;
        if(CVMetalTextureCacheCreateTextureFromImage(NULL,metalCache,pixels[i],(__bridge CFDictionaryRef)textureAttributes,MTLPixelFormatBGRA8Unorm,w,h,0,&metalImage[i])!=kCVReturnSuccess)return NO;
    }
    scaler.inputContentWidth=w;scaler.inputContentHeight=h;
    if(!readFBO)glGenFramebuffers(1,&readFBO);
    if(!writeFBO)glGenFramebuffers(1,&writeFBO);
    inputW=w;inputH=h;outputW=ow;outputH=oh;
    host_logf(HOST_LOG_INFO,"MetalFX configured: input %ux%u, output %ux%u, GPU hand-off %s",w,h,ow,oh,sharedEvent?"shared event":"glFinish");
    return YES;
}
/* The layer is exactly the scaler's output size and sits centred on the black
   surface, so the drawable is the scaler's output and the compositor does no scaling. */
static void placeLayer(unsigned ow,unsigned oh) {
#if HALO_MACOS
    CGFloat scale=surface.window.backingScaleFactor;
#else
    CGFloat scale=surface.window.screen.scale;
#endif
    if(scale<1)scale=1;
    CGFloat width=round(surface.bounds.size.width*scale),height=round(surface.bounds.size.height*scale);
    CGRect frame=CGRectMake(fmax(0,floor((width-ow)/2))/scale,fmax(0,floor((height-oh)/2))/scale,ow/scale,oh/scale);
    if(scale!=placedScale || !CGRectEqualToRect(frame,placedFrame)) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        layer.contentsScale=scale;layer.frame=frame;
        [CATransaction commit];
        placedScale=scale;placedFrame=frame;
    }
    if(layer.drawableSize.width!=ow || layer.drawableSize.height!=oh)layer.drawableSize=CGSizeMake(ow,oh);
}
static BOOL createSurface(void) {
#if HALO_MACOS
    extern void *host_macos_game_window(void);
    NSWindow *window=(__bridge NSWindow *)host_macos_game_window();
    NSView *root=window.contentView;
    if(!root)return NO;
    surface=[[HaloMetalSurface alloc]initWithFrame:root.bounds];surface.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    surface.wantsLayer=YES;surface.layer.backgroundColor=NSColor.blackColor.CGColor;
#else
    UIWindow *window=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])for(UIWindow *candidate in ((UIWindowScene*)scene).windows)if(candidate.isKeyWindow)window=candidate;
    UIView *root=window.rootViewController.view;
    if(!root)return NO;
    surface=[[UIView alloc]initWithFrame:root.bounds];surface.userInteractionEnabled=NO;surface.backgroundColor=UIColor.blackColor;
    surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
#endif
    layer=[CAMetalLayer layer];layer.device=device;layer.pixelFormat=drawableFormat;layer.opaque=YES;
    /* The scaler writes the drawable's texture directly, which needs shader-write usage. */
    layer.framebufferOnly=NO;
    [surface.layer addSublayer:layer];
#if HALO_MACOS
    [root addSubview:surface];
#else
    [root insertSubview:surface atIndex:0];
#endif
    return YES;
}
/* Presenting: this function owns the frame's only present, so the caller skips
   the ANGLE swap. Pacing comes from [layer nextDrawable] (display-synced, three
   drawables) together with the two-frame semaphore, which is what eglSwapBuffers
   gave the ANGLE path. A failure returns 0 and every later frame is presented by ANGLE. */
int host_ios_metalfx_present(unsigned int texture,unsigned int w,unsigned int h,unsigned int ow,unsigned int oh) {
    if(!enabled || failed || !w || !h || !ow || !oh)return 0;
    halo_graphics_pace_frame();
    @autoreleasepool {
        GLint oldRead,oldWrite,oldTexture;glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&oldRead);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&oldWrite);glGetIntegerv(GL_TEXTURE_BINDING_2D,&oldTexture);
        BOOL scissor=glIsEnabled(GL_SCISSOR_TEST),success=YES,acquired=NO,submitted=NO;
        if(atomic_load(&commandFailed)){host_logf(HOST_LOG_ERROR,"MetalFX: a command buffer failed");success=NO;}
        if(success && (w!=inputW || h!=inputH || ow!=outputW || oh!=outputH))success=configure(w,h,ow,oh);
        if(success && !surface)success=createSurface();
        if(success)placeLayer(ow,oh);
        if(success){dispatch_semaphore_wait(inFlight,DISPATCH_TIME_FOREVER);acquired=YES;}
        unsigned slot=frameSlot%HALO_GRAPHICS_SHARED_SLOTS;
        if(success)success=halo_graphics_shared_begin(slot);
        int handoff=0;
        uint64_t value=eventValue+1;
        if(success) {
            glBindFramebuffer(GL_READ_FRAMEBUFFER,readFBO);glFramebufferTexture2D(GL_READ_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,texture,0);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER,writeFBO);
            glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,sharedTexture[slot],0);glDisable(GL_SCISSOR_TEST);
            success=glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
        }
        if(success) {
            /* Guest row zero already denotes the top, as Metal expects. */
            glBlitFramebuffer(0,0,w,h,0,0,w,h,GL_COLOR_BUFFER_BIT,GL_NEAREST);
            handoff=halo_graphics_shared_end(slot,sharedEvent?(__bridge void *)sharedEvent:NULL,value);
            success=handoff!=0;
        }
        if(success) {
            id<CAMetalDrawable> drawable=[layer nextDrawable];
            id<MTLTexture> target=drawable.texture;
            if(!target || target.width<ow || target.height<oh) {
                host_logf(HOST_LOG_WARN,"MetalFX drawable unavailable or too small (%ux%u requested)",ow,oh);success=NO;
            } else {
                BOOL direct=target.pixelFormat==drawableFormat && target.width==ow && target.height==oh && (target.usage&scaler.outputTextureUsage)==scaler.outputTextureUsage;
                if(!direct && !output) {
                    MTLTextureDescriptor *description=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:drawableFormat width:ow height:oh mipmapped:NO];
                    description.storageMode=MTLStorageModePrivate;description.usage=scaler.outputTextureUsage;
                    output=[device newTextureWithDescriptor:description];
                    if(!output)success=NO;
                }
                if(success && outputPath!=(direct?1:2)) {
                    outputPath=direct?1:2;
                    host_logf(HOST_LOG_INFO,"MetalFX output: %s (drawable %lux%lu, usage %lu)",direct?"scaler writes the drawable":"scaler writes a private texture, then a copy",(unsigned long)target.width,(unsigned long)target.height,(unsigned long)target.usage);
                }
                if(success) {
                    id<MTLCommandBuffer> commands=[queue commandBuffer];
                    if(handoff==HALO_GRAPHICS_SHARED_SIGNALED)[commands encodeWaitForEvent:sharedEvent value:value];
                    scaler.colorTexture=CVMetalTextureGetTexture(metalImage[slot]);scaler.outputTexture=direct?target:output;
                    [scaler encodeToCommandBuffer:commands];
                    if(!direct) {
                        if(target.width!=ow || target.height!=oh) {
                            MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
                            pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);
                            [[commands renderCommandEncoderWithDescriptor:pass]endEncoding];
                        }
                        id<MTLBlitCommandEncoder> blit=[commands blitCommandEncoder];
                        [blit copyFromTexture:output sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(ow,oh,1) toTexture:target destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake((target.width-ow)/2,(target.height-oh)/2,0)];
                        [blit endEncoding];
                    }
                    [commands presentDrawable:drawable];
                    dispatch_semaphore_t semaphore=inFlight;
                    [commands addCompletedHandler:^(id<MTLCommandBuffer> finished) {
                        if(finished.status==MTLCommandBufferStatusError) {
                            host_logf(HOST_LOG_ERROR,"MetalFX: %s",finished.error.localizedDescription.UTF8String);
                            atomic_store(&commandFailed,true);
                        }
                        dispatch_semaphore_signal(semaphore);
                    }];
                    [commands commit];
                    submitted=YES;eventValue=value;frameSlot++;
                    if(surface.hidden)surface.hidden=NO;
                }
            }
        }
        if(acquired && !submitted)dispatch_semaphore_signal(inFlight);
        glBindFramebuffer(GL_READ_FRAMEBUFFER,oldRead);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,oldWrite);glBindTexture(GL_TEXTURE_2D,oldTexture);
        if(scissor)glEnable(GL_SCISSOR_TEST);else glDisable(GL_SCISSOR_TEST);
        if(!success) {
            failed=YES;surface.hidden=YES;releaseImages();
            host_logf(HOST_LOG_WARN,"MetalFX presentation stopped; using the normal Metal path");
        }
        return success;
    }
}

#endif

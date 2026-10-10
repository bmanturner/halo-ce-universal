#pragma once
#include <stdint.h>
struct SDL_Window;
void halo_graphics_initialize(void);
int halo_graphics_metal(void);
int halo_graphics_prefer_metal(void);
void halo_graphics_set_preference(int metal);
void *halo_graphics_proc(const char *name);
int halo_graphics_has_extension(const char *name);
void *halo_graphics_create(struct SDL_Window *window);
int halo_graphics_make_current(void);
int halo_graphics_swap(void);
int halo_graphics_swap_interval(int interval);
/* IOSurface ownership is transferred to/from ANGLE around each MetalFX copy.
   Each slot is one IOSurface-backed GL texture; MetalFX double-buffers them. */
#define HALO_GRAPHICS_SHARED_SLOTS 2
/* halo_graphics_shared_end results: 0 failed; COMPLETE the GPU work is finished
   (glFinish); SIGNALED the work is submitted and the MTLSharedEvent will reach
   the value on the GPU. */
#define HALO_GRAPHICS_SHARED_COMPLETE 1
#define HALO_GRAPHICS_SHARED_SIGNALED 2
int halo_graphics_shared_event_supported(void);
unsigned int halo_graphics_shared_create(unsigned int slot,void *iosurface,unsigned int width,unsigned int height);
int halo_graphics_shared_begin(unsigned int slot);
/* event is an id<MTLSharedEvent> (bridged) or NULL; with it, no CPU wait. */
int halo_graphics_shared_end(unsigned int slot,void *event,uint64_t value);
void halo_graphics_shared_destroy_slot(unsigned int slot);
void halo_graphics_shared_destroy(void);

/* Apple TV services that the shared Apple host (port/ios/host/host_main.m) calls. */
#ifndef HALO_TVOS_HOST_H
#define HALO_TVOS_HOST_H
#include <stddef.h>
/* The maps built into the app (GameData in its bundle, tools/tvos_build.py).
   Writes to data_root the writable game folder <documents>/game, to maps_root
   the bundle's GameData/maps (paths.maps: tvOS refuses a link to it), and to
   custom_root the Custom Edition folder: the bundle's GameData/CustomEdition,
   else an empty <documents>/CustomEdition. Ends the app with a message when
   the build has no maps. */
void host_tv_prepare_game_data(const char *documents, char *data_root, size_t data_size,
    char *maps_root, size_t maps_size, char *custom_root, size_t custom_size);
/* Mirrors <save_root> and <documents>/config.toml to the iCloud container that
   HaloCloudContainer in Info.plist names. First restores the files that are
   missing (tvOS empties Caches when it needs space), waiting a bounded time,
   then uploads the files as they change. Does nothing without a container or
   an iCloud account. */
void host_cloud_saves_start(const char *documents, const char *save_root);
#endif

/*
WEB_STUBS.C

What the platform layer links against that a browser does not have: the
router (UPnP) and Discord for internet play, which stays off in the web
build (web_main.c), the Android app's on-screen touch controls, a C library
function Emscripten names differently and an MSVC intrinsic clang knows only
on x86 and ARM.
*/

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

typedef unsigned int posix_ulong;

/* ---------- internet play (p2p.c) */

int posix_upnp_forward_udp(unsigned short port, unsigned short preferred_port, posix_ulong *external_address, unsigned short *external_port,
	char *error, int error_size)
{
	(void)port;
	(void)preferred_port;
	(void)external_address;
	(void)external_port;
	if (error && error_size > 0)
	{
		strncpy(error, "UPnP is not available in a browser", (size_t)error_size - 1);
		error[error_size - 1] = '\0';
	}
	return 0;
}

void posix_upnp_stop_forwarding_udp(unsigned short external_port)
{
	(void)external_port;
}

/* ---------- the Android app's touch controls (touch_input.c)

The web build is HALO_ANDROID, but the page draws its own touch controls
(site/input.js), which reach the game as a controller: the Android overlay
reads as idle and shown nowhere, with no system gesture edges. */

void host_gesture_insets(int *insets)
{
	memset(insets, 0, 4 * sizeof(*insets));
}

void host_touch_read(int *state)
{
	memset(state, 0, 7 * sizeof(*state));
}

void host_touch_look_read(float *delta)
{
	memset(delta, 0, 4 * sizeof(*delta));
}

void host_touch_rumble(unsigned int low, unsigned int high)
{
	(void)low;
	(void)high;
}

void host_touch_scene(int scene)
{
	(void)scene;
}

void host_touch_bindings(const int *controls)
{
	(void)controls;
}

/* ---------- the C library (posix_net.c) */

ssize_t getrandom(void *buffer, size_t size, unsigned int flags)
{
	unsigned char *cursor = buffer;
	size_t left = size;

	(void)flags;
	while (left)
	{
		/* getentropy gives at most 256 bytes at a time */
		size_t chunk = left > 256 ? 256 : left;

		if (getentropy(cursor, chunk) != 0)
			return size - left ? (ssize_t)(size - left) : -1;
		cursor += chunk;
		left -= chunk;
	}
	return (ssize_t)size;
}

/* ---------- MSVC (scenario.c): a compiler barrier */

void _ReadWriteBarrier(void)
{
	__atomic_signal_fence(__ATOMIC_SEQ_CST);
}

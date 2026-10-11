# internet play's DTLS with browsers in the Apple host: posix_dtls.c with the
# vendored Mbed TLS (port/third_party/mbedtls, default configuration), as the
# other posix_*.c are in the host and as tools/android_build.py builds it.
# Mbed TLS's entropy is the platform's: /dev/urandom (read-only access that the
# iOS, tvOS and macOS sandboxes allow), with PSA's CTR_DRBG on top.
# Include after add_executable(HaloCE ...) and ROOT.
set(HALO_MBEDTLS_DIR "${ROOT}/port/third_party/mbedtls")
file(GLOB HALO_MBEDTLS_SOURCES "${HALO_MBEDTLS_DIR}/library/*.c")
target_sources(HaloCE PRIVATE "${ROOT}/port/linux/src/posix_dtls.c" ${HALO_MBEDTLS_SOURCES})
target_include_directories(HaloCE PRIVATE "${HALO_MBEDTLS_DIR}/include" "${HALO_MBEDTLS_DIR}/library")
# The vendored library is compiled quietly, nothing in it is changed.
set_source_files_properties(${HALO_MBEDTLS_SOURCES} PROPERTIES COMPILE_OPTIONS "-w")

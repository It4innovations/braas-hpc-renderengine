#ifndef HDR_BLOCK_CODEC_H
#define HDR_BLOCK_CODEC_H

#include <cstdint>
#include <cstddef>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations
struct Half4;

// Codec profiles
enum class HDRCodecProfile : uint32_t {
    HDR_4BPP_PREVIEW   = 4,
    HDR_8BPP_ENDPOINTS = 8,
    HDR_16BPP_QUALITY  = 16
};

// Size calculation helpers
int blocks_x_for(int width);
int blocks_y_for(int height);
int num_blocks_for(int width, int height);

size_t compressed_size_bytes(
    int width,
    int height,
    HDRCodecProfile profile);

// Compression and decompression functions
void compress_frame_cuda(
    const Half4* d_src,
    void* d_blocks,
    int width,
    int height,
    HDRCodecProfile profile);

void decompress_frame_cuda(
    const void* d_blocks,
    Half4* d_dst,
    int width,
    int height,
    HDRCodecProfile profile);

#ifdef __cplusplus
}
#endif

#endif // HDR_BLOCK_CODEC_H

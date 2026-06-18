// #####################################################################################################################
// # Copyright(C) 2011-2026 IT4Innovations National Supercomputing Center, VSB - Technical University of Ostrava
// #
// # This program is free software : you can redistribute it and/or modify
// # it under the terms of the GNU General Public License as published by
// # the Free Software Foundation, either version 3 of the License, or
// # (at your option) any later version.
// #
// # This program is distributed in the hope that it will be useful,
// # but WITHOUT ANY WARRANTY; without even the implied warranty of
// # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
// # GNU General Public License for more details.
// #
// # You should have received a copy of the GNU General Public License
// # along with this program.  If not, see <https://www.gnu.org/licenses/>.
// #
// #####################################################################################################################

// CUDA half4 linear HDR image codec with selectable fixed-bpp profiles.
//
// This is NOT standards-compliant BC6H.
// It is a simple block-based HDR RGB codec for TCP streaming:
//
//   input:  half4 linear RGBA
//   output: compressed 4x4 blocks
//   decode: half4 linear RGBA
//
// Profiles:
//
//   4 bpp:
//     8 bytes / 4x4 block
//     preview quality
//     luminance + average chroma
//
//   8 bpp:
//     16 bytes / 4x4 block
//     current BC6H-like endpoint codec
//     2 RGB half endpoints + 2-bit index per pixel
//
//   16 bpp:
//     32 bytes / 4x4 block
//     higher quality
//     2 RGB float endpoints + 4-bit index per pixel
//
// For Full HD 1920x1080 at 25 FPS:
//   4 bpp  = ~207 Mbit/s
//   8 bpp  = ~415 Mbit/s
//   16 bpp = ~829 Mbit/s

#include <cuda_runtime.h>
#include <cuda_fp16.h>

#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
#include <cstdint>
#include <algorithm>
#include <cstring>

#define CUDA_CHECK(call)                                                     \
    do {                                                                     \
        cudaError_t err__ = (call);                                          \
        if (err__ != cudaSuccess) {                                          \
            std::fprintf(stderr, "CUDA error %s:%d: %s\n",                   \
                         __FILE__, __LINE__, cudaGetErrorString(err__));     \
            std::exit(EXIT_FAILURE);                                         \
        }                                                                    \
    } while (0)

struct Half4 {
    __half x, y, z, w;
};

static_assert(sizeof(Half4) == 8, "Half4 must be 8 bytes");

// ------------------------------------------------------------
// Codec profiles
// ------------------------------------------------------------

enum class HDRCodecProfile : uint32_t {
    HDR_4BPP_PREVIEW   = 4,
    HDR_8BPP_ENDPOINTS = 8,
    HDR_16BPP_QUALITY  = 16
};

[[maybe_unused]]
static const char* profile_name(HDRCodecProfile p)
{
    switch (p) {
        case HDRCodecProfile::HDR_4BPP_PREVIEW:   return "HDR_4BPP_PREVIEW";
        case HDRCodecProfile::HDR_8BPP_ENDPOINTS: return "HDR_8BPP_ENDPOINTS";
        case HDRCodecProfile::HDR_16BPP_QUALITY:  return "HDR_16BPP_QUALITY";
        default:                                  return "UNKNOWN";
    }
}

[[maybe_unused]]
static HDRCodecProfile parse_profile(int argc, char** argv)
{
    if (argc < 2) {
        return HDRCodecProfile::HDR_8BPP_ENDPOINTS;
    }

    int v = std::atoi(argv[1]);

    if (v == 4)  return HDRCodecProfile::HDR_4BPP_PREVIEW;
    if (v == 8)  return HDRCodecProfile::HDR_8BPP_ENDPOINTS;
    if (v == 16) return HDRCodecProfile::HDR_16BPP_QUALITY;

    std::fprintf(stderr, "Unknown profile '%s'. Use 4, 8, or 16.\n", argv[1]);
    std::exit(EXIT_FAILURE);
}

// ------------------------------------------------------------
// Block formats
// ------------------------------------------------------------

// 4 bpp:
//   2 bytes: max_luma as half
//   1 byte : average chroma r fraction
//   1 byte : average chroma g fraction
//   4 bytes: 16 x 2-bit luminance indices
//   total  : 8 bytes
struct alignas(8) HDRBlock4bpp {
    __half   max_luma;
    uint8_t  cr8;
    uint8_t  cg8;
    uint32_t indices;
};

static_assert(sizeof(HDRBlock4bpp) == 8, "HDRBlock4bpp must be 8 bytes");

// 8 bpp:
//   12 bytes: RGB endpoint 0 + RGB endpoint 1, half precision
//    4 bytes: 16 x 2-bit indices
//   total   : 16 bytes
struct alignas(16) HDRBlock8bpp {
    __half r0, g0, b0;
    __half r1, g1, b1;
    uint32_t indices;
};

static_assert(sizeof(HDRBlock8bpp) == 16, "HDRBlock8bpp must be 16 bytes");

// 16 bpp:
//   24 bytes: RGB endpoint 0 + RGB endpoint 1, float precision
//    8 bytes: 16 x 4-bit indices
//   total   : 32 bytes
struct alignas(32) HDRBlock16bpp {
    float r0, g0, b0;
    float r1, g1, b1;
    uint64_t indices;
};

static_assert(sizeof(HDRBlock16bpp) == 32, "HDRBlock16bpp must be 32 bytes");

// ------------------------------------------------------------
// Size helpers
// ------------------------------------------------------------

extern "C" {

int blocks_x_for(int width)
{
    return (width + 3) / 4;
}

int blocks_y_for(int height)
{
    return (height + 3) / 4;
}

int num_blocks_for(int width, int height)
{
    return blocks_x_for(width) * blocks_y_for(height);
}

size_t compressed_size_bytes(
    int width,
    int height,
    HDRCodecProfile profile)
{
    const int num_blocks = num_blocks_for(width, height);

    switch (profile) {
        case HDRCodecProfile::HDR_4BPP_PREVIEW:
            return size_t(num_blocks) * sizeof(HDRBlock4bpp);

        case HDRCodecProfile::HDR_8BPP_ENDPOINTS:
            return size_t(num_blocks) * sizeof(HDRBlock8bpp);

        case HDRCodecProfile::HDR_16BPP_QUALITY:
            return size_t(num_blocks) * sizeof(HDRBlock16bpp);

        default:
            return 0;
    }
}

[[maybe_unused]]
static double bits_per_pixel(
    int width,
    int height,
    HDRCodecProfile profile)
{
    const size_t compressed_bytes =
        compressed_size_bytes(width, height, profile);

    return 8.0 * double(compressed_bytes) / double(width * height);
}

[[maybe_unused]]
static double compression_ratio_vs_half4(
    int width,
    int height,
    HDRCodecProfile profile)
{
    const size_t raw_bytes =
        size_t(width) * size_t(height) * sizeof(Half4);

    const size_t compressed_bytes =
        compressed_size_bytes(width, height, profile);

    return double(raw_bytes) / double(compressed_bytes);
}

[[maybe_unused]]
static double stream_mbit_per_second(
    int width,
    int height,
    HDRCodecProfile profile,
    double fps)
{
    const size_t compressed_bytes =
        compressed_size_bytes(width, height, profile);

    return double(compressed_bytes) * 8.0 * fps / 1.0e6;
}

// ------------------------------------------------------------
// Math helpers
// ------------------------------------------------------------

static __host__ __device__ __forceinline__
float clamp01(float x)
{
    return fminf(fmaxf(x, 0.0f), 1.0f);
}

static __device__ __forceinline__
float3 half4_to_rgb(const Half4& h)
{
    return make_float3(
        __half2float(h.x),
        __half2float(h.y),
        __half2float(h.z)
    );
}

static __device__ __forceinline__
Half4 rgb_to_half4(float3 c, float alpha)
{
    Half4 h;
    h.x = __float2half_rn(c.x);
    h.y = __float2half_rn(c.y);
    h.z = __float2half_rn(c.z);
    h.w = __float2half_rn(alpha);
    return h;
}

static __device__ __forceinline__
float3 lerp3(float3 a, float3 b, float t)
{
    return make_float3(
        a.x + t * (b.x - a.x),
        a.y + t * (b.y - a.y),
        a.z + t * (b.z - a.z)
    );
}

static __device__ __forceinline__
float dot3(float3 a, float3 b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

static __device__ __forceinline__
float3 sub3(float3 a, float3 b)
{
    return make_float3(a.x - b.x, a.y - b.y, a.z - b.z);
}

static __device__ __forceinline__
float3 min3(float3 a, float3 b)
{
    return make_float3(
        fminf(a.x, b.x),
        fminf(a.y, b.y),
        fminf(a.z, b.z)
    );
}

static __device__ __forceinline__
float3 max3(float3 a, float3 b)
{
    return make_float3(
        fmaxf(a.x, b.x),
        fmaxf(a.y, b.y),
        fmaxf(a.z, b.z)
    );
}

static __device__ __forceinline__
float max_rgb(float3 c)
{
    return fmaxf(c.x, fmaxf(c.y, c.z));
}

// ------------------------------------------------------------
// 4 bpp preview codec
// ------------------------------------------------------------
//
// This is intentionally aggressive.
// It stores one block luminance range and one average chroma.
// It is useful only as a low-bandwidth preview codec.

__global__
void compress_half4_to_hdr4bpp_blocks(
    const Half4* __restrict__ src,
    HDRBlock4bpp* __restrict__ blocks,
    int width,
    int height)
{
    const int tx = threadIdx.x; // 0..15
    const int lx = tx & 3;
    const int ly = tx >> 2;

    const int block_x = blockIdx.x;
    const int block_y = blockIdx.y;

    const int x = block_x * 4 + lx;
    const int y = block_y * 4 + ly;

    const bool valid = (x < width && y < height);

    const int blocks_x = (width + 3) / 4;
    const int block_id = block_y * blocks_x + block_x;

    __shared__ float s_max_luma[16];
    __shared__ float s_cr_sum[16];
    __shared__ float s_cg_sum[16];
    __shared__ float s_count[16];

    float3 rgb = make_float3(0.0f, 0.0f, 0.0f);

    if (valid) {
        rgb = half4_to_rgb(src[y * width + x]);
        rgb.x = fmaxf(rgb.x, 0.0f);
        rgb.y = fmaxf(rgb.y, 0.0f);
        rgb.z = fmaxf(rgb.z, 0.0f);
    }

    const float lum = valid ? max_rgb(rgb) : 0.0f;
    const float sum_rgb = rgb.x + rgb.y + rgb.z;

    float cr = 1.0f / 3.0f;
    float cg = 1.0f / 3.0f;

    if (valid && sum_rgb > 1.0e-20f) {
        cr = rgb.x / sum_rgb;
        cg = rgb.y / sum_rgb;
    }

    s_max_luma[tx] = lum;
    s_cr_sum[tx] = valid ? cr : 0.0f;
    s_cg_sum[tx] = valid ? cg : 0.0f;
    s_count[tx] = valid ? 1.0f : 0.0f;

    __syncthreads();

    for (int stride = 8; stride > 0; stride >>= 1) {
        if (tx < stride) {
            s_max_luma[tx] = fmaxf(s_max_luma[tx], s_max_luma[tx + stride]);
            s_cr_sum[tx] += s_cr_sum[tx + stride];
            s_cg_sum[tx] += s_cg_sum[tx + stride];
            s_count[tx] += s_count[tx + stride];
        }
        __syncthreads();
    }

    const float max_luma = fmaxf(s_max_luma[0], 1.0e-20f);
    const float inv_max_luma = 1.0f / max_luma;

    const float count = fmaxf(s_count[0], 1.0f);
    const float avg_cr = clamp01(s_cr_sum[0] / count);
    const float avg_cg = clamp01(s_cg_sum[0] / count);

    uint32_t idx = 0;

    if (valid) {
        float t = clamp01(lum * inv_max_luma);
        idx = (uint32_t)(t * 3.0f + 0.5f);
        idx = min(idx, 3u);
    }

    __shared__ uint32_t s_bits[16];
    s_bits[tx] = idx << (2 * tx);

    __syncthreads();

    for (int stride = 8; stride > 0; stride >>= 1) {
        if (tx < stride) {
            s_bits[tx] |= s_bits[tx + stride];
        }
        __syncthreads();
    }

    if (tx == 0) {
        HDRBlock4bpp b;
        b.max_luma = __float2half_rn(max_luma);
        b.cr8 = (uint8_t)(clamp01(avg_cr) * 255.0f + 0.5f);
        b.cg8 = (uint8_t)(clamp01(avg_cg) * 255.0f + 0.5f);
        b.indices = s_bits[0];

        blocks[block_id] = b;
    }
}

__global__
void decompress_hdr4bpp_blocks_to_half4(
    const HDRBlock4bpp* __restrict__ blocks,
    Half4* __restrict__ dst,
    int width,
    int height)
{
    const int tx = threadIdx.x; // 0..15
    const int lx = tx & 3;
    const int ly = tx >> 2;

    const int block_x = blockIdx.x;
    const int block_y = blockIdx.y;

    const int x = block_x * 4 + lx;
    const int y = block_y * 4 + ly;

    if (x >= width || y >= height) {
        return;
    }

    const int blocks_x = (width + 3) / 4;
    const int block_id = block_y * blocks_x + block_x;

    const HDRBlock4bpp b = blocks[block_id];

    const float max_luma = __half2float(b.max_luma);
    const float cr = float(b.cr8) / 255.0f;
    const float cg = float(b.cg8) / 255.0f;
    const float cb = fmaxf(1.0f - cr - cg, 0.0f);

    float3 chroma = make_float3(cr, cg, cb);
    const float chroma_max = fmaxf(max_rgb(chroma), 1.0e-20f);

    const uint32_t idx = (b.indices >> (2 * tx)) & 3u;
    const float lum = (float(idx) / 3.0f) * max_luma;

    // Scale chroma so that max(R,G,B) == luminance.
    float3 rgb = make_float3(
        chroma.x * lum / chroma_max,
        chroma.y * lum / chroma_max,
        chroma.z * lum / chroma_max
    );

    dst[y * width + x] = rgb_to_half4(rgb, 1.0f);
}

// ------------------------------------------------------------
// 8 bpp endpoint codec
// ------------------------------------------------------------

__global__
void compress_half4_to_hdr8bpp_blocks(
    const Half4* __restrict__ src,
    HDRBlock8bpp* __restrict__ blocks,
    int width,
    int height)
{
    const int tx = threadIdx.x; // 0..15
    const int lx = tx & 3;
    const int ly = tx >> 2;

    const int block_x = blockIdx.x;
    const int block_y = blockIdx.y;

    const int x = block_x * 4 + lx;
    const int y = block_y * 4 + ly;

    const bool valid = (x < width && y < height);

    const int blocks_x = (width + 3) / 4;
    const int block_id = block_y * blocks_x + block_x;

    __shared__ float3 s_min[16];
    __shared__ float3 s_max[16];

    float3 rgb = make_float3(0.0f, 0.0f, 0.0f);

    if (valid) {
        rgb = half4_to_rgb(src[y * width + x]);

        rgb.x = fmaxf(rgb.x, 0.0f);
        rgb.y = fmaxf(rgb.y, 0.0f);
        rgb.z = fmaxf(rgb.z, 0.0f);
    }

    if (valid) {
        s_min[tx] = rgb;
        s_max[tx] = rgb;
    }
    else {
        s_min[tx] = make_float3(1.0e30f, 1.0e30f, 1.0e30f);
        s_max[tx] = make_float3(0.0f, 0.0f, 0.0f);
    }

    __syncthreads();

    for (int stride = 8; stride > 0; stride >>= 1) {
        if (tx < stride) {
            s_min[tx] = min3(s_min[tx], s_min[tx + stride]);
            s_max[tx] = max3(s_max[tx], s_max[tx + stride]);
        }
        __syncthreads();
    }

    float3 c0 = s_min[0];
    float3 c1 = s_max[0];

    if (c0.x > 1.0e20f) {
        c0 = make_float3(0.0f, 0.0f, 0.0f);
        c1 = make_float3(0.0f, 0.0f, 0.0f);
    }

    float3 axis = sub3(c1, c0);
    float axis_len2 = dot3(axis, axis);

    uint32_t local_bits = 0;

    if (valid && axis_len2 > 1.0e-20f) {
        float t = dot3(sub3(rgb, c0), axis) / axis_len2;
        t = clamp01(t);

        uint32_t idx = (uint32_t)(t * 3.0f + 0.5f);
        idx = min(idx, 3u);

        local_bits = idx << (2 * tx);
    }

    __shared__ uint32_t s_bits[16];
    s_bits[tx] = local_bits;

    __syncthreads();

    for (int stride = 8; stride > 0; stride >>= 1) {
        if (tx < stride) {
            s_bits[tx] |= s_bits[tx + stride];
        }
        __syncthreads();
    }

    if (tx == 0) {
        HDRBlock8bpp b;

        b.r0 = __float2half_rn(c0.x);
        b.g0 = __float2half_rn(c0.y);
        b.b0 = __float2half_rn(c0.z);

        b.r1 = __float2half_rn(c1.x);
        b.g1 = __float2half_rn(c1.y);
        b.b1 = __float2half_rn(c1.z);

        b.indices = s_bits[0];

        blocks[block_id] = b;
    }
}

__global__
void decompress_hdr8bpp_blocks_to_half4(
    const HDRBlock8bpp* __restrict__ blocks,
    Half4* __restrict__ dst,
    int width,
    int height)
{
    const int tx = threadIdx.x; // 0..15
    const int lx = tx & 3;
    const int ly = tx >> 2;

    const int block_x = blockIdx.x;
    const int block_y = blockIdx.y;

    const int x = block_x * 4 + lx;
    const int y = block_y * 4 + ly;

    if (x >= width || y >= height) {
        return;
    }

    const int blocks_x = (width + 3) / 4;
    const int block_id = block_y * blocks_x + block_x;

    HDRBlock8bpp b = blocks[block_id];

    float3 c0 = make_float3(
        __half2float(b.r0),
        __half2float(b.g0),
        __half2float(b.b0)
    );

    float3 c1 = make_float3(
        __half2float(b.r1),
        __half2float(b.g1),
        __half2float(b.b1)
    );

    uint32_t idx = (b.indices >> (2 * tx)) & 3u;
    float t = float(idx) / 3.0f;

    float3 rgb = lerp3(c0, c1, t);

    dst[y * width + x] = rgb_to_half4(rgb, 1.0f);
}

// ------------------------------------------------------------
// 16 bpp quality codec
// ------------------------------------------------------------

__global__
void compress_half4_to_hdr16bpp_blocks(
    const Half4* __restrict__ src,
    HDRBlock16bpp* __restrict__ blocks,
    int width,
    int height)
{
    const int tx = threadIdx.x; // 0..15
    const int lx = tx & 3;
    const int ly = tx >> 2;

    const int block_x = blockIdx.x;
    const int block_y = blockIdx.y;

    const int x = block_x * 4 + lx;
    const int y = block_y * 4 + ly;

    const bool valid = (x < width && y < height);

    const int blocks_x = (width + 3) / 4;
    const int block_id = block_y * blocks_x + block_x;

    __shared__ float3 s_min[16];
    __shared__ float3 s_max[16];

    float3 rgb = make_float3(0.0f, 0.0f, 0.0f);

    if (valid) {
        rgb = half4_to_rgb(src[y * width + x]);

        rgb.x = fmaxf(rgb.x, 0.0f);
        rgb.y = fmaxf(rgb.y, 0.0f);
        rgb.z = fmaxf(rgb.z, 0.0f);

        s_min[tx] = rgb;
        s_max[tx] = rgb;
    }
    else {
        s_min[tx] = make_float3(1.0e30f, 1.0e30f, 1.0e30f);
        s_max[tx] = make_float3(0.0f, 0.0f, 0.0f);
    }

    __syncthreads();

    for (int stride = 8; stride > 0; stride >>= 1) {
        if (tx < stride) {
            s_min[tx] = min3(s_min[tx], s_min[tx + stride]);
            s_max[tx] = max3(s_max[tx], s_max[tx + stride]);
        }
        __syncthreads();
    }

    float3 c0 = s_min[0];
    float3 c1 = s_max[0];

    if (c0.x > 1.0e20f) {
        c0 = make_float3(0.0f, 0.0f, 0.0f);
        c1 = make_float3(0.0f, 0.0f, 0.0f);
    }

    float3 axis = sub3(c1, c0);
    float axis_len2 = dot3(axis, axis);

    uint64_t local_bits = 0ull;

    if (valid && axis_len2 > 1.0e-20f) {
        float t = dot3(sub3(rgb, c0), axis) / axis_len2;
        t = clamp01(t);

        uint64_t idx = (uint64_t)(t * 15.0f + 0.5f);
        idx = min(idx, (uint64_t)15);

        local_bits = idx << (4 * tx);
    }

    __shared__ uint64_t s_bits[16];
    s_bits[tx] = local_bits;

    __syncthreads();

    for (int stride = 8; stride > 0; stride >>= 1) {
        if (tx < stride) {
            s_bits[tx] |= s_bits[tx + stride];
        }
        __syncthreads();
    }

    if (tx == 0) {
        HDRBlock16bpp b;

        b.r0 = c0.x;
        b.g0 = c0.y;
        b.b0 = c0.z;

        b.r1 = c1.x;
        b.g1 = c1.y;
        b.b1 = c1.z;

        b.indices = s_bits[0];

        blocks[block_id] = b;
    }
}

__global__
void decompress_hdr16bpp_blocks_to_half4(
    const HDRBlock16bpp* __restrict__ blocks,
    Half4* __restrict__ dst,
    int width,
    int height)
{
    const int tx = threadIdx.x; // 0..15
    const int lx = tx & 3;
    const int ly = tx >> 2;

    const int block_x = blockIdx.x;
    const int block_y = blockIdx.y;

    const int x = block_x * 4 + lx;
    const int y = block_y * 4 + ly;

    if (x >= width || y >= height) {
        return;
    }

    const int blocks_x = (width + 3) / 4;
    const int block_id = block_y * blocks_x + block_x;

    HDRBlock16bpp b = blocks[block_id];

    float3 c0 = make_float3(b.r0, b.g0, b.b0);
    float3 c1 = make_float3(b.r1, b.g1, b.b1);

    uint64_t idx = (b.indices >> (4 * tx)) & 15ull;
    float t = float(idx) / 15.0f;

    float3 rgb = lerp3(c0, c1, t);

    dst[y * width + x] = rgb_to_half4(rgb, 1.0f);
}

// ------------------------------------------------------------
// Profile dispatch
// ------------------------------------------------------------

void compress_frame_cuda(
    const Half4* d_src,
    void* d_blocks,
    int width,
    int height,
    HDRCodecProfile profile)
{
	cudaStream_t stream = 0; // default stream
    dim3 block(16);
    dim3 grid((width + 3) / 4, (height + 3) / 4);

    switch (profile) {
        case HDRCodecProfile::HDR_4BPP_PREVIEW:
            compress_half4_to_hdr4bpp_blocks<<<grid, block, 0, stream>>>(
                d_src,
                reinterpret_cast<HDRBlock4bpp*>(d_blocks),
                width,
                height
            );
            break;

        case HDRCodecProfile::HDR_8BPP_ENDPOINTS:
            compress_half4_to_hdr8bpp_blocks<<<grid, block, 0, stream>>>(
                d_src,
                reinterpret_cast<HDRBlock8bpp*>(d_blocks),
                width,
                height
            );
            break;

        case HDRCodecProfile::HDR_16BPP_QUALITY:
            compress_half4_to_hdr16bpp_blocks<<<grid, block, 0, stream>>>(
                d_src,
                reinterpret_cast<HDRBlock16bpp*>(d_blocks),
                width,
                height
            );
            break;
    }
}

void decompress_frame_cuda(
    const void* d_blocks,
    Half4* d_dst,
    int width,
    int height,
    HDRCodecProfile profile)
{
    cudaStream_t stream = 0; // default stream
    dim3 block(16);
    dim3 grid((width + 3) / 4, (height + 3) / 4);

    switch (profile) {
        case HDRCodecProfile::HDR_4BPP_PREVIEW:
            decompress_hdr4bpp_blocks_to_half4<<<grid, block, 0, stream>>>(
                reinterpret_cast<const HDRBlock4bpp*>(d_blocks),
                d_dst,
                width,
                height
            );
            break;

        case HDRCodecProfile::HDR_8BPP_ENDPOINTS:
            decompress_hdr8bpp_blocks_to_half4<<<grid, block, 0, stream>>>(
                reinterpret_cast<const HDRBlock8bpp*>(d_blocks),
                d_dst,
                width,
                height
            );
            break;

        case HDRCodecProfile::HDR_16BPP_QUALITY:
            decompress_hdr16bpp_blocks_to_half4<<<grid, block, 0, stream>>>(
                reinterpret_cast<const HDRBlock16bpp*>(d_blocks),
                d_dst,
                width,
                height
            );
            break;
    }
}

} // extern "C"

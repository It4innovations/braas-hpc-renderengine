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

// LHC - Linear Half Codec
//
// GPU (CUDA) codec for scene-linear RGBA half-float frames (half4). Designed for interactive
// streaming of path-traced images where the client applies the view transform itself, so the
// full HDR range has to survive the transfer.
//
//   1. Quantization on the half bit pattern: the 15 magnitude bits of a half are monotonic and
//      logarithmic, so rounding away (10 - mantissa_bits) low bits gives a *relative* error
//      bound of 2^-(mantissa_bits+1) for normal numbers. mantissa_bits = 10 is lossless
//      (except NaN -> 0, Inf -> 65504, -0 -> +0).
//   2. Color decorrelation G, R-G, B-G (in the log-like domain this is a ratio).
//   3. Tiles of 32x32 pixels, one warp per tile. For every row and channel the encoder picks
//      the best of 5 predictors (up, left, planar L+U-UL, smoothed up, temporal) - all of them
//      are decodable in parallel (left/planar via warp prefix sum).
//   4. Residuals are zig-zag mapped and bit-plane packed with __ballot_sync: a group of 32
//      values with bit width w costs exactly w 32-bit words + 1 header byte.
//   5. Temporal prediction: encoder and decoder both keep the previous reconstructed frame on
//      the GPU. While the renderer accumulates samples the frame changes by ~noise/N, so the
//      residuals shrink towards zero as the image converges. The first frame, a resize or
//      reset() produce a key frame (spatial prediction only). TCP keeps both sides in sync.
//
// Stream layout (little endian 32-bit words):
//   LhcHeader (12 words)
//   tile_offsets[num_tiles]       (in words, relative to the payload start)
//   payload[payload_words]
// If the compressed stream would be bigger than the raw frame, the encoder stores the frame raw
// (LHC_FLAG_RAW) and the payload is the plain half4 image (also a valid reference).

#ifndef __HALF_CODEC_H__
#define __HALF_CODEC_H__

#include <cstddef>
#include <cstdint>

#define LHC_MAGIC 0x3143484Cu  // "LHC1"
#define LHC_FLAG_RAW 1u
#define LHC_FLAG_KEYFRAME 2u

#define LHC_TILE 32
#define LHC_MAX_WIDTH 19  // max bit width of a zig-zag residual (see half_codec.cu)
#define LHC_TILE_MAX_WORDS (LHC_TILE + LHC_TILE * 4 * LHC_MAX_WIDTH)

#define LHC_MANTISSA_BITS_LOSSLESS 10
#define LHC_MANTISSA_BITS_DEFAULT 10

struct LhcHeader {
	uint32_t magic;
	uint32_t width;
	uint32_t height;
	uint32_t mantissa_bits;
	uint32_t tiles_x;
	uint32_t tiles_y;
	uint32_t payload_words;
	uint32_t flags;
	uint32_t sequence;  // frame counter since the last key frame
	uint32_t reserved[3];
};

class HalfCodec {
public:
	HalfCodec();
	~HalfCodec();

	// Compresses a half4 RGBA image (device or host pointer).
	// mantissa_bits: 1..10, 10 = lossless.
	// On success *out points to a pinned host buffer owned by the codec (valid until the next
	// encode call) and *out_size is the stream size in bytes. Returns 0 on success.
	int encode(const void* rgba_half, int width, int height, int mantissa_bits,
		const uint8_t** out, size_t* out_size);

	// Decompresses a stream (host memory) into a half4 RGBA image (device or host pointer).
	// Returns 0 on success.
	int decode(const uint8_t* stream, size_t size, void* rgba_half_out, int width, int height);

	// Upper bound of the stream size (raw fallback included).
	static size_t max_stream_size(int width, int height);

	// Forget the temporal reference: the next encoded frame is a key frame and the decoder
	// accepts only a key frame next. Call on (re)connection.
	void reset();

	// Enable/disable temporal prediction in the encoder (default on).
	void set_temporal(bool enabled) { m_temporal = enabled; }

	// Timing of the last call in milliseconds (GPU part only, measured with events).
	float last_gpu_ms() const { return m_last_gpu_ms; }

private:
	void release();
	bool ensure_stream();
	bool ensure(void** ptr, size_t* cap, size_t size, bool host);

	void* m_stream = nullptr;  // cudaStream_t
	void* m_ev0 = nullptr;     // cudaEvent_t
	void* m_ev1 = nullptr;

	void* m_d_src = nullptr;     size_t m_d_src_cap = 0;      // input staging (host input)
	void* m_d_scratch = nullptr; size_t m_d_scratch_cap = 0;  // per tile worst case
	void* m_d_sizes = nullptr;   size_t m_d_sizes_cap = 0;
	void* m_d_stream = nullptr;  size_t m_d_stream_cap = 0;   // compacted stream
	void* m_d_temp = nullptr;    size_t m_d_temp_cap = 0;     // cub temp storage
	void* m_d_ref = nullptr;     size_t m_d_ref_cap = 0;      // previous reconstructed frame (half4)
	void* m_h_stream = nullptr;  size_t m_h_stream_cap = 0;   // pinned host stream

	bool m_temporal = true;
	bool m_ref_valid = false;
	int m_ref_width = 0;
	int m_ref_height = 0;
	uint32_t m_sequence = 0;

	float m_last_gpu_ms = 0.0f;
};

#endif

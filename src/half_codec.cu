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

#include "half_codec.h"

#include <cuda_runtime.h>
#include <cub/device/device_scan.cuh>

#include <cstdio>
#include <cstring>

#define LHC_FULL_MASK 0xffffffffu
#define LHC_WARPS_PER_BLOCK 4

#define LHC_CHECK(stmt) \
	do { \
		cudaError_t err__ = (stmt); \
		if (err__ != cudaSuccess) { \
			fprintf(stderr, "HalfCodec CUDA error: %s in %s (%s:%d)\n", cudaGetErrorString(err__), #stmt, __FILE__, __LINE__); \
			return 1; \
		} \
	} while (0)

// Residual bound: transformed channel values are within +-2*0x7BFF, the planar predictor within
// +-3*(2*0x7BFF), so |residual| <= 4*2*0x7BFF = 253944 and the zig-zag value < 2^19.
static_assert(LHC_MAX_WIDTH >= 19, "LHC_MAX_WIDTH too small");

//////////////////////////////////////////////////////////////////////////////////////////////////
// device helpers

__device__ __forceinline__ int lhc_quant(unsigned int h, int shift)
{
	int mag = (int)(h & 0x7fffu);
	if (mag > 0x7c00) mag = 0;            // NaN -> 0
	else if (mag == 0x7c00) mag = 0x7bff; // Inf -> 65504
	const int k = (mag + ((1 << shift) >> 1)) >> shift;
	return (h & 0x8000u) ? -k : k;
}

__device__ __forceinline__ unsigned short lhc_dequant(int k, int shift)
{
	const bool neg = k < 0;
	int mag = (neg ? -k : k) << shift;
	if (mag > 0x7bff) mag = 0x7bff;
	return (unsigned short)((neg ? 0x8000 : 0) | mag);
}

__device__ __forceinline__ unsigned int lhc_zz(int v)
{
	return (unsigned int)((v << 1) ^ (v >> 31));
}

__device__ __forceinline__ int lhc_unzz(unsigned int z)
{
	return (int)(z >> 1) ^ -(int)(z & 1u);
}

__device__ __forceinline__ unsigned int lhc_warp_or(unsigned int v)
{
#pragma unroll
	for (int o = 16; o > 0; o >>= 1)
		v |= __shfl_xor_sync(LHC_FULL_MASK, v, o);
	return v;
}

__device__ __forceinline__ int lhc_bit_width(unsigned int m)
{
	return m ? 32 - __clz((int)m) : 0;
}

//////////////////////////////////////////////////////////////////////////////////////////////////
// encoder: one warp per 32x32 tile, writes into a fixed size slot of the scratch buffer

__device__ __forceinline__ void lhc_transform(const ushort4 p, int shift, int t[4])
{
	const int qr = lhc_quant(p.x, shift);
	const int qg = lhc_quant(p.y, shift);
	const int qb = lhc_quant(p.z, shift);
	t[0] = qg;
	t[1] = qr - qg;
	t[2] = qb - qg;
	t[3] = lhc_quant(p.w, shift);
}

__device__ __forceinline__ ushort4 lhc_inverse(const int t[4], int shift)
{
	const int qg = t[0];
	ushort4 p;
	p.x = lhc_dequant(t[1] + qg, shift);
	p.y = lhc_dequant(qg, shift);
	p.z = lhc_dequant(t[2] + qg, shift);
	p.w = lhc_dequant(t[3], shift);
	return p;
}

// ref: previous reconstructed frame, read for temporal prediction (if temporal != 0) and
// overwritten in place with the reconstruction of the current frame (same pixel, same lane).
__global__ void lhc_encode_kernel(const ushort4* __restrict__ src, ushort4* __restrict__ ref, int temporal,
	int width, int height, int shift, int tiles_x, int num_tiles,
	unsigned int* __restrict__ scratch, unsigned int* __restrict__ sizes)
{
	const int tile = (int)((blockIdx.x * blockDim.x + threadIdx.x) >> 5);
	const int lane = (int)(threadIdx.x & 31);
	if (tile >= num_tiles)
		return;  // uniform for the whole warp

	const int x = (tile % tiles_x) * LHC_TILE + lane;
	const int y0 = (tile / tiles_x) * LHC_TILE;
	const bool vx = x < width;
	const bool vxr = (x + 1) < width;
	const int rows = min(LHC_TILE, height - y0);

	unsigned int* out = scratch + (size_t)tile * LHC_TILE_MAX_WORDS;
	int pos = LHC_TILE;  // first 32 words: per row 4 header bytes

	int prev[4] = { 0, 0, 0, 0 };

	for (int r = 0; r < LHC_TILE; r++) {
		if (r >= rows) {
			if (lane == 0)
				out[r] = 0;
			continue;
		}

		const size_t idx = (size_t)(y0 + r) * width + x;
		int t[4] = { 0, 0, 0, 0 };
		int tr[4] = { 0, 0, 0, 0 };
		if (vx) {
			lhc_transform(src[idx], shift, t);
			if (temporal)
				lhc_transform(ref[idx], shift, tr);
		}

		unsigned int hdr = 0;

#pragma unroll
		for (int c = 0; c < 4; c++) {
			const int v = t[c];
			const int up = prev[c];
			int L = __shfl_up_sync(LHC_FULL_MASK, v, 1);
			int UL = __shfl_up_sync(LHC_FULL_MASK, up, 1);
			int UR = __shfl_down_sync(LHC_FULL_MASK, up, 1);
			if (lane == 0) {
				L = up;
				UL = up;
			}
			if (!vxr)
				UR = up;

			const unsigned int z0 = vx ? lhc_zz(v - up) : 0u;
			const unsigned int z1 = vx ? lhc_zz(v - L) : 0u;
			const unsigned int z2 = vx ? lhc_zz(v - (L + up - UL)) : 0u;
			const unsigned int z3 = vx ? lhc_zz(v - ((UL + 2 * up + UR + 2) >> 2)) : 0u;

			const int w0 = lhc_bit_width(lhc_warp_or(z0));
			const int w1 = lhc_bit_width(lhc_warp_or(z1));
			const int w2 = lhc_bit_width(lhc_warp_or(z2));
			const int w3 = lhc_bit_width(lhc_warp_or(z3));

			int k = 0, w = w0;
			unsigned int z = z0;
			if (w1 < w) { k = 1; w = w1; z = z1; }
			if (w2 < w) { k = 2; w = w2; z = z2; }
			if (w3 < w) { k = 3; w = w3; z = z3; }
			if (temporal) {
				const unsigned int z4 = vx ? lhc_zz(v - tr[c]) : 0u;
				const int w4 = lhc_bit_width(lhc_warp_or(z4));
				if (w4 < w) { k = 4; w = w4; z = z4; }
			}

			hdr |= (unsigned int)((k << 5) | w) << (8 * c);

			unsigned int my_word = 0;
			for (int j = 0; j < w; j++) {
				const unsigned int b = __ballot_sync(LHC_FULL_MASK, (z >> j) & 1u);
				if (lane == j)
					my_word = b;
			}
			if (lane < w)
				out[pos + lane] = my_word;
			pos += w;
		}

		if (lane == 0)
			out[r] = hdr;

		if (vx)
			ref[idx] = lhc_inverse(t, shift);

#pragma unroll
		for (int c = 0; c < 4; c++)
			prev[c] = t[c];
	}

	if (lane == 0)
		sizes[tile] = (unsigned int)pos;
}

// header + total payload size (offsets were produced by the exclusive scan)
__global__ void lhc_finalize_kernel(unsigned int* __restrict__ stream, const unsigned int* __restrict__ sizes,
	int width, int height, int mantissa_bits, int tiles_x, int tiles_y, unsigned int flags, unsigned int sequence)
{
	const int num_tiles = tiles_x * tiles_y;
	const unsigned int* offsets = stream + sizeof(LhcHeader) / 4;
	LhcHeader* h = (LhcHeader*)stream;
	h->magic = LHC_MAGIC;
	h->width = width;
	h->height = height;
	h->mantissa_bits = mantissa_bits;
	h->tiles_x = tiles_x;
	h->tiles_y = tiles_y;
	h->payload_words = offsets[num_tiles - 1] + sizes[num_tiles - 1];
	h->flags = flags;
	h->sequence = sequence;
	h->reserved[0] = h->reserved[1] = h->reserved[2] = 0;
}

__global__ void lhc_compact_kernel(const unsigned int* __restrict__ scratch, const unsigned int* __restrict__ sizes,
	unsigned int* __restrict__ stream, int num_tiles)
{
	const int tile = blockIdx.x;
	const unsigned int* offsets = stream + sizeof(LhcHeader) / 4;
	unsigned int* payload = stream + sizeof(LhcHeader) / 4 + num_tiles;

	const unsigned int n = sizes[tile];
	const unsigned int* s = scratch + (size_t)tile * LHC_TILE_MAX_WORDS;
	unsigned int* d = payload + offsets[tile];
	for (unsigned int i = threadIdx.x; i < n; i += blockDim.x)
		d[i] = s[i];
}

//////////////////////////////////////////////////////////////////////////////////////////////////
// decoder

// ref: previous reconstructed frame (temporal prediction), overwritten in place with the result
__global__ void lhc_decode_kernel(const unsigned int* __restrict__ offsets, const unsigned int* __restrict__ payload,
	int width, int height, int shift, int tiles_x, int num_tiles, int temporal, ushort4* __restrict__ ref)
{
	const int tile = (int)((blockIdx.x * blockDim.x + threadIdx.x) >> 5);
	const int lane = (int)(threadIdx.x & 31);
	if (tile >= num_tiles)
		return;

	const int x = (tile % tiles_x) * LHC_TILE + lane;
	const int y0 = (tile / tiles_x) * LHC_TILE;
	const bool vx = x < width;
	const bool vxr = (x + 1) < width;
	const int rows = min(LHC_TILE, height - y0);

	const unsigned int* in = payload + offsets[tile];
	int pos = LHC_TILE;

	int prev[4] = { 0, 0, 0, 0 };

	for (int r = 0; r < rows; r++) {
		const unsigned int hdr = in[r];
		const size_t idx = (size_t)(y0 + r) * width + x;
		int t[4];
		int tr[4] = { 0, 0, 0, 0 };
		if (temporal && vx)
			lhc_transform(ref[idx], shift, tr);

#pragma unroll
		for (int c = 0; c < 4; c++) {
			const unsigned int b = (hdr >> (8 * c)) & 0xffu;
			const int k = (int)(b >> 5);
			const int w = (int)(b & 31u);

			const unsigned int wd = (lane < w) ? in[pos + lane] : 0u;
			unsigned int z = 0;
			for (int j = 0; j < w; j++) {
				const unsigned int word = __shfl_sync(LHC_FULL_MASK, wd, j);
				z |= ((word >> lane) & 1u) << j;
			}
			pos += w;

			const int res = lhc_unzz(z);
			const int up = prev[c];
			int UL = __shfl_up_sync(LHC_FULL_MASK, up, 1);
			int UR = __shfl_down_sync(LHC_FULL_MASK, up, 1);
			if (lane == 0)
				UL = up;
			if (!vxr)
				UR = up;

			int v;
			if (k == 0) {
				v = res + up;
			}
			else if (k == 3) {
				v = res + ((UL + 2 * up + UR + 2) >> 2);
			}
			else if (k == 4) {
				v = res + tr[c];
			}
			else {
				// left / planar predictor: v[i] = v[i-1] + d[i] -> inclusive prefix sum
				int d = (k == 1) ? res : res + up - UL;
				if (lane == 0)
					d = res + up;
#pragma unroll
				for (int o = 1; o < 32; o <<= 1) {
					const int n = __shfl_up_sync(LHC_FULL_MASK, d, o);
					if (lane >= o)
						d += n;
				}
				v = d;
			}
			t[c] = vx ? v : 0;
		}

		if (vx)
			ref[idx] = lhc_inverse(t, shift);

#pragma unroll
		for (int c = 0; c < 4; c++)
			prev[c] = t[c];
	}
}

//////////////////////////////////////////////////////////////////////////////////////////////////
// host side

static bool lhc_is_device_ptr(const void* ptr)
{
	cudaPointerAttributes attr;
	if (cudaPointerGetAttributes(&attr, ptr) != cudaSuccess) {
		cudaGetLastError();  // clear the error state
		return false;
	}
	return attr.type == cudaMemoryTypeDevice || attr.type == cudaMemoryTypeManaged;
}

HalfCodec::HalfCodec() {}

HalfCodec::~HalfCodec()
{
	release();
}

void HalfCodec::release()
{
	void** dev[] = { &m_d_src, &m_d_scratch, &m_d_sizes, &m_d_stream, &m_d_temp, &m_d_ref };
	for (void** p : dev) {
		if (*p)
			cudaFree(*p);
		*p = nullptr;
	}
	if (m_h_stream)
		cudaFreeHost(m_h_stream);
	m_h_stream = nullptr;
	m_d_src_cap = m_d_scratch_cap = m_d_sizes_cap = m_d_stream_cap = m_d_temp_cap = m_d_ref_cap = m_h_stream_cap = 0;

	if (m_ev0) cudaEventDestroy((cudaEvent_t)m_ev0);
	if (m_ev1) cudaEventDestroy((cudaEvent_t)m_ev1);
	if (m_stream) cudaStreamDestroy((cudaStream_t)m_stream);
	m_ev0 = m_ev1 = m_stream = nullptr;

	reset();
}

void HalfCodec::reset()
{
	m_ref_valid = false;
	m_ref_width = 0;
	m_ref_height = 0;
	m_sequence = 0;
}

bool HalfCodec::ensure(void** ptr, size_t* cap, size_t size, bool host)
{
	if (*ptr && *cap >= size)
		return true;
	if (*ptr) {
		if (host) cudaFreeHost(*ptr);
		else cudaFree(*ptr);
		*ptr = nullptr;
		*cap = 0;
	}
	// grow with some headroom to avoid reallocations on small resizes
	size_t alloc = size + size / 8 + 4096;
	cudaError_t err = host ? cudaHostAlloc(ptr, alloc, cudaHostAllocDefault) : cudaMalloc(ptr, alloc);
	if (err != cudaSuccess) {
		fprintf(stderr, "HalfCodec: allocation of %zu bytes failed: %s\n", alloc, cudaGetErrorString(err));
		*ptr = nullptr;
		return false;
	}
	*cap = alloc;
	return true;
}

size_t HalfCodec::max_stream_size(int width, int height)
{
	const size_t raw = (size_t)width * height * 8;
	return sizeof(LhcHeader) + raw;
}

bool HalfCodec::ensure_stream()
{
	if (m_stream)
		return true;
	if (cudaStreamCreateWithFlags((cudaStream_t*)&m_stream, cudaStreamNonBlocking) != cudaSuccess ||
		cudaEventCreate((cudaEvent_t*)&m_ev0) != cudaSuccess ||
		cudaEventCreate((cudaEvent_t*)&m_ev1) != cudaSuccess) {
		fprintf(stderr, "HalfCodec: cannot create CUDA stream/events\n");
		return false;
	}
	return true;
}

int HalfCodec::encode(const void* rgba_half, int width, int height, int mantissa_bits,
	const uint8_t** out, size_t* out_size)
{
	if (width <= 0 || height <= 0 || rgba_half == nullptr)
		return 1;

	if (mantissa_bits < 1) mantissa_bits = 1;
	if (mantissa_bits > LHC_MANTISSA_BITS_LOSSLESS) mantissa_bits = LHC_MANTISSA_BITS_LOSSLESS;
	const int shift = LHC_MANTISSA_BITS_LOSSLESS - mantissa_bits;

	if (!ensure_stream())
		return 1;
	cudaStream_t stream = (cudaStream_t)m_stream;

	const int tiles_x = (width + LHC_TILE - 1) / LHC_TILE;
	const int tiles_y = (height + LHC_TILE - 1) / LHC_TILE;
	const int num_tiles = tiles_x * tiles_y;
	const size_t raw_bytes = (size_t)width * height * 8;
	const size_t header_words = sizeof(LhcHeader) / 4;
	const size_t stream_max_words = header_words + num_tiles + (size_t)num_tiles * LHC_TILE_MAX_WORDS;

	if (!ensure(&m_d_scratch, &m_d_scratch_cap, (size_t)num_tiles * LHC_TILE_MAX_WORDS * 4, false) ||
		!ensure(&m_d_sizes, &m_d_sizes_cap, (size_t)num_tiles * 4, false) ||
		!ensure(&m_d_stream, &m_d_stream_cap, stream_max_words * 4, false) ||
		!ensure(&m_d_ref, &m_d_ref_cap, raw_bytes, false) ||
		!ensure(&m_h_stream, &m_h_stream_cap, max_stream_size(width, height), true))
		return 1;

	size_t temp_bytes = 0;
	cub::DeviceScan::ExclusiveSum(nullptr, temp_bytes, (unsigned int*)m_d_sizes, (unsigned int*)m_d_stream, num_tiles, stream);
	if (!ensure(&m_d_temp, &m_d_temp_cap, temp_bytes, false))
		return 1;

	const bool keyframe = !m_temporal || !m_ref_valid || m_ref_width != width || m_ref_height != height;
	const uint32_t sequence = keyframe ? 0 : m_sequence + 1;
	m_ref_valid = false;  // valid again only if this frame is encoded successfully

	const bool src_on_device = lhc_is_device_ptr(rgba_half);
	const ushort4* d_src = (const ushort4*)rgba_half;

	if (src_on_device) {
		// the producer may have used another stream (e.g. the legacy default stream)
		LHC_CHECK(cudaDeviceSynchronize());
	}

	LHC_CHECK(cudaEventRecord((cudaEvent_t)m_ev0, stream));

	if (!src_on_device) {
		if (!ensure(&m_d_src, &m_d_src_cap, raw_bytes, false))
			return 1;
		LHC_CHECK(cudaMemcpyAsync(m_d_src, rgba_half, raw_bytes, cudaMemcpyHostToDevice, stream));
		d_src = (const ushort4*)m_d_src;
	}

	unsigned int* d_stream = (unsigned int*)m_d_stream;
	unsigned int* d_offsets = d_stream + header_words;

	const int threads = 32 * LHC_WARPS_PER_BLOCK;
	const int blocks = (num_tiles + LHC_WARPS_PER_BLOCK - 1) / LHC_WARPS_PER_BLOCK;
	lhc_encode_kernel<<<blocks, threads, 0, stream>>>(d_src, (ushort4*)m_d_ref, keyframe ? 0 : 1,
		width, height, shift, tiles_x, num_tiles, (unsigned int*)m_d_scratch, (unsigned int*)m_d_sizes);
	LHC_CHECK(cudaGetLastError());

	LHC_CHECK(cub::DeviceScan::ExclusiveSum(m_d_temp, temp_bytes, (unsigned int*)m_d_sizes, d_offsets, num_tiles, stream));

	const uint32_t flags = keyframe ? LHC_FLAG_KEYFRAME : 0u;
	lhc_finalize_kernel<<<1, 1, 0, stream>>>(d_stream, (unsigned int*)m_d_sizes, width, height, mantissa_bits,
		tiles_x, tiles_y, flags, sequence);
	LHC_CHECK(cudaGetLastError());

	lhc_compact_kernel<<<num_tiles, 128, 0, stream>>>((unsigned int*)m_d_scratch, (unsigned int*)m_d_sizes, d_stream, num_tiles);
	LHC_CHECK(cudaGetLastError());

	LhcHeader* h_header = (LhcHeader*)m_h_stream;
	LHC_CHECK(cudaMemcpyAsync(h_header, d_stream, sizeof(LhcHeader), cudaMemcpyDeviceToHost, stream));
	LHC_CHECK(cudaStreamSynchronize(stream));

	const size_t total = sizeof(LhcHeader) + (size_t)num_tiles * 4 + (size_t)h_header->payload_words * 4;

	if (total < raw_bytes + sizeof(LhcHeader)) {
		LHC_CHECK(cudaMemcpyAsync((uint8_t*)m_h_stream + sizeof(LhcHeader), d_stream + header_words,
			total - sizeof(LhcHeader), cudaMemcpyDeviceToHost, stream));
		*out_size = total;
	}
	else {
		// incompressible (e.g. pure noise in lossless mode): store raw, the raw frame becomes
		// the new reference on both sides
		h_header->flags = flags | LHC_FLAG_RAW;
		h_header->payload_words = (uint32_t)(raw_bytes / 4);
		LHC_CHECK(cudaMemcpyAsync(m_d_ref, d_src, raw_bytes, cudaMemcpyDeviceToDevice, stream));
		if (src_on_device)
			LHC_CHECK(cudaMemcpyAsync((uint8_t*)m_h_stream + sizeof(LhcHeader), rgba_half, raw_bytes, cudaMemcpyDeviceToHost, stream));
		else
			memcpy((uint8_t*)m_h_stream + sizeof(LhcHeader), rgba_half, raw_bytes);
		*out_size = sizeof(LhcHeader) + raw_bytes;
	}

	LHC_CHECK(cudaEventRecord((cudaEvent_t)m_ev1, stream));
	LHC_CHECK(cudaStreamSynchronize(stream));
	cudaEventElapsedTime(&m_last_gpu_ms, (cudaEvent_t)m_ev0, (cudaEvent_t)m_ev1);

	m_ref_valid = true;
	m_ref_width = width;
	m_ref_height = height;
	m_sequence = sequence;

	*out = (const uint8_t*)m_h_stream;
	return 0;
}

int HalfCodec::decode(const uint8_t* data, size_t size, void* rgba_half_out, int width, int height)
{
	if (size < sizeof(LhcHeader) || data == nullptr || rgba_half_out == nullptr)
		return 1;

	LhcHeader h;
	memcpy(&h, data, sizeof(LhcHeader));
	if (h.magic != LHC_MAGIC) {
		fprintf(stderr, "HalfCodec::decode: bad magic 0x%08x\n", h.magic);
		return 1;
	}
	if ((int)h.width != width || (int)h.height != height) {
		fprintf(stderr, "HalfCodec::decode: size mismatch %ux%u != %dx%d\n", h.width, h.height, width, height);
		return 1;
	}

	const bool keyframe = (h.flags & LHC_FLAG_KEYFRAME) != 0;
	if (!keyframe && (!m_ref_valid || m_ref_width != width || m_ref_height != height || h.sequence != m_sequence + 1)) {
		fprintf(stderr, "HalfCodec::decode: lost temporal reference (sequence %u, expected %u)\n", h.sequence, m_sequence + 1);
		m_ref_valid = false;
		return 1;
	}
	m_ref_valid = false;

	if (!ensure_stream())
		return 1;
	cudaStream_t stream = (cudaStream_t)m_stream;

	const size_t raw_bytes = (size_t)width * height * 8;
	const bool dst_on_device = lhc_is_device_ptr(rgba_half_out);

	if (!ensure(&m_d_ref, &m_d_ref_cap, raw_bytes, false))
		return 1;

	LHC_CHECK(cudaEventRecord((cudaEvent_t)m_ev0, stream));

	if (h.flags & LHC_FLAG_RAW) {
		if (size < sizeof(LhcHeader) + raw_bytes)
			return 1;
		LHC_CHECK(cudaMemcpyAsync(m_d_ref, data + sizeof(LhcHeader), raw_bytes, cudaMemcpyHostToDevice, stream));
	}
	else {
		const int tiles_x = (int)h.tiles_x;
		const int num_tiles = (int)(h.tiles_x * h.tiles_y);
		const int shift = LHC_MANTISSA_BITS_LOSSLESS - (int)h.mantissa_bits;
		const size_t expected = sizeof(LhcHeader) + (size_t)num_tiles * 4 + (size_t)h.payload_words * 4;
		if (size < expected || tiles_x != (width + LHC_TILE - 1) / LHC_TILE ||
			(int)h.tiles_y != (height + LHC_TILE - 1) / LHC_TILE || shift < 0 || shift > 9) {
			fprintf(stderr, "HalfCodec::decode: corrupted stream\n");
			return 1;
		}

		if (!ensure(&m_d_stream, &m_d_stream_cap, expected, false))
			return 1;
		LHC_CHECK(cudaMemcpyAsync(m_d_stream, data, expected, cudaMemcpyHostToDevice, stream));

		const unsigned int* d_offsets = (const unsigned int*)m_d_stream + sizeof(LhcHeader) / 4;
		const unsigned int* d_payload = d_offsets + num_tiles;

		const int threads = 32 * LHC_WARPS_PER_BLOCK;
		const int blocks = (num_tiles + LHC_WARPS_PER_BLOCK - 1) / LHC_WARPS_PER_BLOCK;
		lhc_decode_kernel<<<blocks, threads, 0, stream>>>(d_offsets, d_payload, width, height, shift, tiles_x, num_tiles,
			keyframe ? 0 : 1, (ushort4*)m_d_ref);
		LHC_CHECK(cudaGetLastError());
	}

	LHC_CHECK(cudaMemcpyAsync(rgba_half_out, m_d_ref, raw_bytes,
		dst_on_device ? cudaMemcpyDeviceToDevice : cudaMemcpyDeviceToHost, stream));

	LHC_CHECK(cudaEventRecord((cudaEvent_t)m_ev1, stream));
	LHC_CHECK(cudaStreamSynchronize(stream));
	cudaEventElapsedTime(&m_last_gpu_ms, (cudaEvent_t)m_ev0, (cudaEvent_t)m_ev1);

	m_ref_valid = true;
	m_ref_width = width;
	m_ref_height = height;
	m_sequence = h.sequence;
	return 0;
}

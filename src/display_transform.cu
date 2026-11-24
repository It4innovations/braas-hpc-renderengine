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

#include "display_transform.h"

#include <cuda_fp16.h>
#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>

#define DT_CHECK(stmt) \
	do { \
		cudaError_t err__ = (stmt); \
		if (err__ != cudaSuccess) { \
			fprintf(stderr, "DisplayTransform CUDA error: %s in %s (%s:%d)\n", cudaGetErrorString(err__), #stmt, __FILE__, __LINE__); \
			return 1; \
		} \
	} while (0)

__device__ __forceinline__ float dt_srgb(float c)
{
	c = fminf(fmaxf(c, 0.0f), 1.0f);
	return (c <= 0.0031308f) ? 12.92f * c : 1.055f * powf(c, 1.0f / 2.4f) - 0.055f;
}

__device__ __forceinline__ float dt_shaper(float x, float log2_min, float scale, int last)
{
	const float s = (log2f(fmaxf(x, exp2f(log2_min))) - log2_min) * scale;
	return fminf(fmaxf(s, 0.0f), (float)last);
}

__device__ __forceinline__ float3 dt_lut_lookup(const float* __restrict__ lut, int size, float fr, float fg, float fb)
{
	const int last = size - 1;
	const int r0 = min((int)fr, last - 1), g0 = min((int)fg, last - 1), b0 = min((int)fb, last - 1);
	const float dr = fr - r0, dg = fg - g0, db = fb - b0;

	float3 acc = make_float3(0.0f, 0.0f, 0.0f);
#pragma unroll
	for (int k = 0; k < 8; k++) {
		const int ir = r0 + (k & 1), ig = g0 + ((k >> 1) & 1), ib = b0 + ((k >> 2) & 1);
		const float w = ((k & 1) ? dr : 1.0f - dr) * (((k >> 1) & 1) ? dg : 1.0f - dg) * (((k >> 2) & 1) ? db : 1.0f - db);
		const float* p = lut + ((size_t)(ib * size + ig) * size + ir) * 3;
		acc.x += w * p[0];
		acc.y += w * p[1];
		acc.z += w * p[2];
	}
	return acc;
}

__global__ void dt_apply_kernel(const __half* __restrict__ src, uchar4* __restrict__ dst, size_t n,
	const float* __restrict__ lut, int lut_size, float log2_min, float log2_max,
	float exposure_scale, float inv_gamma)
{
	const size_t i = (size_t)blockIdx.x * blockDim.x + threadIdx.x;
	if (i >= n)
		return;

	float r = __half2float(src[i * 4 + 0]);
	float g = __half2float(src[i * 4 + 1]);
	float b = __half2float(src[i * 4 + 2]);
	float a = __half2float(src[i * 4 + 3]);
	if (!isfinite(r)) r = 0.0f;
	if (!isfinite(g)) g = 0.0f;
	if (!isfinite(b)) b = 0.0f;
	a = isfinite(a) ? fminf(fmaxf(a, 0.0f), 1.0f) : 1.0f;

	// Blender draws render results with "predivide": un-premultiply, transform, premultiply
	const bool predivide = a > 0.0f && a < 1.0f;
	if (predivide) {
		const float ia = 1.0f / a;
		r *= ia; g *= ia; b *= ia;
	}

	r *= exposure_scale;
	g *= exposure_scale;
	b *= exposure_scale;

	float3 d;
	if (lut) {
		const int last = lut_size - 1;
		const float scale = (float)last / (log2_max - log2_min);
		d = dt_lut_lookup(lut, lut_size,
			dt_shaper(r, log2_min, scale, last),
			dt_shaper(g, log2_min, scale, last),
			dt_shaper(b, log2_min, scale, last));
	}
	else {
		d = make_float3(dt_srgb(r), dt_srgb(g), dt_srgb(b));
	}

	d.x = fmaxf(d.x, 0.0f);
	d.y = fmaxf(d.y, 0.0f);
	d.z = fmaxf(d.z, 0.0f);
	if (inv_gamma != 1.0f) {
		d.x = powf(d.x, inv_gamma);
		d.y = powf(d.y, inv_gamma);
		d.z = powf(d.z, inv_gamma);
	}
	if (predivide) {
		d.x *= a; d.y *= a; d.z *= a;
	}

	uchar4 o;
	o.x = (unsigned char)(fminf(d.x, 1.0f) * 255.0f + 0.5f);
	o.y = (unsigned char)(fminf(d.y, 1.0f) * 255.0f + 0.5f);
	o.z = (unsigned char)(fminf(d.z, 1.0f) * 255.0f + 0.5f);
	o.w = (unsigned char)(a * 255.0f + 0.5f);
	dst[i] = o;
}

static bool dt_is_device_ptr(const void* ptr)
{
	cudaPointerAttributes attr;
	if (cudaPointerGetAttributes(&attr, ptr) != cudaSuccess) {
		cudaGetLastError();
		return false;
	}
	return attr.type == cudaMemoryTypeDevice || attr.type == cudaMemoryTypeManaged;
}

static bool dt_ensure(void** ptr, size_t* cap, size_t size)
{
	if (*ptr && *cap >= size)
		return true;
	if (*ptr)
		cudaFree(*ptr);
	*ptr = nullptr;
	*cap = 0;
	if (cudaMalloc(ptr, size) != cudaSuccess) {
		*ptr = nullptr;
		return false;
	}
	*cap = size;
	return true;
}

DisplayTransform::DisplayTransform() {}

DisplayTransform::~DisplayTransform()
{
	if (m_d_lut) cudaFree(m_d_lut);
	if (m_d_src) cudaFree(m_d_src);
	if (m_d_out) cudaFree(m_d_out);
}

int DisplayTransform::set_lut(const float* lut, int size, float log2_min, float log2_max)
{
	if (m_d_lut) {
		cudaFree(m_d_lut);
		m_d_lut = nullptr;
	}
	m_lut_size = 0;

	if (lut == nullptr)
		return 0;
	if (size < 2 || !(log2_max > log2_min)) {
		fprintf(stderr, "DisplayTransform::set_lut: invalid LUT (size %d, range %f..%f)\n", size, log2_min, log2_max);
		return 1;
	}

	const size_t bytes = (size_t)size * size * size * 3 * sizeof(float);
	DT_CHECK(cudaMalloc(&m_d_lut, bytes));
	DT_CHECK(cudaMemcpy(m_d_lut, lut, bytes, cudaMemcpyHostToDevice));
	m_lut_size = size;
	m_log2_min = log2_min;
	m_log2_max = log2_max;
	return 0;
}

int DisplayTransform::apply(const void* rgba_half, int width, int height, float exposure, float gamma, void** d_rgba8)
{
	const size_t n = (size_t)width * height;
	if (n == 0 || rgba_half == nullptr)
		return 1;

	const __half* d_src = (const __half*)rgba_half;
	if (!dt_is_device_ptr(rgba_half)) {
		if (!dt_ensure(&m_d_src, &m_d_src_cap, n * 8))
			return 1;
		DT_CHECK(cudaMemcpy(m_d_src, rgba_half, n * 8, cudaMemcpyHostToDevice));
		d_src = (const __half*)m_d_src;
	}
	else {
		DT_CHECK(cudaDeviceSynchronize());  // producer may run on another stream
	}

	if (!dt_ensure(&m_d_out, &m_d_out_cap, n * 4))
		return 1;

	const float exposure_scale = std::exp2(exposure);
	const float inv_gamma = 1.0f / std::fmax(gamma, 1e-5f);

	const int threads = 256;
	const unsigned int blocks = (unsigned int)((n + threads - 1) / threads);
	dt_apply_kernel<<<blocks, threads>>>(d_src, (uchar4*)m_d_out, n, (const float*)m_d_lut, m_lut_size,
		m_log2_min, m_log2_max, exposure_scale, inv_gamma);
	DT_CHECK(cudaGetLastError());
	DT_CHECK(cudaDeviceSynchronize());

	*d_rgba8 = m_d_out;
	return 0;
}

// Round-trip test and benchmark of the LHC (linear half) codec.
//
//   test_half_codec                      synthetic path-tracing-like frames
//   test_half_codec <file.raw> <w> <h>   real frame: raw half4 RGBA dump (8 bytes/pixel)

#include "half_codec.h"

#include <cuda_fp16.h>
#include <cuda_runtime.h>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <string>
#include <vector>

static uint16_t f2h(float f)
{
	__half h = __float2half_rn(f);
	uint16_t u;
	memcpy(&u, &h, 2);
	return u;
}

static float h2f(uint16_t u)
{
	__half h;
	memcpy(&h, &u, 2);
	return __half2float(h);
}

// HDR "scene": sky gradient, a hot emitter, dark corners, textured surfaces; multiplicative
// Monte Carlo noise ~ 1/sqrt(spp), mostly luminance (correlated between channels).
static std::vector<uint16_t> make_frame(int w, int h, int spp, unsigned seed)
{
	std::vector<uint16_t> img((size_t)w * h * 4);
	std::mt19937 rng(seed);
	std::normal_distribution<float> n01(0.0f, 1.0f);
	const float sigma = spp > 0 ? 1.2f / std::sqrt((float)spp) : 0.0f;

	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			float u = (float)x / w, v = (float)y / h;
			float r, g, b;
			if (v > 0.6f) {  // sky
				float s = (v - 0.6f) / 0.4f;
				r = 0.3f + 2.0f * s; g = 0.5f + 2.5f * s; b = 1.0f + 4.0f * s;
			}
			else {  // ground with texture + shadows
				float tex = 0.5f + 0.5f * std::sin(u * 80.0f) * std::sin(v * 60.0f);
				float shadow = (u > 0.3f && u < 0.6f && v < 0.4f) ? 0.02f : 1.0f;
				r = 0.18f * (0.6f + 0.8f * tex) * shadow;
				g = 0.15f * (0.6f + 0.8f * tex) * shadow;
				b = 0.10f * (0.6f + 0.8f * tex) * shadow;
			}
			float dx = u - 0.8f, dy = v - 0.85f;
			float d2 = dx * dx + dy * dy;
			if (d2 < 0.002f) { r = 900.0f; g = 800.0f; b = 600.0f; }  // emitter
			float vign = 1.0f - 0.9f * (std::fabs(u - 0.5f) + std::fabs(v - 0.5f));
			r *= vign; g *= vign; b *= vign;

			if (sigma > 0.0f) {
				float l = std::max(0.0f, 1.0f + sigma * n01(rng));
				// fireflies
				if ((rng() & 1023) == 0 && spp < 64) l *= 20.0f;
				r *= l * std::max(0.0f, 1.0f + 0.2f * sigma * n01(rng));
				g *= l * std::max(0.0f, 1.0f + 0.2f * sigma * n01(rng));
				b *= l * std::max(0.0f, 1.0f + 0.2f * sigma * n01(rng));
			}
			size_t i = ((size_t)y * w + x) * 4;
			img[i + 0] = f2h(r);
			img[i + 1] = f2h(g);
			img[i + 2] = f2h(b);
			img[i + 3] = f2h(1.0f);
		}
	}
	return img;
}

struct Stats {
	double max_rel = 0;
	double mean_rel = 0;
	size_t mismatches = 0;
};

static Stats compare(const std::vector<uint16_t>& a, const std::vector<uint16_t>& b)
{
	Stats s;
	double sum = 0;
	size_t n = 0;
	for (size_t i = 0; i < a.size(); i++) {
		if (a[i] != b[i])
			s.mismatches++;
		float fa = h2f(a[i]), fb = h2f(b[i]);
		if (!std::isfinite(fa))
			continue;
		double denom = std::max(std::fabs((double)fa), 6.103515625e-5);  // relative above smallest normal (2^-14)
		double rel = std::fabs((double)fa - fb) / denom;
		s.max_rel = std::max(s.max_rel, rel);
		sum += rel;
		n++;
	}
	s.mean_rel = n ? sum / n : 0;
	return s;
}

static bool run(const char* name, const std::vector<uint16_t>& img, int w, int h)
{
	HalfCodec enc, dec;
	enc.set_temporal(false);  // spatial only - every frame is a key frame
	const size_t raw = (size_t)w * h * 8;

	void* d_img = nullptr;
	void* d_out = nullptr;
	cudaMalloc(&d_img, raw);
	cudaMalloc(&d_out, raw);
	cudaMemcpy(d_img, img.data(), raw, cudaMemcpyHostToDevice);

	std::vector<uint16_t> out(img.size());
	bool ok = true;

	printf("\n%s  %dx%d  raw %.2f MB\n", name, w, h, raw / 1048576.0);
	printf("  mbits |  ratio |   bpp  |  enc ms (gpu) |  dec ms (gpu) | max rel err | mean rel err | exact\n");

	for (int mbits = 10; mbits >= 5; mbits--) {
		const uint8_t* stream = nullptr;
		size_t size = 0;

		// warm up + correctness (device -> host stream -> device)
		if (enc.encode(d_img, w, h, mbits, &stream, &size) != 0) { printf("encode failed\n"); return false; }
		std::vector<uint8_t> copy(stream, stream + size);
		cudaMemset(d_out, 0, raw);
		if (dec.decode(copy.data(), copy.size(), d_out, w, h) != 0) { printf("decode failed\n"); return false; }
		cudaMemcpy(out.data(), d_out, raw, cudaMemcpyDeviceToHost);

		// host -> host path must give identical result
		std::vector<uint16_t> out_host(img.size());
		const uint8_t* stream2 = nullptr;
		size_t size2 = 0;
		enc.encode(img.data(), w, h, mbits, &stream2, &size2);
		std::vector<uint8_t> copy2(stream2, stream2 + size2);
		dec.decode(copy2.data(), copy2.size(), out_host.data(), w, h);
		if (size2 != size || memcmp(out_host.data(), out.data(), raw) != 0) {
			printf("  host and device paths differ!\n");
			ok = false;
		}

		const int iters = 20;
		double enc_ms = 0, dec_ms = 0, enc_gpu = 0, dec_gpu = 0;
		for (int i = 0; i < iters; i++) {
			auto t0 = std::chrono::high_resolution_clock::now();
			enc.encode(d_img, w, h, mbits, &stream, &size);
			auto t1 = std::chrono::high_resolution_clock::now();
			enc_gpu += enc.last_gpu_ms();
			dec.decode(copy.data(), copy.size(), d_out, w, h);
			auto t2 = std::chrono::high_resolution_clock::now();
			dec_gpu += dec.last_gpu_ms();
			enc_ms += std::chrono::duration<double, std::milli>(t1 - t0).count();
			dec_ms += std::chrono::duration<double, std::milli>(t2 - t1).count();
		}
		enc_ms /= iters; dec_ms /= iters; enc_gpu /= iters; dec_gpu /= iters;

		Stats s = compare(img, out);
		const double bound = std::ldexp(1.0, -(mbits + 1)) * 1.0001;
		const bool exact = s.mismatches == 0;
		if (mbits == 10 && !exact) ok = false;
		if (s.max_rel > bound) ok = false;

		printf("  %5d | %6.2f | %6.2f | %5.2f (%5.2f) | %5.2f (%5.2f) |   %.2e  |   %.2e   | %s%s\n",
			mbits, (double)raw / size, size * 8.0 / ((double)w * h), enc_ms, enc_gpu, dec_ms, dec_gpu,
			s.max_rel, s.mean_rel, exact ? "yes" : "no",
			s.max_rel > bound ? "  <-- ERROR BOUND VIOLATED" : "");
	}

	cudaFree(d_img);
	cudaFree(d_out);
	return ok;
}

// Progressive accumulation like cyclesphi: frame N = mean of N noisy samples.
static bool run_accumulation(int w, int h, int frames, int mbits)
{
	std::vector<uint16_t> base = make_frame(w, h, 0, 7);
	std::vector<float> acc((size_t)w * h * 3, 0.0f);
	std::vector<uint16_t> img(base.size()), out(base.size());
	std::mt19937 rng(11);
	std::normal_distribution<float> n01(0.0f, 1.0f);
	const size_t raw = (size_t)w * h * 8;

	HalfCodec enc_t, enc_s, dec;
	enc_s.set_temporal(false);
	void* d_img = nullptr;
	void* d_out = nullptr;
	cudaMalloc(&d_img, raw);
	cudaMalloc(&d_out, raw);

	printf("\naccumulation %dx%d, mantissa bits %d\n", w, h, mbits);
	printf("  frame | spatial ratio | temporal ratio | temporal bpp | enc ms | dec ms | max rel err | exact\n");
	bool ok = true;
	double tot_s = 0, tot_t = 0;
	for (int n = 1; n <= frames; n++) {
		for (size_t p = 0; p < (size_t)w * h; p++) {
			float l = std::max(0.0f, 1.0f + 1.2f * n01(rng));
			if ((rng() & 1023) == 0) l *= 20.0f;
			for (int c = 0; c < 3; c++) {
				float sample = h2f(base[p * 4 + c]) * l * std::max(0.0f, 1.0f + 0.25f * n01(rng));
				acc[p * 3 + c] += (sample - acc[p * 3 + c]) / n;
				img[p * 4 + c] = f2h(acc[p * 3 + c]);
			}
			img[p * 4 + 3] = f2h(1.0f);
		}
		cudaMemcpy(d_img, img.data(), raw, cudaMemcpyHostToDevice);

		const uint8_t* stream = nullptr;
		size_t size_s = 0, size_t_ = 0;
		enc_s.encode(d_img, w, h, mbits, &stream, &size_s);
		auto t0 = std::chrono::high_resolution_clock::now();
		enc_t.encode(d_img, w, h, mbits, &stream, &size_t_);
		auto t1 = std::chrono::high_resolution_clock::now();
		std::vector<uint8_t> copy(stream, stream + size_t_);
		auto t2 = std::chrono::high_resolution_clock::now();
		if (dec.decode(copy.data(), copy.size(), d_out, w, h) != 0) { printf("decode failed\n"); ok = false; break; }
		auto t3 = std::chrono::high_resolution_clock::now();
		cudaMemcpy(out.data(), d_out, raw, cudaMemcpyDeviceToHost);

		Stats s = compare(img, out);
		const bool exact = s.mismatches == 0;
		if (mbits == 10 && !exact) ok = false;
		if (s.max_rel > std::ldexp(1.0, -(mbits + 1)) * 1.0001) ok = false;
		tot_s += size_s; tot_t += size_t_;
		if ((n & (n - 1)) == 0 || n == frames)
			printf("  %5d | %13.2f | %14.2f | %12.2f | %6.2f | %6.2f |   %.2e  | %s\n", n,
				(double)raw / size_s, (double)raw / size_t_, size_t_ * 8.0 / ((double)w * h),
				std::chrono::duration<double, std::milli>(t1 - t0).count(),
				std::chrono::duration<double, std::milli>(t3 - t2).count(), s.max_rel, exact ? "yes" : "no");
	}
	printf("  total over %d frames: spatial %.2fx, temporal %.2fx\n", frames, frames * (double)raw / tot_s, frames * (double)raw / tot_t);
	cudaFree(d_img);
	cudaFree(d_out);
	return ok;
}

int main(int argc, char** argv)
{
	cudaSetDevice(0);
	cudaDeviceProp prop;
	cudaGetDeviceProperties(&prop, 0);
	printf("GPU: %s\n", prop.name);

	bool ok = true;

	if (argc >= 4) {
		int w = atoi(argv[2]), h = atoi(argv[3]);
		std::vector<uint16_t> img((size_t)w * h * 4);
		FILE* f = fopen(argv[1], "rb");
		if (!f || fread(img.data(), 8, (size_t)w * h, f) != (size_t)w * h) {
			printf("cannot read %s\n", argv[1]);
			return 2;
		}
		fclose(f);
		ok &= run(argv[1], img, w, h);
	}
	else {
		ok &= run("tiny 5x3 (edge handling)", make_frame(5, 3, 4, 1), 5, 3);
		ok &= run("odd 1917x1081, 1 spp", make_frame(1917, 1081, 1, 2), 1917, 1081);
		for (int spp : { 1, 16, 256, 0 }) {
			std::string name = "1920x1080, " + (spp ? std::to_string(spp) + " spp" : std::string("noise free"));
			ok &= run(name.c_str(), make_frame(1920, 1080, spp, 3), 1920, 1080);
		}
		ok &= run("3840x2160, 16 spp", make_frame(3840, 2160, 16, 4), 3840, 2160);

		// incompressible input -> raw fallback
		ok &= run_accumulation(1920, 1080, 128, 10);
		ok &= run_accumulation(1920, 1080, 128, 8);
		ok &= run_accumulation(1920, 1080, 128, 6);

		std::vector<uint16_t> rnd((size_t)640 * 480 * 4);
		std::mt19937 rng(5);
		for (auto& v : rnd) { v = (uint16_t)(rng() & 0x7bff); }
		ok &= run("random bits (raw fallback)", rnd, 640, 480);
	}

	printf("\n%s\n", ok ? "ALL OK" : "FAILED");
	return ok ? 0 : 1;
}

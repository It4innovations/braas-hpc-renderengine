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

// Server side color management for display-referred streaming (e.g. GPUJPEG).
//
// Reproduces Blender's viewport color management on the GPU:
//   scene linear * 2^exposure  ->  view transform + look + display (3D LUT)  ->  ^(1/gamma)  ->  8 bit
//
// The view/look/display part is baked by the renderer (it owns the OCIO config) into a 3D LUT
// over a log2 shaper: lattice coordinate = (log2(x) - log2_min) / (log2_max - log2_min). Use an
// odd LUT size with integer log2 bounds (e.g. 97 over [-16, 16]) so that x = 1.0 lies on a
// lattice point - the clip of the "Standard" view is then reproduced exactly.
// Without a LUT the plain sRGB transfer function ("Standard" view) is used.

#ifndef __DISPLAY_TRANSFORM_H__
#define __DISPLAY_TRANSFORM_H__

#include <cstddef>
#include <cstdint>

#define DISPLAY_LUT_DEFAULT_SIZE 97
#define DISPLAY_LUT_DEFAULT_LOG2_MIN -16.0f
#define DISPLAY_LUT_DEFAULT_LOG2_MAX 16.0f

class DisplayTransform {
public:
	DisplayTransform();
	~DisplayTransform();

	// lut: size^3 RGB float triplets, red index fastest: ((b * size + g) * size + r) * 3.
	// Pass nullptr to go back to the built-in sRGB transfer function.
	int set_lut(const float* lut, int size, float log2_min, float log2_max);
	bool has_lut() const { return m_d_lut != nullptr; }

	// half4 RGBA scene linear (device or host pointer) -> RGBA8 display referred in a device
	// buffer owned by this object (*d_rgba8, valid until the next call).
	int apply(const void* rgba_half, int width, int height, float exposure, float gamma, void** d_rgba8);

private:
	void* m_d_lut = nullptr;
	int m_lut_size = 0;
	float m_log2_min = 0.0f;
	float m_log2_max = 0.0f;

	void* m_d_src = nullptr; size_t m_d_src_cap = 0;
	void* m_d_out = nullptr; size_t m_d_out_cap = 0;
};

#endif

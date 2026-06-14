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

#ifndef __RENDERENGINE_DATA_H__
#define __RENDERENGINE_DATA_H__

struct alignas(16) renderengine_cam {
	int magic_number = 999; // ack

	float transform_inverse_view_matrix[12] = {};

	float lens = 0;
	float clip_start = 0;
	float clip_end = 0;

	float sensor_width = 0;
	float sensor_height = 0;
	int sensor_fit = 0;

	float shift_x = 0;
	float shift_y = 0;

	float interocular_distance = 0;
	float convergence_distance = 0;

	float view_camera_zoom = 0;
	float view_camera_offset[2] = {};
	int use_view_camera = 0;
	int view_perspective = 0;

	// Explicit padding to preserve 16-byte alignment
	int _pad[2];
};

struct alignas(16) renderengine_data {
	int magic_number = 999; // ack

	//char filename[1024];
	int width = 0, height = 0;
	//int step_samples;
	int reset = 0;
	int frame = 0;

	renderengine_cam cam = {};
};

//typedef struct BRaaSHPCDataRender {
//	float colorMap[4 * 128];
//	float domain[2];
//	float baseDensity;
//}BRaaSHPCDataRender;

struct alignas(16) BRaaSHPCDataState {
	float world_bounds_spatial_lower[3] = {};
	float world_bounds_spatial_upper[3] = {};
	float scalars_range[2] = {};
	int samples = 0;
	float fps = 0;
};

#endif

// #####################################################################################################################
// # Copyright(C) 2011-2025 IT4Innovations National Supercomputing Center, VSB - Technical University of Ostrava
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

typedef struct renderengine_cam {
	float transform_inverse_view_matrix[12];

	float lens;
	float clip_start;
	float clip_end;

	float sensor_width;
	float sensor_height;
	int sensor_fit;

	float shift_x;
	float shift_y;

	float interocular_distance;
	float convergence_distance;

	float view_camera_zoom;
	float view_camera_offset[2];
	int use_view_camera;
	int view_perspective;
}renderengine_cam;

typedef struct renderengine_data {
	//char filename[1024];
	int width, height;
	//int step_samples;
	int reset;
	int frame;

	struct renderengine_cam cam;

}renderengine_data;

//typedef struct BRaaSHPCDataRender {
//	float colorMap[4 * 128];
//	float domain[2];
//	float baseDensity;
//}BRaaSHPCDataRender;

typedef struct BRaaSHPCDataState {
	float world_bounds_spatial_lower[3];
	float world_bounds_spatial_upper[3];
	float scalars_range[2];
	int samples;
	float fps;
} BRaaSHPCDataState;

#endif

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

// Pixel stream codecs requested by the client (renderengine_stream_settings::codec).
// LEGACY keeps the original wire format (raw pixels or gpujpeg without a frame header, chosen by
// set_pixsize/enable_gpujpeg on both sides). All other codecs send a renderengine_frame_header
// in front of every frame.
#define RENDERENGINE_CODEC_LEGACY 0
#define RENDERENGINE_CODEC_RAW_HALF 1      // half4 scene linear, uncompressed
#define RENDERENGINE_CODEC_LHC 2           // half4 scene linear, LHC GPU codec (lossless / near lossless)
#define RENDERENGINE_CODEC_JPEG_DISPLAY 3  // server side color management -> RGBA8 display referred -> GPUJPEG

#define RENDERENGINE_STREAM_NAME_LEN 64

// Sent by the client with every camera update. Not part of the camera change detection on the
// server (changing e.g. the exposure must not restart the accumulation).
struct alignas(16) renderengine_stream_settings {
	int codec = RENDERENGINE_CODEC_LEGACY;
	int quality = 0;           // LHC: mantissa bits 1..10 (10 = lossless), JPEG: 1..100, 0 = default
	int request_keyframe = 0;  // client lost the temporal reference of the LHC codec
	int _pad0 = 0;

	// Blender scene color management (used by RENDERENGINE_CODEC_JPEG_DISPLAY)
	float exposure = 0.0f;
	float gamma = 1.0f;
	int _pad1[2] = {};
	char display[RENDERENGINE_STREAM_NAME_LEN] = {};  // scene.display_settings.display_device
	char view[RENDERENGINE_STREAM_NAME_LEN] = {};     // scene.view_settings.view_transform
	char look[RENDERENGINE_STREAM_NAME_LEN] = {};     // scene.view_settings.look ("None" = no look)
};

struct alignas(16) renderengine_data {
	int magic_number = 999; // ack

	//char filename[1024];
	int width = 0, height = 0;
	//int step_samples;
	int reset = 0;
	int frame = 0;

	renderengine_cam cam = {};

	// keep last: the server compares only the bytes before this member to detect camera changes
	renderengine_stream_settings stream = {};
};

#define RENDERENGINE_FRAME_MAGIC 0x4D415246  // "FRAM"

// Sent by the server in front of every frame when a non-legacy codec is used.
struct alignas(16) renderengine_frame_header {
	int magic = RENDERENGINE_FRAME_MAGIC;
	int codec = RENDERENGINE_CODEC_LEGACY;
	int width = 0;
	int height = 0;
	unsigned long long payload_size = 0;  // bytes following the header
	int pixel_bits = 16;                  // decoded texel channel size: 8 (RGBA8) or 16 (RGBA half)
	int display_referred = 0;             // 1: already color managed, the client must not apply OCIO
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

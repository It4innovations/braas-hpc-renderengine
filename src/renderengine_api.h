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

#ifndef __BRAAS_HPC_API_H__
#define __BRAAS_HPC_API_H__

#if defined(__APPLE__)
#	define BRAAS_HPC_EXPORT_DLL
#	define BRAAS_HPC_EXPORT_STD
#elif defined(_WIN32)
#	define BRAAS_HPC_EXPORT_DLL __declspec(dllexport)
#	define BRAAS_HPC_EXPORT_STD __stdcall
#else
#	define BRAAS_HPC_EXPORT_DLL
#	define BRAAS_HPC_EXPORT_STD
#endif

#ifdef __cplusplus
extern "C"
{
#endif

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD resize(int width, int height);
	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD set_resolution(int width, int height);
	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD set_frame(int frame);

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD get_pixels(void* pixels);
	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD set_pixels(void* pixels, bool device);
	BRAAS_HPC_EXPORT_DLL size_t BRAAS_HPC_EXPORT_STD get_gpu_buffer();

	BRAAS_HPC_EXPORT_DLL int BRAAS_HPC_EXPORT_STD recv_pixels_data();
	BRAAS_HPC_EXPORT_DLL int BRAAS_HPC_EXPORT_STD send_pixels_data();
	
	BRAAS_HPC_EXPORT_DLL int BRAAS_HPC_EXPORT_STD send_cam_data();
	BRAAS_HPC_EXPORT_DLL int BRAAS_HPC_EXPORT_STD recv_cam_data();

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD set_timestep(int timestep);

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD client_init(const char *server, int port, int w, int h);
	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD server_init(const char* server, int port, int w, int h);

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD client_close_connection();
	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD server_close_connection();

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD set_camera(void *view_martix,
														  float lens,
														  float nearclip,
														  float farclip,
														  float sensor_width,
														  float sensor_height,
														  int sensor_fit,
														  float view_camera_zoom,
														  float view_camera_offset0,
														  float view_camera_offset1,
														  int use_view_camera,
														  float shift_x,
														  float shift_y,
														  int view_perspective);

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD get_camera(void* view_martix,
		float* lens,
		float* nearclip,
		float* farclip,
		float* sensor_width,
		float* sensor_height,
		int* sensor_fit,
		float* view_camera_zoom,
		float* view_camera_offset0,
		float* view_camera_offset1,
		int* use_view_camera,
		float* shift_x,
		float* shift_y,
		int* view_perspective);

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD draw_texture();

	BRAAS_HPC_EXPORT_DLL int BRAAS_HPC_EXPORT_STD get_current_samples();
	BRAAS_HPC_EXPORT_DLL float BRAAS_HPC_EXPORT_STD get_remote_fps();
	BRAAS_HPC_EXPORT_DLL float BRAAS_HPC_EXPORT_STD get_local_fps();

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD reset();

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD  send_braas_hpc_renderengine_data_render(const char* data, int size);
	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD  recv_braas_hpc_renderengine_data(const char* data, int size);

	BRAAS_HPC_EXPORT_DLL void BRAAS_HPC_EXPORT_STD  get_braas_hpc_renderengine_range(
		void* world_bounds_spatial_lower,
		void* world_bounds_spatial_upper,
		void* scalars_range);

	BRAAS_HPC_EXPORT_DLL int BRAAS_HPC_EXPORT_STD get_texture_id();

	BRAAS_HPC_EXPORT_DLL int BRAAS_HPC_EXPORT_STD com_error();
	

#ifdef __cplusplus
}
#endif
#endif

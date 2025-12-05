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

#include "renderengine_api.h"
#include "renderengine_data.h"

//#ifdef _WIN32
//#	include <glad/glad.h>
//#endif
#ifdef WITH_CLIENT_EPOXY
#	include <epoxy/gl.h>
#	include <cuda_gl_interop.h>
#elif defined(WITH_CLIENT_GPUJPEG)
#	include <cuda_runtime.h>
#endif

#include "renderengine_tcp.h"

#include <iostream>
#include <string.h>
#include <string>
#include <stdlib.h>
//#include <vector>

#define TCP_PIX_SIZE_F32 sizeof(float)
#define TCP_PIX_SIZE_U16 sizeof(unsigned short)
#define TCP_PIX_SIZE_U8 sizeof(unsigned char)

size_t PIX_SIZE = TCP_PIX_SIZE_U8;

#ifdef WITH_CLIENT_GPUJPEG
bool USE_GPUJPEG = true;
#else
bool USE_GPUJPEG = false;
#endif

//////////////////////////

#ifdef _WIN32
int setenv(const char* name, const char* value, int overwrite)
{
	int errcode = 0;
	if (!overwrite) {
		size_t envsize = 0;
		errcode = getenv_s(&envsize, NULL, 0, name);
		if (errcode || envsize)
			return errcode;
	}
	return _putenv_s(name, value);
}
#endif

TcpConnection tcpConnection;

//unsigned int g_renderengine_data.width = 2;
//unsigned int g_renderengine_data.height = 1;

unsigned char* g_pixels_buf = NULL;
void* g_pixels_buf_d = NULL;
void* g_pixels_buf_recv_d = NULL;

#ifdef WITH_CLIENT_EPOXY
GLuint g_bufferId;   // ID of PBO
GLuint g_textureId;  // ID of texture
#endif

renderengine_data g_renderengine_data;
renderengine_data g_renderengine_data_recv;
BRaaSHPCDataState g_hs_data_state;

double g_previousTime[3] = { 0, 0, 0 };
int g_frameCount[3] = { 0, 0, 0 };
char fname[1024];

float g_right_eye = 0.035f;

struct stl_tri;
stl_tri* polys = NULL;
size_t polys_size = 0;

//int current_samples = 0;

int active_gpu = 1;
float local_fps = 0;

/////////////////////////
#if 0 //def _WIN32
#include <omp.h>
void displayFPS(int type, int tot_samples = 0)
{
	double currentTime = omp_get_wtime();
	g_frameCount[type]++;

	local_fps = (double)g_frameCount[type] / (currentTime - g_previousTime[type]);

	if (currentTime - g_previousTime[type] >= 3.0)
	{		
		if (local_fps > 0.01)
		{
			char sTemp[1024];

			//int* samples = (int*)&g_renderengine_data.step_samples;

			sprintf(sTemp,
				"FPS: %.2f, Total Samples: %d, Res: %d x %d",
				local_fps,
				tot_samples,
				g_renderengine_data.width,
				g_renderengine_data.height);
			printf("%s\n", sTemp);
		}
		g_frameCount[type] = 0;
		g_previousTime[type] = omp_get_wtime();
	}
}
#endif
//////////////////////////
void check_exit()
{
}

#if defined(WITH_CLIENT_EPOXY) || defined(WITH_CLIENT_GPUJPEG)

#define cuda_assert(stmt) \
  { \
    if (stmt != cudaSuccess) { \
      char err[1024]; \
      sprintf(err, \
              "CUDA error: %s: %s in %s, line %d", \
              cudaGetErrorName(stmt), \
              cudaGetErrorString(stmt), \
              #stmt, \
              __LINE__); \
      std::string message(err); \
      fprintf(stderr, "%s\n", message.c_str()); \
      check_exit(); \
    } \
  } \
  (void)0

bool gpu_error_(cudaError_t result, const std::string& stmt)
{
	if (result == cudaSuccess)
		return false;

	char err[1024];
	sprintf(err,
		"CUDA error at %s: %s: %s",
		stmt.c_str(),
		cudaGetErrorName(result),
		cudaGetErrorString(result));
	std::string message(err);
	fprintf(stderr, "%s\n", message.c_str());
	return true;
}
#else
#	define cuda_assert(stmt) ((void)0)
#   define gpu_error_(result, stmt) false
#endif

#define gpu_error(stmt) gpu_error_(stmt, #stmt)

void gpu_error_message(const std::string& message)
{
	fprintf(stderr, "%s\n", message.c_str());
}

void cuda_set_device()
{
	cuda_assert(cudaSetDevice(0));
}

void setup_texture(bool use_gl)
{
	cuda_set_device();

#ifdef WITH_CLIENT_EPOXY
	if (use_gl) {
		GLuint pboIds[1];      // IDs of PBO
		GLuint textureIds[1];  // ID of texture

		glGenTextures(1, textureIds);
		g_textureId = textureIds[0];

		glBindTexture(GL_TEXTURE_2D, g_textureId);
		//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
		//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

		//glTexImage2D(GL_TEXTURE_2D,
		//	0,
		//	GL_RGBA8,
		//	g_renderengine_data.width,
		//	g_renderengine_data.height,
		//	0,
		//	GL_RGBA,
		//	GL_UNSIGNED_BYTE,
		//	NULL);

//		glTexImage2D(GL_TEXTURE_2D,
//			0,
//
//#ifdef TCP_PIX_SIZE_F32
//			GL_RGBA,
//#elif defined(TCP_PIX_SIZE_U16)
//			GL_RGBA16F,
//#else //TCP_PIX_SIZE_U8
//			GL_RGBA,
//#endif
//
//			g_renderengine_data.width,
//			g_renderengine_data.height,
//			0,
//			GL_RGBA,
//#ifdef TCP_PIX_SIZE_F32
//			GL_FLOAT,
//#elif defined(TCP_PIX_SIZE_U16)
//			GL_HALF_FLOAT,
//#else //TCP_PIX_SIZE_U8
//			GL_UNSIGNED_BYTE,
//#endif
//			NULL);
		if (PIX_SIZE == TCP_PIX_SIZE_F32) {
			glTexImage2D(GL_TEXTURE_2D,
				0,
				GL_RGBA,
				g_renderengine_data.width,
				g_renderengine_data.height,
				0,
				GL_RGBA,
				GL_FLOAT,
				NULL);
		}
		else if (PIX_SIZE == TCP_PIX_SIZE_U16) {
			glTexImage2D(GL_TEXTURE_2D,
				0,
				GL_RGBA16F,
				g_renderengine_data.width,
				g_renderengine_data.height,
				0,
				GL_RGBA,
				GL_HALF_FLOAT,
				NULL);
		}
		else { // TCP_PIX_SIZE_U8
			glTexImage2D(GL_TEXTURE_2D,
				0,
				GL_RGBA,
				g_renderengine_data.width,
				g_renderengine_data.height,
				0,
				GL_RGBA,
				GL_UNSIGNED_BYTE,
				NULL);
		}

		glBindTexture(GL_TEXTURE_2D, 0);

		glGenBuffers(1, pboIds);
		g_bufferId = pboIds[0];

		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, g_bufferId);

		glBufferData(GL_PIXEL_UNPACK_BUFFER,
			(size_t)g_renderengine_data.width * g_renderengine_data.height * 4 * PIX_SIZE,
			0,
			GL_DYNAMIC_COPY);

		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);

		cuda_assert(cudaGLRegisterBufferObject(g_bufferId));
		//cuda_assert(cudaGLMapBufferObject((void**)&g_pixels_buf_d, g_bufferId));
	}
#endif

	cuda_assert(cudaMalloc(&g_pixels_buf_recv_d, (size_t)g_renderengine_data.width * g_renderengine_data.height * 4 * PIX_SIZE));	
	printf("Setup texture %d x %d, Pointer: %lld (Size: %lld)\n", g_renderengine_data.width, g_renderengine_data.height, (size_t)g_pixels_buf_recv_d, (size_t)g_renderengine_data.width * g_renderengine_data.height * 4 * PIX_SIZE);
}

void free_texture(bool use_gl)
{
	cuda_set_device();

#ifdef WITH_CLIENT_EPOXY
	//cuda_assert(cudaGLUnmapBufferObject(g_bufferId));

	if (use_gl) {
		cuda_assert(cudaGLUnregisterBufferObject(g_bufferId));
	}
#endif

	printf("Free texture Pointer: %lld\n", (size_t)g_pixels_buf_recv_d);
	cuda_assert(cudaFree(g_pixels_buf_recv_d));	

#ifdef WITH_CLIENT_EPOXY
	if (use_gl) {
		glDeleteFramebuffers(1, &g_bufferId);
		glDeleteTextures(1, &g_textureId);
	}
#endif
}

void to_ortho(bool use_gl)
{
#ifdef WITH_CLIENT_EPOXY
	if (use_gl) {
		// set viewport to be the entire window
		glViewport(0, 0, (GLsizei)g_renderengine_data.width, (GLsizei)g_renderengine_data.height);

		// set orthographic viewing frustum
		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();

		glOrtho(0, 1, 0, 1, -1, 1);

		//glOrtho(0, 0.5, 0, 1, -1, 1);
		//glOrtho(0.5, 1, 0, 1, -1, 1);

		// switch to modelview matrix in order to set scene
		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();
	}
#endif
}

void draw_texture_internal(bool use_gl)
{
	cuda_set_device();
#ifdef WITH_CLIENT_EPOXY
	if (use_gl) {
		cuda_assert(cudaGLMapBufferObject((void**)&g_pixels_buf_d, g_bufferId));
		cuda_assert(cudaMemcpy(g_pixels_buf_d, g_pixels_buf_recv_d, (size_t)g_renderengine_data.width * g_renderengine_data.height * 4 * PIX_SIZE,
			cudaMemcpyDeviceToDevice));
		cuda_assert(cudaGLUnmapBufferObject(g_bufferId));

		//download texture from pbo
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, g_bufferId);
		glBindTexture(GL_TEXTURE_2D, g_textureId);
//		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, g_renderengine_data.width, g_renderengine_data.height,
//			GL_RGBA,
//
//#ifdef TCP_PIX_SIZE_F32
//			GL_FLOAT,
//#elif defined(TCP_PIX_SIZE_U16)
//			GL_HALF_FLOAT,
//#else //TCP_PIX_SIZE_U8
//			GL_UNSIGNED_BYTE,
//#endif
//
//			NULL);
		if (PIX_SIZE == TCP_PIX_SIZE_F32) {
			glTexSubImage2D(GL_TEXTURE_2D,
				0,
				0,
				0,
				g_renderengine_data.width,
				g_renderengine_data.height,
				GL_RGBA,
				GL_FLOAT,
				NULL);
		}
		else if (PIX_SIZE == TCP_PIX_SIZE_U16) {
			glTexSubImage2D(GL_TEXTURE_2D,
				0,
				0,
				0,
				g_renderengine_data.width,
				g_renderengine_data.height,
				GL_RGBA,
				GL_HALF_FLOAT,
				NULL);
		}
		else { // TCP_PIX_SIZE_U8
			glTexSubImage2D(GL_TEXTURE_2D,
				0,
				0,
				0,
				g_renderengine_data.width,
				g_renderengine_data.height,
				GL_RGBA,
				GL_UNSIGNED_BYTE,
				NULL);
		}

		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, g_textureId);
		//glBindBuffer(GL_PIXEL_UNPACK_BUFFER, g_bufferId);
		////glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);

		//return;

		////glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

		//// bind the texture and PBO
		//glBindTexture(GL_TEXTURE_2D, g_textureId);
		//glBindBuffer(GL_PIXEL_UNPACK_BUFFER, g_bufferId);

		//// copy pixels from PBO to texture object
		//// use offset instead of pointer.
		//glTexSubImage2D(GL_TEXTURE_2D,
		//	0,
		//	0,
		//	0,
		//	g_renderengine_data.width,
		//	g_renderengine_data.height,
		//	GL_RGBA,
		//	GL_UNSIGNED_BYTE,
		//	0);

		//glBindBuffer(GL_ARRAY_BUFFER, 0);
		//glBindTexture(GL_TEXTURE_2D, 0);
	}
#endif
}

void draw_texture() {
	draw_texture_internal(true);
}

//////////////////////////
void set_frame(int frame)
{
	g_renderengine_data.frame = frame;
}

void set_resolution(int width, int height)
{
	g_renderengine_data.width = width;
	g_renderengine_data.height = height;
}

void resize_internal(int width, int height, bool use_gl)
{
	if (width == g_renderengine_data.width && height == g_renderengine_data.height && g_pixels_buf)
		return;

	cuda_set_device();

	if (g_pixels_buf)
	{		
		free_texture(use_gl);
		cuda_assert(cudaFreeHost(g_pixels_buf));
	}

	g_renderengine_data.width = width;
	g_renderengine_data.height = height;

	cuda_assert(cudaHostAlloc((void**)&g_pixels_buf, (size_t)width * height * PIX_SIZE * 4, cudaHostAllocMapped));

	//int* size = (int*)&g_renderengine_data.width;
	//g_renderengine_data.width = width;
	//g_renderengine_data.height = height;
	setup_texture(use_gl);
}

void resize(int width, int height)
{
	resize_internal(width, height, true);
}

int recv_pixels_data()
{  
	cuda_set_device();

	if (USE_GPUJPEG) {
		//#ifdef TCP_PIX_SIZE_F32
		//	int format = 2;
		//#elif defined(TCP_PIX_SIZE_U16)
		//	int format = 1;
		//#else //TCP_PIX_SIZE_U8
		int format = 0;
		//#endif
		if (PIX_SIZE == TCP_PIX_SIZE_F32) {
			int format = 2;
		}
		else if (PIX_SIZE == TCP_PIX_SIZE_U16) {
			int format = 1;
		}
		else { //TCP_PIX_SIZE_U8
			int format = 0;
		}

		tcpConnection.recv_gpujpeg(
			(char*)g_pixels_buf_recv_d, (char*)g_pixels_buf, g_renderengine_data.width, g_renderengine_data.height, format);
	}
	else {
		tcpConnection.recv_data_data((char*)g_pixels_buf,
			g_renderengine_data.width * g_renderengine_data.height * PIX_SIZE * 4 /*, false*/);

		cuda_assert(cudaMemcpy(g_pixels_buf_recv_d, //g_pixels_buf_d,
			g_pixels_buf,
			g_renderengine_data.width * g_renderengine_data.height * PIX_SIZE * 4,
			cudaMemcpyHostToDevice));  // cudaMemcpyDefault gpuMemcpyHostToDevice

		//current_samples = ((int*)g_pixels_buf)[0];
	}

	tcpConnection.recv_data_data((char*)&g_hs_data_state, sizeof(BRaaSHPCDataState));

#ifdef _WIN32
	displayFPS(1, get_current_samples());
#endif	

	return 0;
}

int send_pixels_data()
{  
	cuda_set_device();

	if (USE_GPUJPEG) {

		//#ifdef TCP_PIX_SIZE_F32
		//	int format = 2;
		//#elif defined(TCP_PIX_SIZE_U16)
		//	int format = 1;
		//#else //TCP_PIX_SIZE_U8
		int format = 0;
		//#endif
		if (PIX_SIZE == TCP_PIX_SIZE_F32) {
			int format = 2;
		}
		else if (PIX_SIZE == TCP_PIX_SIZE_U16) {
			int format = 1;
		}
		else { //TCP_PIX_SIZE_U8
			int format = 0;
		}

		tcpConnection.send_gpujpeg(
			(char*)g_pixels_buf_recv_d, (char*)g_pixels_buf, g_renderengine_data.width, g_renderengine_data.height, format);
	}
	else {
		//cuda_assert(cudaMemcpy(g_pixels_buf_recv_d, //g_pixels_buf_d,
		//	g_pixels_buf,
		//	g_renderengine_data.width * g_renderengine_data.height * PIX_SIZE * 4,
		//	cudaMemcpyHostToDevice));  // cudaMemcpyDefault gpuMemcpyHostToDevice

		tcpConnection.send_data_data((char*)g_pixels_buf,
			g_renderengine_data.width * g_renderengine_data.height * PIX_SIZE * 4 /*, false*/);

		//current_samples = ((int*)g_pixels_buf)[0];
	}

	tcpConnection.send_data_data((char*)&g_hs_data_state, sizeof(BRaaSHPCDataState));

#ifdef _WIN32
	displayFPS(1, get_current_samples());
#endif	

	return 0;
}

int send_cam_data()
{
	tcpConnection.send_data_data((char*)&g_renderengine_data, sizeof(renderengine_data));

	return 0;
}

int recv_cam_data()
{
	//int width_old = g_renderengine_data.width;
	//int height_old = g_renderengine_data.height;

	//tcpConnection.recv_data_data((char*)&g_renderengine_data, sizeof(renderengine_data));
	tcpConnection.recv_data_data((char*)&g_renderengine_data_recv, sizeof(renderengine_data));

	int width = g_renderengine_data_recv.width;
	int height = g_renderengine_data_recv.height;

	//g_renderengine_data.width = width_old;
	//g_renderengine_data.height = height_old;

	resize_internal(width, height, false);

	int compare = memcmp((char*)&g_renderengine_data, (char*)&g_renderengine_data_recv, sizeof(renderengine_data));
	memcpy((char*)&g_renderengine_data, (char*)&g_renderengine_data_recv, sizeof(renderengine_data));

	return compare;
}

void reset()
{
	renderengine_data rd;
	rd.reset = 1;

	tcpConnection.send_data_data((char*)&rd, sizeof(renderengine_data));
}

void send_braas_hpc_renderengine_data_render(const char* data, int size)
{
	tcpConnection.send_data_data((char*)&size, sizeof(int));
	if(size > 0)
		tcpConnection.send_data_data((char*)data, size);
}

void recv_braas_hpc_renderengine_data(const char* data, int size)
{
	tcpConnection.recv_data_data((char*)data, size);
}

//void braas_hpc_renderengine_init(const char* server,
//	int port_cam,
//	int port_data)
//{
//	init_sockets_cam(server, port_cam, port_data);
//}

void get_braas_hpc_renderengine_range(
	void* world_bounds_spatial_lower,
	void* world_bounds_spatial_upper,
	void* scalars_range)
{
	memcpy((char*)world_bounds_spatial_lower, g_hs_data_state.world_bounds_spatial_lower, sizeof(float) * 3);
	memcpy((char*)world_bounds_spatial_upper, g_hs_data_state.world_bounds_spatial_upper, sizeof(float) * 3);
	memcpy((char*)scalars_range, g_hs_data_state.scalars_range, sizeof(float) * 2);
}

void set_braas_hpc_renderengine_range(
	void* world_bounds_spatial_lower,
	void* world_bounds_spatial_upper,
	void* scalars_range,
	int samples,
	float fps
	)
{
	memcpy(g_hs_data_state.world_bounds_spatial_lower, (char*)world_bounds_spatial_lower, sizeof(float) * 3);
	memcpy(g_hs_data_state.world_bounds_spatial_upper, (char*)world_bounds_spatial_upper, sizeof(float) * 3);
	memcpy(g_hs_data_state.scalars_range, (char*)scalars_range, sizeof(float) * 2);
	g_hs_data_state.samples = samples;
	g_hs_data_state.fps = fps;
}

void set_timestep(int timestep)
{
	tcpConnection.set_port_offset(timestep);
}

int get_pixsize()
{
	if (PIX_SIZE == TCP_PIX_SIZE_F32) {
		return 32;
	}
	else if (PIX_SIZE == TCP_PIX_SIZE_U16) {
		return 16;
	}
	else { // TCP_PIX_SIZE_U8
		return 8;
	}	
}

void set_pixsize(int ps)
{
	if (ps == 8) {
		PIX_SIZE = TCP_PIX_SIZE_U8;
	}
	else if (ps == 32) {
		PIX_SIZE = TCP_PIX_SIZE_F32;
	}
	else if (ps == 16) {
		PIX_SIZE = TCP_PIX_SIZE_U16;
	}
	else {
		printf("set_pixsize: Unsupported pixel size %d, using 8 bits\n", ps);
		PIX_SIZE = TCP_PIX_SIZE_U8;
	}
}

int is_gpujpeg() {
	return USE_GPUJPEG ? 1 : 0;
}

int enable_gpujpeg(int enabled)
{
#ifdef WITH_CLIENT_GPUJPEG
	USE_GPUJPEG = (enabled != 0);
	return 0;
#else
	printf("enable_gpujpeg: Not compiled with GPUJPEG support\n");
	return -1;
#endif
}

void client_init(const char* server,
	int port,
	//int port_data,
	int w,
	int h)
{
	//init_sockets_cam(server, port_cam, port_data);
	//setenv("SOCKET_SERVER_NAME_CAM", server, 1);
	//setenv("SOCKET_SERVER_NAME_DATA", server, 1);

	//char stemp[128];
	//sprintf(stemp, "%d", port_cam);
	//setenv("SOCKET_SERVER_PORT_CAM", stemp, 1);
	//sprintf(stemp, "%d", port_data);
	//setenv("SOCKET_SERVER_PORT_DATA", stemp, 1);

	//g_renderengine_data.step_samples = step_samples;
	//strcpy(g_renderengine_data.filename, filename);

	tcpConnection.init_sockets_data(server, port, false);
	//gladLoadGL();
	
	memset(&g_renderengine_data, 0, sizeof(renderengine_data));
	memset(&g_hs_data_state, 0, sizeof(BRaaSHPCDataState));

	resize_internal(w, h, true);
}

void server_init(const char* server,
	int port,
	int w,
	int h)
{
	tcpConnection.init_sockets_data(server, port, true);

	memset(&g_renderengine_data, 0, sizeof(renderengine_data));
	memset(&g_hs_data_state, 0, sizeof(BRaaSHPCDataState));

	resize_internal(w, h, false);
}

void client_close_connection()
{
	tcpConnection.client_close();
	tcpConnection.server_close();
}

void server_close_connection()
{
	tcpConnection.client_close();
	tcpConnection.server_close();
}

void set_camera(void* view_martix,
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
	int view_perspective)
{
	memcpy(
		(char*)g_renderengine_data.cam.transform_inverse_view_matrix, view_martix, sizeof(float) * 12);

	g_renderengine_data.cam.lens = lens;
	g_renderengine_data.cam.clip_start = nearclip;
	g_renderengine_data.cam.clip_end = farclip;

	g_renderengine_data.cam.sensor_width = sensor_width;
	g_renderengine_data.cam.sensor_height = sensor_height;
	g_renderengine_data.cam.sensor_fit = sensor_fit;

	g_renderengine_data.cam.view_camera_zoom = view_camera_zoom;
	g_renderengine_data.cam.view_camera_offset[0] = view_camera_offset0;
	g_renderengine_data.cam.view_camera_offset[1] = view_camera_offset1;
	g_renderengine_data.cam.use_view_camera = use_view_camera;
	g_renderengine_data.cam.shift_x = shift_x;
	g_renderengine_data.cam.shift_y = shift_y;
	g_renderengine_data.cam.view_perspective = view_perspective;
}

void get_camera(void* view_martix,
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
	int* view_perspective)
{
	memcpy(
		(char*)view_martix, g_renderengine_data.cam.transform_inverse_view_matrix, sizeof(float) * 12);

	*lens = g_renderengine_data.cam.lens;
	*nearclip = g_renderengine_data.cam.clip_start;
	*farclip = g_renderengine_data.cam.clip_end;

	*sensor_width = g_renderengine_data.cam.sensor_width;
	*sensor_height = g_renderengine_data.cam.sensor_height;
	*sensor_fit = g_renderengine_data.cam.sensor_fit;
	*view_camera_zoom = g_renderengine_data.cam.view_camera_zoom;
	*view_camera_offset0 = g_renderengine_data.cam.view_camera_offset[0];
	*view_camera_offset1 = g_renderengine_data.cam.view_camera_offset[1];
	*use_view_camera = g_renderengine_data.cam.use_view_camera;
	*shift_x = g_renderengine_data.cam.shift_x;
	*shift_y = g_renderengine_data.cam.shift_y;
	*view_perspective = g_renderengine_data.cam.view_perspective;
}

//int get_samples()
//{
//	int* samples = (int*)&g_renderengine_data.step_samples;
//	return samples[0];
//}

int get_current_samples()
{
	return g_hs_data_state.samples;
}

float get_remote_fps()
{
	return g_hs_data_state.fps;
}

float get_local_fps()
{
	return local_fps;
}

void get_pixels(void* pixels)
{
	size_t pix_type_size = PIX_SIZE * 4; // sizeof(char) * 4;
	memcpy(pixels, (char*)g_pixels_buf, g_renderengine_data.width * g_renderengine_data.height * pix_type_size);
}

void set_pixels(void* pixels, bool device)
{
	cuda_set_device();

	size_t pix_type_size = PIX_SIZE * 4; // sizeof(char) * 4;

	if (device) {
		//printf("Set pixels device to device Pointer: %lld -> %lld (Size: %lld)\n", (size_t)pixels, (size_t)g_pixels_buf_recv_d, (size_t)g_renderengine_data.width * g_renderengine_data.height * pix_type_size);

		cuda_assert(cudaMemcpy(
			g_pixels_buf_recv_d,
			pixels,
			(size_t)g_renderengine_data.width * g_renderengine_data.height * pix_type_size,
			cudaMemcpyDeviceToDevice));  // cudaMemcpyDefault gpuMemcpyHostToDevice
	}
	else {
		if (USE_GPUJPEG) {
			cuda_assert(cudaMemcpy(
				g_pixels_buf_recv_d,
				pixels,
				(size_t)g_renderengine_data.width * g_renderengine_data.height * pix_type_size,
				cudaMemcpyHostToDevice));  // cudaMemcpyDefault gpuMemcpyHostToDevice
		}
		else {
			memcpy((char*)g_pixels_buf, pixels, g_renderengine_data.width * g_renderengine_data.height * pix_type_size);
		}
	}
}

unsigned long long int get_gpu_buffer() {
	return (unsigned long long int)g_pixels_buf_recv_d;
}

int get_texture_id()
{
#ifdef WITH_CLIENT_EPOXY
	return g_textureId;
#else
	return -1;
#endif
}

int com_error() {
	return tcpConnection.is_error();
}

int get_width() {
	return g_renderengine_data.width;
}

int get_height() {
	return g_renderengine_data.height;
}


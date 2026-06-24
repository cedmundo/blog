---
title: "Using slang with SDL3 (SDLGPU): Part 4 - Vertex buffers and attributes"
date: 2026-06-23T21:16:38-06:00
draft: true
---

## Introduction

This post belongs to a series, you can find other parts [here](/)

The source code will be available on
[github.com/cedmundo/slang-sdl3-example](https://github.com/cedmundo/slang-sdl3-example),
feel free to fork it and use it as you find suitable in your projects.

## Vertex buffers and attributes

Passing vertex buffers is the same as other shader languages, you must only specify in slang the correct
layout and you'll be fine. Let's update our code to add a `SingleQuad` object that binds vertex data and
renders using an index buffer.

Let's add a `quad.h`:
```c
#ifndef QUAD_H
#define QUAD_H

#include <SDL3/SDL_gpu.h>

typedef struct {
  float time;
} QuadFUniformData;

typedef struct {
  SDL_GPUBuffer *buffer;
  SDL_GPUTransferBuffer *transfer_buffer;
  SDL_GPUBufferBinding buffer_bindings[3];
  Uint32 indices_count;
  QuadFUniformData frag_uniforms;
  bool uploaded;
} SingleQuad;

SingleQuad *CreateSingleQuad(SDL_GPUDevice *device);
void DestroySingleQuad(SingleQuad *quad, SDL_GPUDevice *device);
void UploadSingleQuad(SingleQuad *quad, SDL_GPUDevice *device,
                      SDL_GPUCopyPass *copy_pass);
void UpdateSingleQuad(SingleQuad *quad);
void RenderSingleQuad(SingleQuad *quad, SDL_GPUCommandBuffer *cmdbuf,
                      SDL_GPURenderPass *render_pass);
#endif /* QUAD_H */
```

Here we can see a lot of new operations:

* Create/Destroy SingleQuad help to manage resources of the object.
* UploadSingleQuad will push the static data into the GPU.
* RenderSingleQuad will present the quad on the render pass.

Also, we are moving the Uniforms here, we will remove them from main later. SingleQuad
contains mostly a single big buffer with its description:

1. GPU Buffer containing all vertex data plus index data [POS, COL, INDEX]
2. A transfer buffer to upload said data.
3. Buffer bindings that help offset the data within the GPU.
4. Index count and uniforms.
5. Uploaded flag to not upload the same data twice.

The implementation goes as follow in `quad.c`:

```c
// quad.c
#include "quad.h"

#include <SDL3/SDL_assert.h>
#include <SDL3/SDL_gpu.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_timer.h>

static const float v_pos_buffer[][3] = {
    {+0.5, +0.5, 0},
    {+0.5, -0.5, 0},
    {-0.5, +0.5, 0},
    {-0.5, -0.5, 0},
};

static const float v_col_buffer[][3] = {
    {1.0, 0.0, 0.0},
    {0.0, 1.0, 0.0},
    {0.0, 0.0, 1.0},
    {1.0, 1.0, 1.0},
};

// IMPORTANT: Either use U32 or U16
static const Uint32 quad_indices[] = {
    0, 1, 2, 2, 1, 3,
};

#define V_INDEX_COUNT (sizeof(quad_indices) / sizeof(unsigned))
#define QUAD_BUFFER_SIZE                                                       \
  (sizeof(v_pos_buffer) + sizeof(v_col_buffer) + sizeof(quad_indices))

#define V_POS_BINDING_IDX (0)
#define V_COL_BINDING_IDX (1)
#define INDICES_BINDING_IDX (2)

SingleQuad *CreateSingleQuad(SDL_GPUDevice *device) {
  SingleQuad *quad = SDL_malloc(sizeof(SingleQuad));
  if (quad == NULL) {
    return quad;
  }

  // This is going to be used to hold the data in GPU
  SDL_GPUBufferCreateInfo buffer_create_info = {0};
  buffer_create_info.usage = SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ |
                             SDL_GPU_BUFFERUSAGE_VERTEX |
                             SDL_GPU_BUFFERUSAGE_INDEX;
  buffer_create_info.size = QUAD_BUFFER_SIZE;

  quad->buffer = SDL_CreateGPUBuffer(device, &buffer_create_info);
  if (quad->buffer == NULL) {
    DestroySingleQuad(quad, device);
    return NULL;
  }

  // This is going to be used to transfer the data into GPU
  SDL_GPUTransferBufferCreateInfo create_info = {0};
  create_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
  create_info.size = QUAD_BUFFER_SIZE;
  quad->transfer_buffer = SDL_CreateGPUTransferBuffer(device, &create_info);
  if (quad->transfer_buffer == NULL) {
    DestroySingleQuad(quad, device);
    return NULL;
  }

  // First part of buffer is positions:
  quad->buffer_bindings[V_POS_BINDING_IDX] = (SDL_GPUBufferBinding){
      .buffer = quad->buffer,
      .offset = 0,
  };

  // Second part of buffer is colors:
  quad->buffer_bindings[V_COL_BINDING_IDX] = (SDL_GPUBufferBinding){
      .buffer = quad->buffer,
      .offset = sizeof(v_pos_buffer),
  };

  // Third part of buffer are indices:
  quad->buffer_bindings[INDICES_BINDING_IDX] = (SDL_GPUBufferBinding){
      .buffer = quad->buffer,
      .offset = sizeof(v_pos_buffer) + sizeof(v_col_buffer),
  };

  quad->indices_count = V_INDEX_COUNT;
  return quad;
}

void DestroySingleQuad(SingleQuad *quad, SDL_GPUDevice *device) {
  if (quad == NULL) {
    return;
  }

  if (quad->buffer != NULL) {
    SDL_ReleaseGPUBuffer(device, quad->buffer);
  }

  if (quad->transfer_buffer != NULL) {
    SDL_ReleaseGPUTransferBuffer(device, quad->transfer_buffer);
  }

  SDL_free(quad);
}

void UploadSingleQuad(SingleQuad *quad, SDL_GPUDevice *device,
                      SDL_GPUCopyPass *copy_pass) {
  if (quad->uploaded) {
    return;
  }

  void *gpu_staging =
      SDL_MapGPUTransferBuffer(device, quad->transfer_buffer, false);
  {
    // buffer + 0: positions
    SDL_memcpy(gpu_staging, v_pos_buffer, sizeof(v_pos_buffer));

    // buffer + v_pos: colors
    SDL_memcpy(gpu_staging + sizeof(v_pos_buffer), v_col_buffer,
               sizeof(v_col_buffer));

    // buffer + v_pos + v_col: indices
    SDL_memcpy(gpu_staging + sizeof(v_pos_buffer) + sizeof(v_col_buffer),
               quad_indices, sizeof(quad_indices));

    SDL_GPUTransferBufferLocation src = {
        .transfer_buffer = quad->transfer_buffer,
        .offset = 0,
    };

    SDL_GPUBufferRegion dst = {
        .buffer = quad->buffer,
        .offset = 0,
        .size = QUAD_BUFFER_SIZE,
    };

    SDL_UploadToGPUBuffer(copy_pass, &src, &dst, false);
  }
  SDL_UnmapGPUTransferBuffer(device, quad->transfer_buffer);
  quad->uploaded = true;
}

void UpdateSingleQuad(SingleQuad *quad) {
  quad->frag_uniforms.time = (float)SDL_GetTicks() / 1000.0;
}

void RenderSingleQuad(SingleQuad *quad, SDL_GPUCommandBuffer *cmdbuf,
                      SDL_GPURenderPass *render_pass) {
  SDL_BindGPUVertexBuffers(render_pass, 0, quad->buffer_bindings, 2); // POS,COL
  SDL_BindGPUIndexBuffer(render_pass,
                         &quad->buffer_bindings[INDICES_BINDING_IDX],
                         SDL_GPU_INDEXELEMENTSIZE_32BIT);
  SDL_PushGPUFragmentUniformData(cmdbuf, 0, &quad->frag_uniforms,
                                 sizeof(QuadFUniformData));
  SDL_DrawGPUIndexedPrimitives(render_pass, quad->indices_count, 1, 0, 0, 1);
}
```

Phew, thats quite a lot of code, well, at least the explanation is fairly simple:

1. We use three static arrays to simulate data, this data can from anywhere
but usually it is read from files in disc.
2. CreateSingleQuad does not only allocate the memory resources for the SingleQuad
but also initializes the GPU objects.
3. DestroySingleQuad also does the same, aside from memory operations,
releases the GPU resources allocated by CreateSingleQuad.
4. UploadSingleQuad must be executed within a CopyPass, this will perform
the copy of actual data into the GPU.
5. UpdateSingleQuad just updates the uniform data (time, transform, etc).
6. RenderSingleQuad performs the actual rendering of the data, basically uses
everything that has been setup.

Don't forget to add `quad.c` to `CMakeLists.txt`:

```
target_sources(slang-sdl3-example PRIVATE shader.c quad.c main.c) # HERE: add quad.c
```

Now, let's update `shader.c`, because the pipeline creation has to reflect the buffer
and attribute states, this must be done right after `color_target_info` creation:

```c
  // shader.c
  // ...

  // finally we can create the actual pipeline
  SDL_GPUGraphicsPipelineCreateInfo pipeline_create_info = {0};
  pipeline_create_info.target_info = color_target_info;
  pipeline_create_info.fragment_shader = frag_shader;
  pipeline_create_info.vertex_shader = vert_shader;
  pipeline_create_info.primitive_type = SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
  pipeline_create_info.vertex_input_state = (SDL_GPUVertexInputState){
      .num_vertex_attributes = 2,
      .vertex_attributes =
          (SDL_GPUVertexAttribute[]){
              {.buffer_slot = 0,
               .format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
               .location = 0,
               .offset = 0},
              {.buffer_slot = 1,
               .format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
               .location = 1,
               .offset = 0},
          },
      .num_vertex_buffers = 2,
      .vertex_buffer_descriptions =
          (SDL_GPUVertexBufferDescription[]){
              {.slot = 0,
               .input_rate = SDL_GPU_VERTEXINPUTRATE_VERTEX,
               .instance_step_rate = 0,
               .pitch = sizeof(float) * 3},
              {.slot = 1,
               .input_rate = SDL_GPU_VERTEXINPUTRATE_VERTEX,
               .instance_step_rate = 0,
               .pitch = sizeof(float) * 3},
          },
  };
  pipeline = SDL_CreateGPUGraphicsPipeline(device, &pipeline_create_info);
  // ...
```

Here we are using the format for the vertex position and color, note that they
must match the layout used in the static arrays within `quad.c`.

Another thing that we must do is to update `main.c` since we are not directly
rending the shaders anymore.

```c
#include <SDL3/SDL_assert.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_gpu.h>
#include <SDL3/SDL_init.h>
#include <SDL3/SDL_log.h>
#include <SDL3/SDL_pixels.h>
#include <SDL3/SDL_rect.h>
#include <SDL3/SDL_timer.h>
#include <SDL3/SDL_video.h>

#define SDL_MAIN_USE_CALLBACKS
#include <SDL3/SDL_main.h>

#include "quad.h"
#include "shader.h"

#define WINDOW_TITLE "Slang + SDLGPU Example"
#define WINDOW_HEIGHT 500
#define WINDOW_WIDTH 500

typedef struct {
  SDL_Window *window;
  SDL_GPUDevice *device;
  SDL_GPUViewport viewport;

  // our resources
  SDL_GPUGraphicsPipeline *flat_color_pipeline;
  SingleQuad *quad;
} ExampleApp;

SDL_AppResult SDL_AppInit(void **appstate, int argc, char *argv[]) {
  (void)argc;
  (void)argv;

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    SDL_Log("Error: SDL_Init(): %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  ExampleApp *app = SDL_malloc(sizeof(ExampleApp));
  if (!app) {
    SDL_OutOfMemory();
    return SDL_APP_FAILURE;
  }

  *appstate = app;
  app->window = SDL_CreateWindow(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, 0);
  if (app->window == NULL) {
    SDL_Log("Error: SDL_CreateWindow(): %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }
  app->viewport =
      (SDL_GPUViewport){.x = 0, .y = 0, .w = WINDOW_WIDTH, .h = WINDOW_HEIGHT};

  app->device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_SPIRV, true, NULL);
  if (app->device == NULL) {
    SDL_Log("Error: SDL_CreateGPUDevice(): %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  if (!SDL_ClaimWindowForGPUDevice(app->device, app->window)) {
    SDL_Log("Error: SDL_ClaimWindowForGPUDevice(): %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  // create resources
  ShaderOptions vert_shader_opts = {0};
  vert_shader_opts.filename = "flat-color.vs.spirv";
  vert_shader_opts.stage = SDL_GPU_SHADERSTAGE_VERTEX;

  ShaderOptions frag_shader_opts = {0};
  frag_shader_opts.filename = "flat-color.fs.spirv";
  frag_shader_opts.stage = SDL_GPU_SHADERSTAGE_FRAGMENT;
  frag_shader_opts.uniform_buffer_count = 1;

  app->flat_color_pipeline = CreatePipeline(app->device, app->window,
                                            vert_shader_opts, frag_shader_opts);
  if (app->flat_color_pipeline == NULL) {
    SDL_Log("Error: failed to create pipeline: %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  app->quad = CreateSingleQuad(app->device);
  if (app->quad == NULL) {
    SDL_Log("Error: failed to create quad: %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  // Initial upload (static data):
  SDL_GPUCommandBuffer *cmdbuf = SDL_AcquireGPUCommandBuffer(app->device);
  if (cmdbuf == NULL) {
    SDL_Log("Error: failed to get initial command buffer: %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  SDL_GPUCopyPass *static_data_copy_pass = SDL_BeginGPUCopyPass(cmdbuf);
  {
    if (static_data_copy_pass == NULL) {
      SDL_Log("Error: failed to get initial copy pass: %s", SDL_GetError());
      return SDL_APP_FAILURE;
    }

    UploadSingleQuad(app->quad, app->device, static_data_copy_pass);
  }
  SDL_EndGPUCopyPass(static_data_copy_pass);
  SDL_SubmitGPUCommandBuffer(cmdbuf);
  return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void *appstate) {
  ExampleApp *app = (ExampleApp *)appstate;
  SDL_assert(app != NULL);

  // Update everything, including camera, positions, etc...
  UpdateSingleQuad(app->quad);

  // Render everything...
  SDL_GPUCommandBuffer *cmdbuf = SDL_AcquireGPUCommandBuffer(app->device);
  if (cmdbuf == NULL) {
    SDL_Log("Error: SDL_AcquireGPUCommandBuffer(): %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  SDL_GPUTexture *swapchain_texture = NULL;
  if (!SDL_WaitAndAcquireGPUSwapchainTexture(cmdbuf, app->window,
                                             &swapchain_texture, NULL, NULL)) {
    SDL_Log("Warning: could not acquire GPU swapchain texture");
  }

  if (swapchain_texture != NULL) {
    SDL_GPUColorTargetInfo color_target_info = {0};
    color_target_info.texture = swapchain_texture;
    color_target_info.clear_color = (SDL_FColor){0.2f, 0.2f, 0.5f, 1.0f};
    color_target_info.load_op = SDL_GPU_LOADOP_CLEAR;
    color_target_info.store_op = SDL_GPU_STOREOP_STORE;

    SDL_GPURenderPass *render_pass =
        SDL_BeginGPURenderPass(cmdbuf, &color_target_info, 1, NULL);
    {
      SDL_SetGPUViewport(render_pass, &app->viewport);

      // Bind flat color pipeline
      SDL_BindGPUGraphicsPipeline(render_pass, app->flat_color_pipeline);
      {
        // Render the quad using the bound pipeline
        RenderSingleQuad(app->quad, cmdbuf, render_pass);
      }
      SDL_BindGPUGraphicsPipeline(render_pass, NULL);
    }
    SDL_EndGPURenderPass(render_pass);
  }

  SDL_SubmitGPUCommandBuffer(cmdbuf);
  return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event) {
  ExampleApp *app = (ExampleApp *)appstate;
  SDL_assert(app != NULL);

  switch (event->type) {
  case SDL_EVENT_QUIT:
    return SDL_APP_SUCCESS;
  case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
    if (event->window.windowID == SDL_GetWindowID(app->window)) {
      return SDL_APP_SUCCESS;
    }
    break;
  }
  return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void *appstate, SDL_AppResult result) {
  ExampleApp *app = (ExampleApp *)appstate;
  if (app == NULL) {
    return;
  }

  DestroySingleQuad(app->quad, app->device);
  SDL_ReleaseGPUGraphicsPipeline(app->device, app->flat_color_pipeline);
  SDL_DestroyGPUDevice(app->device);
  SDL_DestroyWindow(app->window);
  SDL_Log("Info: Terminated with result: %d", result);
}
```

An important note is that we are creating a copy pass during initialization,
this is because we want to push data to the GPU before rendering anything, this
can be changed, however, to pass data before rending during iteration, but it
is not needed here.

Also, we dropped everything that was using buffers and rendering, and we delegated
most of the responsabilities to `quad.c`.

A final warning is that, the pipeline only support those two attributes: position
and color, if you want to use more attributes you should be creating or modifing
the pipeline, which is not directly linked to the quad object, this entirely depends
on your design.

For the fun part, let's update the shaders:

Vertex shader `assets/shaders/flat-color.vs.slang` is actually smaller:

```hlsl
struct VSInput {
  float3 position : POSITION; // FROM ATTRIBUTE LAYOUT
  float3 color : COLOR; // FROM ATTIRBUTE LAYOUT
};

struct VSOutput {
  float4 position : SV_Position;
  float3 color;
};

[shader("vertex")]
VSOutput main(VSInput input) {
  VSOutput output;
  output.position = float4(input.position, 1.0f);
  output.color = input.color;
  return output;
}
```

Fragment shader `assets/shaders/flat-color.fs.slang` is also simpler:

```hlsl
struct UniformData {
  float time;
};

struct PSInput {
  float4 position : SV_Position;
  float3 color;
};

struct PSOutput {
  float4 color : SV_Target;
};

// https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader#remarks
layout(set = 3, binding = 0) ParameterBlock<UniformData> uniforms;

[shader("pixel")]
PSOutput main(PSInput input) {
  PSOutput output;
  float factor = (sin(uniforms.time) + 1) / 2;
  output.color = float4(input.color * factor, 1.0);
  return output;
}
```

To try the new changes, let's re-compile the shaders:

```
$ slangc assets/shaders/flat-color.vs.slang -o cmake-build-debug/flat-color.vs.spirv -entry main -target spirv
$ slangc assets/shaders/flat-color.fs.slang -o cmake-build-debug/flat-color.fs.spirv -entry main -target spirv
```

And then build and run the application again:

```
$ cmake -B cmake-build-debug -S . && cmake --build cmake-build-debug && ./cmake-build-debug/slang-sdl3-example
-- Configuring done
-- Generating done
-- Build files have been written to: /home/carlos/Projects/Misc/slang-sdl3-example/cmake-build-debug
Consolidate compiler generated dependencies of target slang-sdl3-example
[100%] Built target slang-sdl3-example
```

If everything was good, we should be seeing this:

![A window with blue background and a colored square oscilating from/to black](/images/slang-sdl3-example-4.gif)

Awesome! Now we talking, we got working Uniforms, Vertex Buffers and Attributes.

## Next steps

Now you can pass vertex buffers and setup attributes. Next part I'll show how to
bind textures and after that, how to bind custom data to graphic shaders. Finally,
I'll add a compute example to finish the series.

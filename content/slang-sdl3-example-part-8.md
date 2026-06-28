---
title: "Using slang with SDL3 (SDLGPU): Part 8 - Extras"
date: 2026-06-24T20:10:15-06:00
draft: false
---

## Introduction

This post belongs to a series, you can find other parts [here](/)

The source code will be available on
[github.com/cedmundo/slang-sdl3-example](https://github.com/cedmundo/slang-sdl3-example),
feel free to fork it and use it as you find suitable in your projects.

## Process assets with CMake

It is possible to compile our shaders and copy the resources to the build directory
everytime we compile the program, to do this. This can save a lot of time debugging
versions of those files. I usually add a custom rule to compile the slang shaders and
copy images, then I also add a depdendency in the main target.

Let's add a `assets/CMakeLists.txt`:

```cmake
add_custom_target(slang-sdl3-example-vs
    COMMAND slangc
      -target spirv
      -profile spirv_1_3
      -o ${CMAKE_BINARY_DIR}/flat-color.vs.spirv
      -entry main
      ${CMAKE_SOURCE_DIR}/assets/shaders/flat-color.vs.slang
    DEPENDS ${CMAKE_SOURCE_DIR}/assets/shaders/flat-color.vs.slang
    BYPRODUCTS ${CMAKE_BINARY_DIR}/flat-color.vs.spirv)

add_custom_target(slang-sdl3-example-fs
    COMMAND slangc
      -target spirv
      -profile spirv_1_3
      -o ${CMAKE_BINARY_DIR}/flat-color.fs.spirv
      -entry main
      ${CMAKE_SOURCE_DIR}/assets/shaders/flat-color.fs.slang
    DEPENDS ${CMAKE_SOURCE_DIR}/assets/shaders/flat-color.fs.slang
    BYPRODUCTS ${CMAKE_BINARY_DIR}/flat-color.fs.spirv)

add_custom_target(slang-sdl3-example-cs
    COMMAND slangc
      -target spirv
      -profile spirv_1_3
      -o ${CMAKE_BINARY_DIR}/quad-group.spirv
      -entry main
      ${CMAKE_SOURCE_DIR}/assets/shaders/quad-group.slang
    DEPENDS ${CMAKE_SOURCE_DIR}/assets/shaders/quad-group.slang
    BYPRODUCTS ${CMAKE_BINARY_DIR}/quad-group.spirv)

add_custom_target(slang-sdl3-example-texture
    COMMAND ${CMAKE_COMMAND} -E copy
      ${CMAKE_SOURCE_DIR}/assets/textures/quad.png
      ${CMAKE_BINARY_DIR}/quad.png
    DEPENDS ${CMAKE_SOURCE_DIR}/assets/textures/quad.png
    BYPRODUCTS ${CMAKE_BINARY_DIR}/quad.png)
```

If you are planning to use this approach in your project (I don't necessary recomend it when
it is more than 10 files), you can add a macro or function to add the targets when needed.

Also, don't forget to add the subdirectory and dependency on the main `CMakeLists.txt` file:

```cmake
cmake_minimum_required(VERSION 3.22)
project(slang-sdl3-example
  VERSION "1.0.0"
  DESCRIPTION "Example of slang with SDL3"
  LANGUAGES C)

# CMake options
set(CMAKE_C_STANDARD 11)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
include(FetchContent)

# Vendored dependencies
find_package(SDL3 REQUIRED CONFIG REQUIRED COMPONENTS SDL3)
FetchContent_Declare(
  SDL3_image
  GIT_REPOSITORY "https://github.com/libsdl-org/SDL_image.git"
  GIT_TAG "release-3.4.4"
)
FetchContent_MakeAvailable(SDL3_image)

# Custom target for shaders
add_subdirectory(assets)

# Main target
add_executable(slang-sdl3-example)
target_sources(slang-sdl3-example PRIVATE
  shader.c
  pipeline.c
  texture.c
  quad.c
  quad_group.c
  main.c)
target_link_libraries(slang-sdl3-example PRIVATE SDL3 SDL3_image-shared)

# Asset dependencies:
add_dependencies(slang-sdl3-example
  slang-sdl3-example-vs
  slang-sdl3-example-fs
  slang-sdl3-example-cs
  slang-sdl3-example-texture)
```

Another solution is to have a custom `python` script that processes the assets
accordingly, then create a custom rule in cmake to call that tool. This will be
maybe covered by other series in this blog, but I haven't planned it just yet.

## Creating the SDLGPU Device without warnings

When making this project (and others) I've been fighting agains this warnings:

```
[100%] Built target slang-sdl3-example
Validation Error: [ VUID-VkShaderModuleCreateInfo-pCode-08737 ] | MessageID = 0xa5625282
vkCreateShaderModule(): pCreateInfo->pCode (spirv-val produced an error):
Invalid SPIR-V binary version 1.3 for target environment SPIR-V 1.0 (under Vulkan 1.0 semantics).
The Vulkan spec states: If pCode is a pointer to SPIR-V code, pCode must adhere to the validation rules described by the Validation Rules within a Module section of the SPIR-V Environment appendix (https://vulkan.lunarg.com/doc/view/1.4.313.0/linux/antora/spec/latest/chapters/shaders.html#VUID-VkShaderModuleCreateInfo-pCode-08737)

Validation Error: [ VUID-VkShaderModuleCreateInfo-pCode-08737 ] | MessageID = 0xa5625282
vkCreateShaderModule(): pCreateInfo->pCode (spirv-val produced an error):
Invalid SPIR-V binary version 1.3 for target environment SPIR-V 1.0 (under Vulkan 1.0 semantics).
The Vulkan spec states: If pCode is a pointer to SPIR-V code, pCode must adhere to the validation rules described by the Validation Rules within a Module section of the SPIR-V Environment appendix (https://vulkan.lunarg.com/doc/view/1.4.313.0/linux/antora/spec/latest/chapters/shaders.html#VUID-VkShaderModuleCreateInfo-pCode-08737)

Validation Error: [ VUID-VkShaderModuleCreateInfo-pCode-08740 ] | MessageID = 0x6e224e9
vkCreateShaderModule(): SPIR-V Capability DrawParameters was declared, but one of the following requirements is required (VkPhysicalDeviceVulkan11Features::shaderDrawParameters OR VK_KHR_shader_draw_parameters).
The Vulkan spec states: If pCode is a pointer to SPIR-V code, and pCode declares any of the capabilities listed in the SPIR-V Environment appendix, one of the corresponding requirements must be satisfied (https://vulkan.lunarg.com/doc/view/1.4.313.0/linux/antora/spec/latest/chapters/shaders.html#VUID-VkShaderModuleCreateInfo-pCode-08740)

Loaded shader: /home/carlos/Projects/Misc/slang-sdl3-example/cmake-build-debug/flat-color.vs.spirv
Validation Error: [ VUID-VkShaderModuleCreateInfo-pCode-08737 ] | MessageID = 0xa5625282
vkCreateShaderModule(): pCreateInfo->pCode (spirv-val produced an error):
Invalid SPIR-V binary version 1.3 for target environment SPIR-V 1.0 (under Vulkan 1.0 semantics).
The Vulkan spec states: If pCode is a pointer to SPIR-V code, pCode must adhere to the validation rules described by the Validation Rules within a Module section of the SPIR-V Environment appendix (https://vulkan.lunarg.com/doc/view/1.4.313.0/linux/antora/spec/latest/chapters/shaders.html#VUID-VkShaderModuleCreateInfo-pCode-08737)

Loaded shader: /home/carlos/Projects/Misc/slang-sdl3-example/cmake-build-debug/flat-color.fs.spirv
```

The reason is that, by default, SDL3 will create the device using a minimal set of features, which is not
what slang needs to work. I ignore if this can be an issue in production environments, I suspect that
there are driver vendors that may take them very seriously. Still, we can fix them by creating the
device with some properties:

First, in a header or other part, declare the following macro and variables:

```c
#define VK_MAKE_API_VERSION(variant, major, minor, patch)                                         \
  ((((uint32_t)(variant)) << 29U) | (((uint32_t)(major)) << 22U) | (((uint32_t)(minor)) << 12U) | \
   ((uint32_t)(patch)))

static const size_t vk_device_extension_count = 1;
static const char* vk_device_extension_names[] = {
    "VK_KHR_shader_draw_parameters",
};
```

That macro is available in the Vulkan SDK. But I didn't want to include everything just to add that thing, it is an
overkill. If you are using the SDK anyway, use the provided one instead. The variables help us add the extensions
for the device creation.

Then, when we create the device, we should do it like this:

```c
  SDL_GPUVulkanOptions vulkan_options = {0};
  vulkan_options.vulkan_api_version = VK_MAKE_API_VERSION(0, 1, 4, 0);
  vulkan_options.device_extension_count = vk_device_extension_count;
  vulkan_options.device_extension_names = vk_device_extension_names;

  SDL_PropertiesID device_properties = SDL_CreateProperties();
  SDL_SetBooleanProperty(device_properties, SDL_PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, true);
  SDL_SetBooleanProperty(device_properties, SDL_PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true);
  SDL_SetBooleanProperty(device_properties,
                         SDL_PROP_GPU_DEVICE_CREATE_FEATURE_INDIRECT_DRAW_FIRST_INSTANCE_BOOLEAN,
                         true);
  SDL_SetPointerProperty(device_properties, SDL_PROP_GPU_DEVICE_CREATE_VULKAN_OPTIONS_POINTER,
                         &vulkan_options);

  app->device = SDL_CreateGPUDeviceWithProperties(device_properties);
  if (app->device == NULL) {
    SDL_Log("Error: SDL_CreateGPUDevice(): %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }
```

This is only needed for vulkan as far as I know, however, the same options should be used for other APIs. If you
compile using the code above, most warning should go away.

Unfortunately I haven't been able to remove one last warning:

```
Validation Error: [ VUID-VkShaderModuleCreateInfo-pCode-08740 ] | MessageID = 0x6e224e9
vkCreateShaderModule(): SPIR-V Capability DrawParameters was declared, but one of the following requirements is required (VkPhysicalDeviceVulkan11Features::shaderDrawParameters OR VK_KHR_shader_draw_parameters).
The Vulkan spec states: If pCode is a pointer to SPIR-V code, and pCode declares any of the capabilities listed in the SPIR-V Environment appendix, one of the corresponding requirements must be satisfied (https://vulkan.lunarg.com/doc/view/1.4.313.0/linux/antora/spec/latest/chapters/shaders.html#VUID-VkShaderModuleCreateInfo-pCode-08740)
```

I'm not sure why this is the case because I'm providing the extension name in the device creation options. One solution
may be to use `features` field in `SDL_GPUVulkanOptions` to add `VkPhysicalDeviceVulkan11Features::shaderDrawParameters`
alongside extensions. But that would require to use the Vulkan SDK. Which, again, would be an overkill for this blog series.

I'm planning to do some research and eliminate all warnings, but that will be done in another post.

## RenderDoc

Just use it: [https://renderdoc.org/](https://renderdoc.org/).


It is a wonder and powerful that helped me debug many issues, not only with this series of posts, but also with many other
projects.

If you want to integrate really nicely with SDL3, you can actually provide properties for every object created in `SDLGPU`,
it will show the name in renderdoc, which will help debug any issues.

## Summary

In this series we explroed how to integrate SDL3 with slang, which can be a little bit of fun when you don't know exactly
what to do with each part, because there is too many obscure features and conditions it starts to be hard to debug issues,
this post propose is to be a starting point that may help new developers understand some tricky parts of Vulkan and SDL3.

Thanks for reading!
Happy coding.

#ifndef MMDShaderTypes_h
#define MMDShaderTypes_h

#include <simd/simd.h>

#ifdef __METAL_VERSION__
// Metal side: packed_float3 = 12 bytes (no padding)
struct MMDVertex {
    packed_float3 position;
    packed_float3 normal;
    float2 uv;
};
#else
// CPU side: plain floats, 32 bytes total
struct __attribute__((packed)) MMDVertex {
    float position[3];
    float normal[3];
    float uv[2];
};
#endif

struct MMDUniforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float3 lightDirection;
    simd_float3 cameraPosition;
};

struct MMDMaterialUniforms {
    simd_float4 diffuse;
    simd_float3 specular;
    float specularPower;
    simd_float3 ambient;
    int hasTexture;
};

#endif

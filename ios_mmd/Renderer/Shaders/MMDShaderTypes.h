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

struct MMDSceneUniforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float3 lightDirection;
    float _pad0;
    simd_float3 lightColor;
    float _pad1;
    simd_float3 cameraPosition;
    float ambientIntensity;
    // Spherical harmonics (9 coefficients for diffuse irradiance)
    simd_float4 sh[9]; // xyz = coefficient, w unused (padding for Metal alignment)
};

struct MMDMaterialUniforms {
    simd_float4 diffuse;
    simd_float3 specular;
    float specularPower;
    simd_float3 ambient;
    int hasTexture;
    float roughness;
    float metallic;
    float _pad0;
    float _pad1;
};

#endif

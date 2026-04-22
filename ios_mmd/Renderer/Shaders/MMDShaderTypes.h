#ifndef MMDShaderTypes_h
#define MMDShaderTypes_h

#include <simd/simd.h>

struct MMDVertex {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 uv;
};

struct MMDUniforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float3 lightDirection;
    simd_float3 cameraPosition;
};

struct MMDMaterialUniforms {
    simd_float4 diffuse;       // rgb + alpha
    simd_float3 specular;
    float specularPower;
    simd_float3 ambient;
    int hasTexture;
};

#endif /* MMDShaderTypes_h */

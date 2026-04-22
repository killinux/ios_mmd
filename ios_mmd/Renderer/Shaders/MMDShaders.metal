#include <metal_stdlib>
using namespace metal;

#include "MMDShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float2 uv;
};

vertex VertexOut mmd_vertex(const device MMDVertex *vertices [[buffer(0)]],
                            constant MMDUniforms &uniforms   [[buffer(1)]],
                            uint vid                         [[vertex_id]])
{
    MMDVertex v = vertices[vid];

    float4 worldPos = uniforms.modelMatrix * float4(v.position, 1.0);
    float3 worldNorm = normalize((uniforms.modelMatrix * float4(v.normal, 0.0)).xyz);

    VertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldNormal = worldNorm;
    out.worldPosition = worldPos.xyz;
    out.uv = v.uv;
    return out;
}

fragment float4 mmd_fragment(VertexOut in                          [[stage_in]],
                             constant MMDMaterialUniforms &mat     [[buffer(0)]],
                             constant MMDUniforms &uniforms        [[buffer(1)]],
                             texture2d<float> tex                  [[texture(0)]],
                             sampler texSampler                    [[sampler(0)]])
{
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(-uniforms.lightDirection);

    float NdotL = dot(N, L);
    float diffuseIntensity = step(0.0, NdotL) * 0.6 + 0.4;

    float3 baseColor = mat.diffuse.rgb;

    if (mat.hasTexture) {
        float4 texColor = tex.sample(texSampler, in.uv);
        baseColor *= texColor.rgb;
    }

    float3 color = mat.ambient + baseColor * diffuseIntensity;

    if (mat.specularPower > 0.0) {
        float3 V = normalize(uniforms.cameraPosition - in.worldPosition);
        float3 H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), mat.specularPower);
        color += mat.specular * spec;
    }

    return float4(saturate(color), mat.diffuse.a);
}

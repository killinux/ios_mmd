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
    float3 pos = float3(vertices[vid].position);
    float3 norm = float3(vertices[vid].normal);
    float2 uv = float2(vertices[vid].uv);

    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);
    float3 worldNorm = normalize((uniforms.modelMatrix * float4(norm, 0.0)).xyz);

    VertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldNormal = worldNorm;
    out.worldPosition = worldPos.xyz;
    out.uv = float2(uv.x, 1.0 - uv.y);
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

    float NdotL = max(dot(N, L), 0.0);
    float toon = smoothstep(0.0, 0.1, NdotL) * 0.5 + 0.5;

    float4 texColor = float4(1.0);
    if (mat.hasTexture) {
        texColor = tex.sample(texSampler, in.uv);
    }

    float3 baseColor = mat.diffuse.rgb * texColor.rgb;
    float3 color = baseColor * toon;

    if (mat.specularPower > 0.0) {
        float3 V = normalize(uniforms.cameraPosition - in.worldPosition);
        float3 H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), mat.specularPower);
        color += mat.specular * spec * 0.3;
    }

    return float4(color, mat.diffuse.a * texColor.a);
}

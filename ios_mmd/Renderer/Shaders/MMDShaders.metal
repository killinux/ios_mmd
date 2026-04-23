#include <metal_stdlib>
using namespace metal;

#include "MMDShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float2 uv;
};

// ── Main pass: vertex shader ──

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

// ── Main pass: fragment shader (3-light + toon) ──

fragment float4 mmd_fragment(VertexOut in                          [[stage_in]],
                             constant MMDMaterialUniforms &mat     [[buffer(0)]],
                             constant MMDUniforms &uniforms        [[buffer(1)]],
                             texture2d<float> tex                  [[texture(0)]],
                             sampler texSampler                    [[sampler(0)]])
{
    float3 N = normalize(in.worldNormal);
    float3 V = normalize(uniforms.cameraPosition - in.worldPosition);

    // Three-light setup
    float3 keyLight = normalize(-uniforms.lightDirection);
    float3 fillLight = normalize(float3(0.5, 0.3, 0.8));
    float3 rimDir = normalize(float3(0.0, 0.5, -1.0));

    // Key light (toon-style)
    float NdotL = dot(N, keyLight);
    float toon = smoothstep(-0.05, 0.15, NdotL) * 0.55 + 0.45;

    // Fill light (soft, from the side)
    float fill = max(dot(N, fillLight), 0.0) * 0.2;

    // Rim light (edge highlight from behind)
    float rim = pow(1.0 - max(dot(N, V), 0.0), 3.0) * max(dot(N, rimDir) + 0.5, 0.0) * 0.3;

    // Texture
    float4 texColor = float4(1.0);
    if (mat.hasTexture) {
        texColor = tex.sample(texSampler, in.uv);
    }

    float3 baseColor = mat.diffuse.rgb * texColor.rgb;

    // Combine lighting
    float3 color = baseColor * (toon + fill) + rim * baseColor;

    // Specular (Blinn-Phong, key light only)
    if (mat.specularPower > 0.0) {
        float3 H = normalize(keyLight + V);
        float spec = pow(max(dot(N, H), 0.0), mat.specularPower);
        color += mat.specular * spec * 0.4;
    }

    // Subtle ambient boost for dark areas
    color += baseColor * 0.05;

    return float4(saturate(color), mat.diffuse.a * texColor.a);
}

// ── Edge pass: vertex shader (expand along normal) ──

vertex VertexOut mmd_edge_vertex(const device MMDVertex *vertices [[buffer(0)]],
                                 constant MMDUniforms &uniforms   [[buffer(1)]],
                                 constant float &edgeSize         [[buffer(2)]],
                                 uint vid                         [[vertex_id]])
{
    float3 pos = float3(vertices[vid].position);
    float3 norm = float3(vertices[vid].normal);

    // Expand position along normal for outline
    pos += norm * edgeSize;

    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);

    VertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldNormal = float3(0);
    out.worldPosition = worldPos.xyz;
    out.uv = float2(0);
    return out;
}

// ── Edge pass: fragment shader (solid dark color) ──

fragment float4 mmd_edge_fragment(VertexOut in [[stage_in]],
                                  constant float4 &edgeColor [[buffer(0)]])
{
    return edgeColor;
}

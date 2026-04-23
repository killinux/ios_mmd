#include <metal_stdlib>
using namespace metal;

#include "MMDShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float2 uv;
};

// ── PBR helper functions ──

float DistributionGGX(float3 N, float3 H, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = M_PI_F * denom * denom;
    return a2 / max(denom, 1e-7);
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
}

float3 FresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// ── Spherical Harmonics evaluation (order 2, 9 coefficients) ──

float3 evaluateSH(float3 n, constant float4 *sh) {
    return sh[0].xyz
        + sh[1].xyz * n.y + sh[2].xyz * n.z + sh[3].xyz * n.x
        + sh[4].xyz * (n.x * n.y) + sh[5].xyz * (n.y * n.z)
        + sh[6].xyz * (3.0 * n.z * n.z - 1.0) + sh[7].xyz * (n.x * n.z)
        + sh[8].xyz * (n.x * n.x - n.y * n.y);
}

// ── ACES tone mapping ──

float3 ACESFilm(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// ── Main pass: vertex shader ──

vertex VertexOut mmd_vertex(const device MMDVertex *vertices [[buffer(0)]],
                            constant MMDSceneUniforms &scene [[buffer(1)]],
                            uint vid                         [[vertex_id]])
{
    float3 pos  = float3(vertices[vid].position);
    float3 norm = float3(vertices[vid].normal);
    float2 uv   = float2(vertices[vid].uv);

    float4 worldPos  = scene.modelMatrix * float4(pos, 1.0);
    float3 worldNorm = normalize((scene.modelMatrix * float4(norm, 0.0)).xyz);

    VertexOut out;
    out.position      = scene.projectionMatrix * scene.viewMatrix * worldPos;
    out.worldNormal   = worldNorm;
    out.worldPosition = worldPos.xyz;
    out.uv            = float2(uv.x, 1.0 - uv.y);
    return out;
}

// ── Main pass: fragment shader (PBR Cook-Torrance + IBL via SH) ──

fragment float4 mmd_fragment(VertexOut in                          [[stage_in]],
                             constant MMDMaterialUniforms &mat     [[buffer(0)]],
                             constant MMDSceneUniforms &scene      [[buffer(1)]],
                             texture2d<float> tex                  [[texture(0)]],
                             sampler texSampler                    [[sampler(0)]])
{
    float3 N = normalize(in.worldNormal);
    float3 V = normalize(scene.cameraPosition - in.worldPosition);
    float3 R = reflect(-V, N);

    // Base color
    float4 texColor = float4(1.0);
    if (mat.hasTexture) {
        texColor = tex.sample(texSampler, in.uv);
    }
    float3 albedo = mat.diffuse.rgb * texColor.rgb;
    float alpha   = mat.diffuse.a * texColor.a;

    // PBR parameters
    float roughness = clamp(mat.roughness, 0.04, 1.0);
    float metallic  = clamp(mat.metallic, 0.0, 1.0);

    // F0: dielectric base reflectance 0.04, metals use albedo
    float3 F0 = mix(float3(0.04), albedo, metallic);

    // ── Direct lighting (key light) ──
    float3 L = normalize(-scene.lightDirection);
    float3 H = normalize(V + L);

    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float HdotV = max(dot(H, V), 0.0);

    // Cook-Torrance BRDF
    float  D = DistributionGGX(N, H, roughness);
    float  G = GeometrySmith(N, V, L, roughness);
    float3 F = FresnelSchlick(HdotV, F0);

    float3 numerator  = D * G * F;
    float denominator = 4.0 * NdotV * NdotL + 1e-4;
    float3 specularBRDF = numerator / denominator;

    // Energy conservation: what isn't reflected is refracted (diffuse)
    float3 kD = (float3(1.0) - F) * (1.0 - metallic);

    float3 directLight = (kD * albedo / M_PI_F + specularBRDF) * scene.lightColor * NdotL;

    // ── IBL diffuse (from spherical harmonics) ──
    float3 irradiance   = max(evaluateSH(N, scene.sh), float3(0.0));
    float3 F_ibl        = FresnelSchlickRoughness(NdotV, F0, roughness);
    float3 kD_ibl       = (float3(1.0) - F_ibl) * (1.0 - metallic);
    float3 iblDiffuse   = kD_ibl * irradiance * albedo;

    // ── IBL specular (approximate: SH sampled at reflection direction, roughness-blended) ──
    // Rough surfaces see more diffuse-like reflection, smooth surfaces see sharper
    float3 prefilteredEnv = max(evaluateSH(R, scene.sh), float3(0.0));
    // Approximate split-sum: blend between sharp reflection and diffuse as roughness increases
    float3 envBRDF  = F_ibl * (1.0 - roughness * 0.7);
    float3 iblSpecular = prefilteredEnv * envBRDF;

    // ── Combine ──
    float3 ambient = (iblDiffuse + iblSpecular) * scene.ambientIntensity;
    float3 color   = directLight + ambient;

    // ACES tone mapping
    color = ACESFilm(color);

    return float4(color, alpha);
}

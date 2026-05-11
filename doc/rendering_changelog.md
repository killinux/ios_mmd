# ios_mmd 渲染优化 — 实施记录

## 进度总览

| 优先级 | 功能 | 状态 | 日期 |
|--------|------|------|------|
| P0 | Sphere Map（MatCap） | ✅ 完成 | 2026-05-11 |
| P0 | 描边（法线外扩） | ✅ 完成 | 2026-05-11 |
| P0 | 材质色描边（原神风格） | ✅ 完成 | 2026-05-11 |
| P0 | Rim Light（菲涅尔边缘光） | ✅ 完成 | 2026-05-11 |
| P1 | Toon Ramp 着色 | 🔲 待实施 | — |
| P1 | Toon 纹理支持（toon01-10） | 🔲 待实施 | — |
| P2 | 头发各向异性高光 | 🔲 待实施 | — |
| P2 | 皮肤次表面散射 SSS | 🔲 待实施 | — |
| P2 | 法线贴图 | 🔲 待实施 | — |
| P3 | 阴影映射 Shadow Map | 🔲 待实施 | — |
| P3 | Bloom 辉光 | 🔲 待实施 | — |
| P3 | SSAO 环境遮蔽 | 🔲 待实施 | — |

---

## 已完成的改动

### P0-1: Sphere Map（MatCap）— 2026-05-11

**效果：** 眼睛出现高光反射点，金属饰品有环境反射。

**改动文件：**

| 文件 | 改动 |
|------|------|
| `SabaModelData.h` | 新增 `sphereTexturePath`、`sphereTextureMode` 属性 |
| `SabaBridge.mm` | 从 `mats[i].m_spTexture` 和 `m_spTextureMode` 提取 sphere map 数据 |
| `MMDShaderTypes.h` | `MMDMaterialUniforms` 新增 `hasSphereTexture`、`sphereTextureMode` 字段 |
| `MMDShaders.metal` | fragment shader 将法线变换到视空间 → UV 采样球面贴图，支持 Mul/Add 模式 |
| `MetalMMDRenderer.swift` | `loadTextures()` 加载 sphere 纹理，`drawSubMesh()` 绑定到 texture slot 1 |

**Shader 核心逻辑：**
```metal
float3 viewNormal = normalize((scene.viewMatrix * float4(N, 0.0)).xyz);
float2 spUV = viewNormal.xy * 0.5 + 0.5;
float4 spColor = sphereTex.sample(texSampler, spUV);
if (mat.sphereTextureMode == 1) albedo *= spColor.rgb;  // Mul: 暗化
if (mat.sphereTextureMode == 2) albedo += spColor.rgb;  // Add: 高亮
```

---

### P0-2: 描边（Back-Face Normal Extrusion）— 2026-05-11

**效果：** 角色轮廓出现描边线，edgeSize/edgeColor 由 PMX 材质数据控制。

**改动文件：**

| 文件 | 改动 |
|------|------|
| `SabaModelData.h` | 新增 `edgeColorR/G/B/A`、`bothFace` 属性 |
| `SabaBridge.mm` | 从 `m_edgeColor`、`m_bothFace` 提取数据 |
| `MMDShaderTypes.h` | 新增 `MMDOutlineUniforms` 结构体（edgeColor, diffuseColor, edgeSize） |
| `MMDShaders.metal` | 新增 `outline_vertex`（裁剪空间法线外扩）和 `outline_fragment` |
| `MetalMMDRenderer.swift` | 创建 outline pipeline，在主渲染前画背面描边（cull front） |

**渲染顺序：**
```
描边(背面, cull front, no depth write)
  → 不透明主渲染(cull none, depth write)
  → 透明主渲染(cull none, no depth write)
```

**踩坑记录：**
1. 第一版 cull mode 设成 `.back`，MMD 模型面朝向不一致导致全黑 → 改回 `.none`
2. 第一版描边 pass 开启 depth write，描边和主渲染 z 深度相同，`less` 比较失败导致全黑 → 改为 `depthStateNoWrite`

---

### P0-3: 材质色描边（原神风格）— 2026-05-11

**效果：** 描边颜色从纯黑变为材质色暗化版本（棕发→深棕描边，肤色→深肤色描边），更柔和自然。

**改动文件：**

| 文件 | 改动 |
|------|------|
| `MMDShaderTypes.h` | `MMDOutlineUniforms` 新增 `diffuseColor` 字段 |
| `MMDShaders.metal` | `outline_fragment` 改为 diffuse*0.35 与 edgeColor 按 7:3 混合 |
| `MetalMMDRenderer.swift` | 传入 `mat.diffuseR/G/B` 到描边 uniform |

**Shader 核心逻辑：**
```metal
float3 tinted = outline.diffuseColor * 0.35;
float3 color = mix(tinted, outline.edgeColor.rgb, 0.3);
return float4(color, outline.edgeColor.a);
```

---

### P0-4: Rim Light（菲涅尔边缘光）— 2026-05-11

**效果：** 角色边缘泛出柔和光晕，增强轮廓立体感。

**改动文件：** `MMDShaders.metal`

**Shader 核心逻辑：**
```metal
float rim = 1.0 - max(dot(N, V), 0.0);
rim = pow(rim, 3.0);
float3 rimColor = float3(1.0, 0.95, 0.9) * 0.25 * rim * max(NdotL, 0.2);
color += rimColor;
```

---

### Bridge 层扩展汇总

从 saba `MMDMaterial` 新增暴露的字段：

| ObjC 属性 | C++ 来源 | 用途 |
|-----------|----------|------|
| `sphereTexturePath` | `m_spTexture` | 球面贴图路径 |
| `sphereTextureMode` | `m_spTextureMode` | 0=None, 1=Mul, 2=Add |
| `edgeColorR/G/B/A` | `m_edgeColor` | 描边颜色 |
| `bothFace` | `m_bothFace` | 双面渲染标记 |

**尚未暴露但后续需要的字段：**

| C++ 字段 | 用途 | 对应阶段 |
|----------|------|----------|
| `m_toonTexture` | Toon 渐变纹理路径 | P1 |
| `m_textureMulFactor` / `m_textureAddFactor` | 纹理混合因子 | P1 |
| `m_spTextureMulFactor` / `m_spTextureAddFactor` | 球面贴图混合因子 | P1 |
| `m_groundShadow` | 地面阴影标记 | P3 |
| `m_shadowCaster` / `m_shadowReceiver` | 投射/接收阴影 | P3 |

---

## 当前渲染管线

```
1. Outline Pass (per-submesh where edgeSize > 0)
   - Pipeline: outline_vertex + outline_fragment
   - Cull: front (只画背面)
   - Depth: read only, no write
   - 输出: 材质色暗化描边

2. Opaque Main Pass (non-PNG textures)
   - Pipeline: mmd_vertex + mmd_fragment
   - Cull: none
   - Depth: read + write
   - 输出: PBR + Sphere Map + Rim Light + ACES tonemapping

3. Transparent Pass (PNG textures)
   - Pipeline: mmd_vertex + mmd_fragment
   - Cull: none
   - Depth: read only, no write
   - 输出: 同上，alpha blend
```

---

## 下一步：P1 实施计划

### P1-1: Toon Ramp 着色

在 fragment shader 中加入可切换的 Toon 模式。用 half-lambert 和 smoothstep 制造明暗分界线：

```metal
float halfLambert = dot(N, L) * 0.5 + 0.5;
float toon = smoothstep(0.45, 0.55, halfLambert);
float3 shadowColor = albedo * float3(0.65, 0.6, 0.7); // 偏冷阴影
float3 lit = mix(shadowColor, albedo, toon);
```

与现有 PBR 混合策略：
- 保留 PBR 高光（Cook-Torrance specular）
- 将 Lambert diffuse 替换为 Toon ramp diffuse
- 这样高光仍然写实，漫反射有卡通感

**工作量：** 小，仅改 MMDShaders.metal

### P1-2: Toon 纹理支持

PMX 材质指定 toon index（0-9 对应 toon01.bmp~toon10.bmp）。用真正的 toon 纹理替代 hardcode 的 smoothstep。

**需要：**
- Bridge 暴露 `m_toonTexture`
- 内置 toon01-10 渐变纹理（10 张小图，每张约 1KB）
- Fragment shader 中用 NdotL 采样 toon 纹理

**工作量：** 中

### P1-3: 双面渲染

利用已暴露的 `bothFace` 字段，对双面材质关闭 backface culling。当前全用 cull none 所以效果等同，但后续优化 cull mode 时需要区分。

**工作量：** 极小

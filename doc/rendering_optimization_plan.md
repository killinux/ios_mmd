# ios_mmd 渲染优化方案

## 当前实现分析

### 已有的渲染管线

```
vertex → Cook-Torrance PBR fragment shader → ACES tonemapping → output
```

| 模块 | 实现 | 文件 |
|------|------|------|
| BRDF | Cook-Torrance (GGX + Schlick-GGX + Fresnel-Schlick) | MMDShaders.metal:15-44 |
| 环境光 | 球谐光照 SH (9 系数, 2 阶) | MMDShaders.metal:48-54 |
| 色调映射 | ACES Film | MMDShaders.metal:58-65 |
| 直接光 | 单方向光 + 能量守恒 | MMDShaders.metal:115-135 |
| 渲染顺序 | 双 pass: 不透明(depth write) → PNG 透明(no depth write) | MetalMMDRenderer.swift:276-294 |
| 材质转换 | specularPower → roughness, specular 均值 → metallic 阈值 | MetalMMDRenderer.swift:307-311 |
| 物理 | Bullet3 + 陀螺仪重力 | SabaBridge.mm |

### 当前的问题

1. **PBR 与 MMD 模型不匹配** — PMX 模型为日式动漫风格设计，PBR 写实渲染让皮肤暗沉、缺少通透感
2. **眼睛无光泽** — PMX 的眼睛依赖 Sphere Map（球面环境贴图），当前未实现
3. **无描边** — PMX 材质自带 `edgeSize` 和 `edgeColor`（Bridge 已提取 edgeSize），但 shader 未使用
4. **头发高光不自然** — 各向同性 GGX 不适合头发丝，应用 Kajiya-Kay 各向异性模型
5. **缺少 Toon 渐变** — PMX 支持 toon01~toon10 渐变纹理，当前未使用
6. **metallic 估算粗糙** — 仅用 specular 均值 > 0.5 ? 0.3 : 0.0 的阈值判断

### saba 库中已有但未暴露的材质数据

```cpp
// Libraries/saba/src/Saba/Model/MMD/MMDMaterial.h
struct MMDMaterial {
    // ✅ 已暴露
    glm::vec3   m_diffuse;
    float       m_alpha;
    glm::vec3   m_specular;
    float       m_specularPower;
    glm::vec3   m_ambient;
    float       m_edgeSize;
    std::string m_texture;

    // ❌ 未暴露 — 需要添加到 SabaBridge
    std::string     m_spTexture;        // Sphere Map 纹理路径
    SphereTextureMode m_spTextureMode;  // None=0, Mul=1, Add=2
    std::string     m_toonTexture;      // Toon 渐变纹理路径
    glm::vec4       m_edgeColor;        // 描边颜色 RGBA
    uint8_t         m_edgeFlag;         // 是否启用描边
    bool            m_bothFace;         // 双面渲染
    glm::vec4       m_textureMulFactor; // 纹理乘算因子
    glm::vec4       m_spTextureMulFactor;
    glm::vec4       m_toonTextureMulFactor;
    glm::vec4       m_textureAddFactor;
    glm::vec4       m_spTextureAddFactor;
    glm::vec4       m_toonTextureAddFactor;
    bool            m_groundShadow;     // 地面阴影
    bool            m_shadowCaster;     // 投射阴影
    bool            m_shadowReceiver;   // 接收阴影
};

enum class SphereTextureMode {
    None,  // 无球面贴图
    Mul,   // 乘算（暗化，用于阴影/暗部）
    Add,   // 加算（高亮，用于眼睛/金属光泽）
};
```

---

## 优化方案总览

### 优先级路线图

```
P0（立即实施，效果最大）
├── Sphere Map（MatCap）  → 眼睛有光泽、金属有反射
└── 描边（法线外扩法）    → 角色轮廓清晰，动漫感

P1（核心 NPR 增强）
├── Toon Ramp 着色       → 皮肤明暗过渡自然
├── Rim Light            → 菲涅尔边缘光，轮廓发光
└── Toon 纹理支持        → 使用 PMX 自带 toon01-10

P2（高级材质）
├── 头发各向异性高光      → Kajiya-Kay 模型
├── 皮肤次表面散射 SSS    → 通透感
└── 法线贴图             → 细节纹理增强

P3（后处理 & 阴影）
├── 阴影映射 Shadow Map   → 地面/身体投影
├── Bloom 辉光            → 高光区域发光
└── SSAO 环境遮蔽         → 凹陷处加阴影
```

---

## P0: Sphere Map + 描边

### P0-1: Sphere Map（MatCap）

**原理：** 将法线变换到视空间，用 xy 分量作为 UV 采样球面贴图。这是 MMD 原版的核心特效，让眼睛闪亮、金属反光。

**实现步骤：**

#### 1. 扩展 Bridge 层

`SabaModelData.h` 新增属性:
```objc
@property (nonatomic, copy) NSString *sphereTexturePath;
@property (nonatomic) int sphereTextureMode;  // 0=None, 1=Mul, 2=Add
@property (nonatomic) float edgeColorR, edgeColorG, edgeColorB, edgeColorA;
@property (nonatomic) BOOL bothFace;
```

`SabaBridge.mm` 的 `materials` 方法中补充:
```objc
// Sphere texture
std::string spTexPath = mats[i].m_spTexture;
mi.sphereTexturePath = spTexPath.empty() ? @"" : @(spTexPath.c_str());
mi.sphereTextureMode = (int)mats[i].m_spTextureMode;

// Edge color
mi.edgeColorR = mats[i].m_edgeColor.r;
mi.edgeColorG = mats[i].m_edgeColor.g;
mi.edgeColorB = mats[i].m_edgeColor.b;
mi.edgeColorA = mats[i].m_edgeColor.a;

// Both face
mi.bothFace = mats[i].m_bothFace;
```

#### 2. Shader 端

`MMDShaderTypes.h` 材质 uniform 添加:
```c
int hasSphereTexture;
int sphereTextureMode; // 0=None, 1=Mul, 2=Add
```

`MMDShaders.metal` fragment shader:
```metal
// Sphere Map sampling
if (mat.hasSphereTexture) {
    float3 viewNormal = normalize((scene.viewMatrix * float4(N, 0.0)).xyz);
    float2 spUV = viewNormal.xy * 0.5 + 0.5;
    float3 spColor = sphereTex.sample(texSampler, spUV).rgb;

    if (mat.sphereTextureMode == 1) {       // Mul
        albedo *= spColor;
    } else if (mat.sphereTextureMode == 2) { // Add
        albedo += spColor;
    }
}
```

#### 3. Renderer 层

`MetalMMDRenderer.swift`:
- 加载 sphere texture（用模型目录 + `sphereTexturePath` 拼路径）
- 绑定到 texture slot 1: `encoder.setFragmentTexture(sphereTex, index: 1)`

**预期效果：**
- 眼睛出现高光反射点
- 金属饰品有环境反射
- 皮肤有柔和的球面渐变

---

### P0-2: 描边（Back-Face Normal Extrusion）

**原理：** 额外的渲染 pass，只画背面，沿法线方向将顶点向外挤出 `edgeSize` 像素，填充 `edgeColor`。

**实现步骤：**

#### 1. 新增描边 shader

```metal
// 描边 vertex shader
vertex VertexOut outline_vertex(const device MMDVertex *vertices [[buffer(0)]],
                                constant MMDSceneUniforms &scene [[buffer(1)]],
                                constant float &edgeScale        [[buffer(2)]],
                                uint vid [[vertex_id]])
{
    float3 pos  = float3(vertices[vid].position);
    float3 norm = float3(vertices[vid].normal);

    // 在裁剪空间中计算外扩量，确保屏幕上等宽
    float4 worldPos = scene.modelMatrix * float4(pos, 1.0);
    float4 clipPos  = scene.projectionMatrix * scene.viewMatrix * worldPos;
    float3 worldNorm = normalize((scene.modelMatrix * float4(norm, 0.0)).xyz);
    float3 clipNorm  = normalize((scene.projectionMatrix * scene.viewMatrix * float4(worldNorm, 0.0)).xyz);

    // 屏幕空间等宽外扩
    clipPos.xy += clipNorm.xy * edgeScale * clipPos.w * 0.002;

    VertexOut out;
    out.position = clipPos;
    out.worldNormal = worldNorm;
    out.worldPosition = worldPos.xyz;
    out.uv = float2(0);
    return out;
}

// 描边 fragment shader — 直接输出边缘颜色
fragment float4 outline_fragment(VertexOut in [[stage_in]],
                                  constant float4 &edgeColor [[buffer(0)]])
{
    return edgeColor;
}
```

#### 2. 渲染流程变更

```
原: 不透明 → 透明
新: 描边(背面, cull front) → 不透明(cull back) → 透明(no cull)
```

`MetalMMDRenderer.swift`:
```swift
// 1. 描边 pass — 只画有 edgeSize > 0 的 submesh
encoder.setRenderPipelineState(outlinePipelineState)
encoder.setDepthStencilState(depthStateWrite)
encoder.setCullMode(.front)  // 只画背面
for sub in subMeshes {
    let mat = materialInfos[Int(sub.materialID)]
    if mat.edgeSize <= 0 { continue }
    var edgeScale = mat.edgeSize
    var color = SIMD4<Float>(mat.edgeColorR, mat.edgeColorG, mat.edgeColorB, mat.edgeColorA)
    encoder.setVertexBytes(&edgeScale, length: 4, index: 2)
    encoder.setFragmentBytes(&color, length: 16, index: 0)
    // drawIndexedPrimitives...
}

// 2. 主渲染 pass
encoder.setRenderPipelineState(mainPipelineState)
encoder.setCullMode(.back)
// ... 不透明 → 透明
```

**预期效果：**
- 角色轮廓出现清晰的描边线
- 描边颜色/粗细由 PMX 材质数据控制（通常是深色/黑色）
- 立刻产生日式动漫的视觉感

---

## P1: NPR Toon 增强

### P1-1: Toon Ramp 着色

**原理：** 用一张 1D 渐变纹理（Ramp Texture）替代连续的 Lambert 明暗过渡，产生卡通风格的色带。

**两种模式：**

#### 模式 A: 使用 PMX 自带 Toon 纹理

PMX 格式内置 toon01.bmp ~ toon10.bmp 共 10 张渐变图。每个材质指定一个 toon index。

```metal
float NdotL = dot(N, L) * 0.5 + 0.5;  // 重映射到 [0,1]
float3 toonColor = toonTex.sample(toonSampler, float2(NdotL, 0.5)).rgb;
float3 lit = albedo * toonColor;
```

#### 模式 B: 自定义 Ramp（原神风格）

自定义明暗分界线位置和过渡宽度:
```metal
float halfLambert = dot(N, L) * 0.5 + 0.5;
float rampThreshold = 0.5;
float rampSmooth = 0.05;
float toon = smoothstep(rampThreshold - rampSmooth, rampThreshold + rampSmooth, halfLambert);
float3 shadowColor = albedo * float3(0.6, 0.55, 0.65);  // 偏冷的阴影
float3 lit = mix(shadowColor, albedo, toon);
```

**Bridge 层改动：**
```objc
@property (nonatomic, copy) NSString *toonTexturePath;
```

**预期效果：**
- 明暗过渡从连续渐变变为带状分界
- 阴影区域有颜色偏移（暖光冷影）
- 接近原版 MMD 的 Toon 着色效果

---

### P1-2: Rim Light（菲涅尔边缘光）

**原理：** 在物体边缘（法线与视线近乎垂直处）添加额外亮光，增强轮廓感和立体感。

```metal
// 在 fragment shader 末尾添加
float rim = 1.0 - max(dot(N, V), 0.0);
rim = pow(rim, 3.0);  // 控制边缘光宽度
float3 rimColor = float3(1.0, 0.95, 0.9) * 0.3;  // 暖白色
color += rimColor * rim * max(dot(N, L), 0.0);  // 仅受光面有 rim
```

**预期效果：**
- 角色边缘泛出柔和的光晕
- 头发轮廓更加分明
- 整体画面更有「舞台灯光」感

**工作量：** 非常小，仅 5 行 shader 代码

---

## P2: 高级材质

### P2-1: 头发各向异性高光（Kajiya-Kay 模型）

**原理：** 头发不是光滑表面，而是大量平行的圆柱丝状结构。高光沿发丝方向形成带状而非点状。

```metal
// Kajiya-Kay specular for hair
float3 T = normalize(tangent);  // 发丝切线方向
float TdotH = dot(T, H);
float sinTH = sqrt(1.0 - TdotH * TdotH);
float hairSpec = pow(sinTH, mat.specularPower) * 0.5;

// 双层高光（主高光 + 次高光偏移）
float3 hairSpecColor = float3(1.0, 0.95, 0.85) * hairSpec;
```

**难点：** 需要逐顶点切线数据。可选方案：
- 方案 A: 从 UV 梯度自动估算切线（`dfdx(uv)`, `dfdy(uv)`）
- 方案 B: 预计算顶点切线并传入顶点 buffer

**预期效果：** 头发出现沿发丝方向的带状高光，丝绸质感

---

### P2-2: 皮肤次表面散射（SSS）

**原理：** 光线穿过皮肤在内部散射后从另一侧射出，产生通透的暖色调（耳朵、手指在背光时泛红）。

**简化方案（Wrap Lighting）：**
```metal
// 皮肤材质检测（基于 diffuse 偏肉色）
bool isSkin = (albedo.r > 0.4 && albedo.g > 0.25 && albedo.r > albedo.b * 1.2);

if (isSkin) {
    float wrap = 0.5;  // 散射范围
    float NdotL_wrap = (dot(N, L) + wrap) / (1.0 + wrap);
    NdotL_wrap = max(NdotL_wrap, 0.0);

    // 散射后偏红/暖
    float3 scatterColor = float3(1.0, 0.4, 0.3);
    float scatter = saturate(1.0 - NdotL_wrap);
    color += albedo * scatterColor * scatter * 0.15;
}
```

**预期效果：** 皮肤暗部偏暖红色，整体更有生命力

---

### P2-3: 法线贴图支持

**原理：** 用纹理编码表面微细法线偏移，不增加多边形就能表现皮肤纹理、布料褶皱。

PMX 模型的贴图中常有 `_N.jpg` / `_normal.jpg` 后缀的法线贴图（如 `pc_a_nk_hair_rgbx_normal.jpg`）。

**实现需要：**
- 顶点 buffer 增加 tangent (float3) — 顶点格式从 32 字节变为 44 字节
- Fragment shader 中用 TBN 矩阵变换法线贴图采样值

**工作量：** 中等（需改动顶点格式和 saba 数据提取）

---

## P3: 后处理与阴影

### P3-1: 阴影映射（Shadow Map）

**原理：** 从光源视角渲染深度图，主渲染时比较片元深度判断是否在阴影中。

```
渲染流程:
1. Shadow pass: 从光源视角渲染深度 → shadow map texture
2. Main pass: 采样 shadow map 判断阴影 → 混合到最终颜色
```

**关键参数：**
- Shadow map 分辨率: 1024x1024（iPhone 性能足够）
- PCF 软阴影: 3x3 采样核
- 级联阴影（CSM）: 对于单角色场景不需要

**预期效果：** 地面/身体出现投影，角色更「站」在地面上

---

### P3-2: Bloom 辉光

**原理：** 提取画面高亮区域，高斯模糊后叠加回原图，模拟相机过曝效果。

```
渲染流程:
1. 主渲染 → full-res HDR texture
2. 亮度筛选 → half-res bright-pass texture (brightness > threshold)
3. 两趟高斯模糊（水平 + 垂直）
4. 叠加回原图
```

**适用场景：** 眼睛高光、金属反射点、Sphere Map 加算区域

**工作量：** 中等（需要额外的 render pass 和 compute shader）

---

### P3-3: SSAO（屏幕空间环境遮蔽）

**原理：** 在屏幕空间采样周围片元深度，估算几何遮挡程度，让凹陷处变暗。

**简化方案（半分辨率）：**
1. 渲染 depth + normal 到 G-buffer
2. 半分辨率 compute shader 采样 16 个随机方向
3. 双边模糊去噪
4. 乘到最终颜色的 ambient 分量

**预期效果：** 眼窝、领口、裙褶等凹陷处出现自然阴影

**工作量：** 大（需要 G-buffer pass + compute shader + blur pass）

---

## 行业参考

### 原神（Genshin Impact）

| 技术 | 实现 |
|------|------|
| 着色 | 自定义 Ramp Texture，冷暖色调分离 |
| 脸部阴影 | SDF（Signed Distance Field）贴图，避免法线阴影 |
| 描边 | 屏幕空间法线/深度边缘检测（非法线外扩） |
| 头发 | 各向异性高光 + 双层 specular |
| 金属 | MatCap 反射 + 高光 |
| 后处理 | Bloom + Color Grading |

### 崩坏3 / 崩坏：星穹铁道

| 技术 | 实现 |
|------|------|
| 着色 | 3 色 Ramp（亮面/暗面/过渡） |
| 描边 | 顶点色控制描边粗细（顶点法线外扩 + 顶点色权重） |
| 表情 | Morph + SDF 面部阴影 |
| Rim Light | 基于 Fresnel 的边缘光，颜色可调 |
| 后处理 | Bloom + SSAO + DOF |

### MikuMikuDance（原版 MMD）

| 技术 | 实现 |
|------|------|
| 着色 | Toon 渐变纹理 (toon01-10) |
| 球面贴图 | Sphere Map（Mul/Add 模式） |
| 描边 | 法线外扩（固定像素宽） |
| 光照 | 单方向光 + 简单 ambient |
| 阴影 | 简单 shadow map |

### 蓝色协议（Blue Protocol）

| 技术 | 实现 |
|------|------|
| 着色 | PBR + NPR 混合（按材质切换） |
| 描边 | 屏幕空间深度/法线不连续检测 |
| 皮肤 | 预积分 SSS + Wrap Lighting |
| 环境 | Reflection Probe + SH |

---

## 改动文件清单

### P0 涉及文件

| 文件 | 改动内容 |
|------|----------|
| `SabaModelData.h` | 添加 sphereTexturePath, sphereTextureMode, edgeColor, bothFace 属性 |
| `SabaBridge.mm` | 从 saba MMDMaterial 提取新增字段 |
| `MMDShaderTypes.h` | 材质 uniform 添加 hasSphereTexture, sphereTextureMode; 新增描边 uniform |
| `MMDShaders.metal` | fragment shader 添加 sphere map 采样; 新增 outline vertex/fragment shader |
| `MetalMMDRenderer.swift` | 加载 sphere 纹理; 创建 outline pipeline state; 添加描边渲染 pass |

### P1 涉及文件

| 文件 | 改动内容 |
|------|----------|
| `SabaModelData.h` | 添加 toonTexturePath |
| `SabaBridge.mm` | 提取 m_toonTexture |
| `MMDShaders.metal` | 添加 toon ramp 采样, rim light 计算 |
| `MetalMMDRenderer.swift` | 加载 toon 纹理（内置 toon01-10 或自定义） |

### P2 涉及文件

| 文件 | 改动内容 |
|------|----------|
| `MMDShaderTypes.h` | 顶点增加 tangent; 材质增加 isSkin flag |
| `MMDShaders.metal` | Kajiya-Kay 头发高光, SSS wrap lighting, 法线贴图采样 |
| `SabaBridge.mm` | 提取/计算顶点切线 |
| `MetalMMDRenderer.swift` | 法线贴图加载, 顶点 buffer 扩展 |

### P3 涉及文件

| 文件 | 改动内容 |
|------|----------|
| `MMDShaders.metal` | shadow map 采样, bloom bright-pass |
| `MetalMMDRenderer.swift` | shadow pass, bloom 降采样/模糊/合成, SSAO compute shader |
| 新增 | `Bloom.metal`, `SSAO.metal`（compute shader） |

---

## 效果对比预期

```
当前效果:
┌──────────────────────────────┐
│  ● 写实 PBR 光照              │
│  ● 皮肤偏暗、缺乏通透感       │
│  ● 眼睛无高光反射             │
│  ● 无描边、缺少动漫感         │
│  ● 头发高光是圆形点状         │
└──────────────────────────────┘

P0 完成后:
┌──────────────────────────────┐
│  ● 眼睛闪亮（Sphere Map Add）  │
│  ● 金属有反射（Sphere Map Mul）│
│  ● 角色轮廓有描边线           │
│  ● 整体产生动漫角色感觉       │
└──────────────────────────────┘

P1 完成后:
┌──────────────────────────────┐
│  ● 明暗有清晰分界线（Toon）    │
│  ● 暗面偏冷色调              │
│  ● 边缘有柔和光晕（Rim Light）│
│  ● 接近原版 MMD 渲染效果      │
└──────────────────────────────┘

全部完成后:
┌──────────────────────────────┐
│  ● 头发丝状高光              │
│  ● 皮肤通透有血色            │
│  ● 地面投影                  │
│  ● 高光辉光（Bloom）          │
│  ● 达到原神级别的角色渲染     │
└──────────────────────────────┘
```

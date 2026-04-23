# PMX 模型渲染行业调研报告

> 调研时间：2026-04-23
> 目标：了解行业内 PMX 模型效果最好的使用方式，为 ios_mmd 渲染质量升级提供方向

## 1. 方案总览

| 方案 | 代表 | 质量 | 实时性 | 移动端可行 |
|------|------|------|--------|-----------|
| Ray-MMD | MMD + MME | ★★★★★ | 实时 | ❌ (DX9) |
| Unity + lilToon | VRChat 生态 | ★★★★ | 实时 | ✅ |
| UE5 + Lumen | 影视级 | ★★★★★ | 实时 | ⚠️ (重) |
| Blender Cycles | 离线光追 | ★★★★★+ | 离线 | ❌ |
| Blender Eevee | 实时 PBR | ★★★★ | 实时 | ❌ |
| 原神式 NPR | miHoYo | ★★★★ | 实时 | ✅ (标杆) |
| 我们当前 (PBR+IBL) | Metal | ★★★ | 实时 | ✅ |

---

## 2. Ray-MMD — MMD 生态内天花板

**项目地址**: https://github.com/ray-cast/ray-mmd
**升级版**: https://github.com/norz3n/ray-mmd-2.0
**技术栈**: HLSL + DX9 + MikuMikuEffect

### 完整功能列表

#### 材质系统
- PBR 材质：albedo / metallic / smoothness(roughness) / specular / reflectance / emissive
- Clear Coat 材质：带吸收的第二层涂层（汽车漆、指甲油效果）
- Cloth 材质：布料专用 DFG（漫反射查找表），模拟织物的柔和高光
- Anisotropic 材质：各向异性反射（用于头发、拉丝金属）
- 子表面散射材质：大理石、皮肤等半透明材质
- Wetness Map：湿润度贴图

#### 光照系统
- IBL (Image-Based Lighting)：HDRI 环境贴图 → DDS 格式球面投射
- 多光源支持：点光源、球形光、聚光灯、IES 光照配置文件
- 体积光：所有光源类型都支持体积散射效果
- 时间系统：白天/夜晚切换

#### 屏幕空间效果
- **SSAO**：天空光近似阴影，8-28 个采样点可配置
- **SSR (Screen Space Reflection)**：光线步进实时反射
- **SSSSS (Screen Space Subsurface Scattering)**：皮肤次表面散射
- **Contact Shadow**：接触阴影（Ray-MMD 2.0 新增）

#### 大气效果
- 体积雾：立方体 / 球体形状（可模拟深海效果）
- 大气散射：物理正确的天空颜色
- 地面雾：低层雾效
- 光轴效果 (Light Shaft / God Rays)

#### 后处理
- Bloom：辉光
- Bokeh DOF：散景景深
- Eye Adaptation：眼睛适应（自动曝光）
- Tone Mapping：ACES-like / Reinhard / Hable / Hejl2015 / NaughtyDog
- Color Balance：色彩平衡
- FXAA / SMAA：抗锯齿

#### 描边
- 外轮廓线渲染
- 质量选项：禁用 / 启用 / 启用+SMAA / 启用+SSAA

### Ray-MMD 效果好的核心原因
不是单一技术，而是 **IBL + SSAO + SSR + 体积光 + DOF + Bloom** 的完整组合。每个技术单独看提升不大，组合起来质变。

---

## 3. Unity 生态 — lilToon / UTS3

### lilToon（社区最受欢迎）
**项目地址**: https://liltoon.org/
**DeepWiki**: https://deepwiki.com/lilxyzw/lilToon/1-overview-of-liltoon-shader-system

- 模块化架构，编译时 `LIL_FEATURE_*` 按需开关功能
- 支持 BRP / LWRP / URP / HDRP 全渲染管线
- 一键预设 + 直觉化自定义
- 防过曝、抗锯齿阴影
- 双发光层（Dual Emission）— 眼睛发光等效果
- 遮罩控制精细

**使用场景**: VRChat 头像标准着色器，也是 PMX → Unity 后最常用的着色器

### UTS3 (Unity Toon Shader)
**项目地址**: https://github.com/Unity-Technologies/com.unity.toonshader

- UTS2 的后继者，Uber Shader 架构
- 3 层颜色系统：Base Color → 1st Shade → 2nd Shade
- 加上 High Color、Rim Light、MatCap、Emissive
- 支持从赛璐珞风格到轻小说插画风格的各种设计

### MToon
- VRM 格式标准着色器
- 功能简单，注重跨平台互操作性
- 不如 lilToon / UTS3 强大

### 对比

| 着色器 | 适用场景 | 渲染管线 | 复杂度 | 社区热度 |
|--------|---------|---------|--------|---------|
| lilToon | VRChat/通用 Toon | BRP/URP/HDRP | 中 | ★★★★★ |
| UTS3 | 赛璐珞动画 | BRP/URP/HDRP | 高 | ★★★ |
| MToon | VRM 互操作 | BRP/URP | 低 | ★★ |

---

## 4. 原神式渲染 — 移动端标杆

**Shader 分析**: https://adrianmendez.artstation.com/projects/wJZ4Gg
**Unity 复刻**: https://github.com/festivities/PrimoToon
**Blender 复刻**: https://bjayers.com/blog/9oOD/blender-npr-recreating-the-genshin-impact-shader

### 核心技术

#### 光影过渡
```
NdotL = dot(Normal, LightDir)
shadow = smoothstep(threshold - 0.1, threshold, NdotL)
```
不用硬切（step），用 softness ≈ 0.1 的 smoothstep。
额外加一层更细的外阴影（微调 NdotL 偏移 + 更硬的过渡）。

#### 人工 SSS (Shadow Ramp)
**这是原神着色器最独特的地方。**

每个角色有独立的 Shadow Ramp 纹理：
- 光面边缘：淡黄色渐变（模拟光线穿透皮肤）
- 阴影内部：淡红色渐变（模拟血液散射）
- 头发：冷暖交替色带

这不是真正的 SSS 计算，而是用 ramp 纹理"画"出来的，性能极低，效果极好。

#### 金属渲染
**不用传统 PBR 的 metallic/roughness！**

用 MatCap（材质球捕捉）+ 梯度纹理：
```
matcap_uv = dot(Normal, ViewDir + LightDir)
metal_color = gradient_texture.sample(matcap_uv)
final = lerp(diffuse, metal_color, metallic_mask)
```
效果：清脆的金属反射，完全可控的艺术方向。

#### 面部阴影
NdotL 在脸上效果差（鼻子下巴会出奇怪阴影）。原神用**特殊面部阴影纹理**：
- R 通道：控制 0°-180° 旋转的阴影形状
- G 通道：控制 180°-360° 旋转的阴影形状
- 根据光源方向角度混合两个通道

#### 描边
**不是菲涅尔效果！** 是屏幕空间后处理：
- 读取角色轮廓
- Sobel 滤波器检测边缘
- 白色/深色描边叠加

#### 移动端优化策略
- LOD（Level of Detail）
- 烘焙光照
- 纹理流式加载
- 自定义 shader 按材质类型分离（皮肤/布料/金属/头发各一套）
- **不用 SSR、不用实时 GI、不用高质量 SSAO**

### 核心思想
> "Most of the shader's elements are faked both for better performance and for full control over art direction."
> — 大部分效果都是假的，为了性能和艺术可控性。

---

## 5. Blender 方案

### 导入工具
- mmd_tools 插件：PMX → Blender

### 关键发现
> "When you use Blender with MMD models, flat shader makes your character look like a cloth doll. Put subsurface scattering on every skin, hair, and fur shader."

**SSS 是 Blender 渲染 PMX 效果好的关键！**

### Eevee vs Cycles

| 特性 | Eevee | Cycles |
|------|-------|--------|
| 速度 | 实时 | 离线（分钟级） |
| IBL | ✅ | ✅ |
| SSAO | ✅ | 自动（光追） |
| SSS | ✅（近似） | ✅（精确） |
| 反射 | 屏幕空间 | 光线追踪 |
| 适用 | 预览/视频 | 最终渲染 |

---

## 6. 头发和皮肤的专项技术

### 头发：Kajiya-Kay 模型
经典的各向异性头发高光模型（1989 年 SIGGRAPH）：
```
specular = pow(sin(dot(Tangent, HalfVector)), shininess)
```
- 头发高光沿发丝方向形成光带（不是点状高光）
- 通常需要两层：主高光（颜色接近头发色）+ 偏移高光（更亮更窄）

**Marschner 模型**是 Kajiya-Kay 的升级版（Pixar RenderMan 使用），更物理正确但更复杂。
移动端推荐 Kajiya-Kay。

### 皮肤：次表面散射 (SSS)
- **真实 SSS**: 光线进入皮肤 → 被血液/组织散射 → 从附近位置射出，呈红色/橙色
- **近似方法（移动端）**:
  - Wrap Lighting: `NdotL_wrap = (NdotL + wrap) / (1 + wrap)`，wrap ≈ 0.5
  - 阴影面偏暖色：`shadow_color = mix(shadow, warm_tint, sss_strength)`
  - Shadow Ramp 纹理（原神方式）

### 眼睛
- 基础：漫反射纹理 + Sphere Map（球面贴图）
- 进阶：视差映射（Parallax Mapping）模拟眼球深度
- 高级：折射 + 焦散（离线渲染用）

---

## 7. 对 ios_mmd 的升级建议

### 当前状态 (v1.0-pbr)
- ✅ PBR (Cook-Torrance BRDF)
- ✅ IBL (球谐光照)
- ✅ ACES Tone Mapping
- ✅ VMD 动画播放
- ✅ Bullet 物理 + 陀螺仪
- ✅ 材质自动转换 (MMD → PBR)

### 升级优先级

| 优先级 | 技术 | 效果提升 | 工作量 | 参考 |
|--------|------|---------|--------|------|
| **P0** | SSS 皮肤 (Wrap Lighting) | 大 | 小 | 原神 Shadow Ramp |
| **P0** | 法线贴图 | 大 | 小 | 模型自带 _N.jpg |
| **P1** | Kajiya-Kay 头发高光 | 明显 | 中 | Ray-MMD Anisotropic |
| **P1** | Bloom 后处理 | 明显 | 中 | Ray-MMD |
| **P2** | SSAO | 明显 | 大 | Ray-MMD |
| **P2** | Sobel 描边 | 风格化 | 中 | 原神 |
| **P3** | Shadow Ramp 纹理 | 精细 | 中 | 原神 |
| **P3** | MatCap 金属 | 精细 | 中 | 原神 |
| **P3** | 面部阴影纹理 | 精细 | 大 | 原神 |
| **P4** | DOF 景深 | 锦上添花 | 中 | Ray-MMD |
| **P4** | 体积雾/光轴 | 氛围 | 大 | Ray-MMD |

### 最小投入最大提升路线
1. **SSS Wrap Lighting** — fragment shader 加 10 行代码，皮肤立刻有质感
2. **法线贴图** — 模型自带，只需加载 + TBN 变换
3. **Bloom** — 最简单的后处理，提取亮部 + 模糊 + 叠加

---

## 参考资料

- [Ray-MMD GitHub](https://github.com/ray-cast/ray-mmd)
- [Ray-MMD 2.0](https://github.com/norz3n/ray-mmd-2.0)
- [Ray-MMD Materials Wiki](https://github.com/ray-cast/ray-mmd/wiki/Materials)
- [Ray-MMD Atmospheric Effects](https://deepwiki.com/ray-cast/ray-mmd/5-atmospheric-effects)
- [lilToon Official](https://liltoon.org/)
- [lilToon DeepWiki](https://deepwiki.com/lilxyzw/lilToon/1-overview-of-liltoon-shader-system)
- [Unity Toon Shader (UTS3)](https://github.com/Unity-Technologies/com.unity.toonshader)
- [UTS2 Project](https://github.com/unity3d-jp/UnityChanToonShaderVer2_Project)
- [Genshin Impact Shader Breakdown (Adrian Mendez)](https://adrianmendez.artstation.com/projects/wJZ4Gg)
- [PrimoToon - Genshin Shader Recreation](https://github.com/festivities/PrimoToon)
- [Blender NPR: Recreating Genshin Shader](https://bjayers.com/blog/9oOD/blender-npr-recreating-the-genshin-impact-shader)
- [Genshin Impact Mobile Optimization](https://www.animaticsassetstore.com/2024/09/13/how-genshin-impact-3d-models-are-optimized-for-mobile-performance/)
- [Advanced MMD Rendering Tutorial](https://ryunochie.tumblr.com/post/656441667965091842/advanced-mmd-rendering-tutorial-and-why-you)
- [Ray-MMD Lighting Tips](https://ryunochie.tumblr.com/post/660863324216524800/ray-mmd-lighting-tips-a-translation-by-ryuu)
- [Kajiya-Kay Hair Rendering](https://godotforums.org/d/33625-kajiya-kay-hair-rendering)
- [Pixar RenderMan Marschner Hair](https://www.fxguide.com/fxfeatured/pixars-renderman-marschner-hair/)
- [UE4 as MMD Guide](https://www.deviantart.com/thehoodieguy02/journal/How-to-make-Unreal-Engine-4-your-new-MMD-Pt-2-892643542)

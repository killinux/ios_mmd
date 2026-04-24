# Vulkan 与 PMX 渲染方案调研

> 调研时间：2026-04-23
> 目标：了解 Vulkan 在 PMX 渲染中的角色，评估跨平台方案

## 1. 总览

| 方案 | 跨平台 | iOS 性能 | 工作量 | 渲染质量上限 |
|------|--------|---------|--------|-------------|
| **Metal 原生**（当前） | 仅 iOS | 最好 | 已完成 | ★★★★★ |
| **saba Vulkan + MoltenVK** | iOS+Android+PC | 好（-5~10%） | 中 | ★★★ |
| **自写 Vulkan + MoltenVK** | iOS+Android+PC | 好 | 大 | ★★★★★ |
| **WebGPU** | 全平台+浏览器 | 一般 | 中 | ★★★ |

---

## 2. saba 自带 Vulkan Viewer

### 概述
saba 库（我们已经在用它的 C++ 核心做 PMX 解析和动画）自带三个渲染示例：
- OpenGL 4.1 viewer
- DirectX 11 viewer
- **Vulkan 1.0.65 viewer**

**源码位置**: `saba/example/simple_mmd_viewer_vulkan.cpp`
**参考**: https://github.com/benikabocha/saba/blob/master/example/simple_mmd_viewer_vulkan.cpp

### 技术细节

| 特性 | 实现 |
|------|------|
| Vulkan 版本 | 1.0.65 |
| 着色器格式 | 预编译 SPIR-V |
| 渲染 Pass | MMD 材质 + 描边(edge) + 地面阴影(ground shadow) |
| MSAA | 支持（可配置最高 8x） |
| 动画 | VMD 30fps，调用 UpdateAllAnimation |
| 纹理加载 | STB Image |
| 窗口 | GLFW |
| 数学库 | GLM |

### 渲染管线

```
Pass 1: MMD Main (mmd.vert.spv + mmd.frag.spv)
  - 材质渲染，逐 submesh 绑定纹理
  - Descriptor set: uniform buffer + texture sampler

Pass 2: Edge (mmd_edge.vert.spv + mmd_edge.frag.spv)
  - 背面扩张描边
  - 每材质可配置 edge size

Pass 3: Ground Shadow (mmd_ground_shadow.vert.spv + mmd_ground_shadow.frag.spv)
  - 半透明红棕色地面投影阴影
  - shadow color: rgba(0.4, 0.2, 0.2, 0.7)
```

### 配置系统
通过 `init.json` 或 `init.lua` 配置：
```json
{
  "MSAAEnable": true,
  "MSAACount": 8,
  "Camera": {
    "Center": [0, 10, 0],
    "Eye": [0, 10, -50],
    "NearClip": 1.0,
    "FarClip": 10000.0
  }
}
```

### 局限性
- 渲染质量是基础级别（简单光照 + 描边 + 地面阴影）
- 没有 PBR、IBL、SSAO、Bloom 等进阶效果
- 是示例代码，不是生产级渲染器

---

## 3. MoltenVK — iOS 上运行 Vulkan 的桥梁

### 概述
MoltenVK 是 Khronos 官方维护的 Vulkan 到 Metal 翻译层，让 Vulkan 应用直接跑在 Apple 平台上。

**项目地址**: https://github.com/KhronosGroup/MoltenVK
**许可证**: Apache 2.0

### 版本历史（2025-2026）

| 版本 | 日期 | Vulkan 支持 |
|------|------|------------|
| 1.3.0 | 2025-05-02 | Vulkan 1.3 核心 |
| 1.4.0 | 2025-08-20 | Vulkan 1.4 核心 |

### 关键能力

- **Vulkan 1.4 核心 API 近乎完整支持**
- **100+ Vulkan 扩展**支持
- SPIR-V 着色器 → Metal Shading Language **自动转换**
- 支持平台：macOS / iOS / tvOS / visionOS / 模拟器
- **可上架 App Store**：不使用私有 API
- 动态渲染 (VK_KHR_dynamic_rendering)
- 扩展动态状态 (VK_EXT_extended_dynamic_state)
- Shader 子组操作

### 性能

- 翻译层开销约 **5-10%**
- 对于 PMX 模型渲染（GPU 负载不重）完全可接受
- iOS 模拟器上没有 Vulkan loader，需直接链接 MoltenVK
- 发布版建议直接使用 MoltenVK 而非 Vulkan loader（减少开销）

### iOS 集成方式

```
你的 Vulkan 代码
    ↓ Vulkan API 调用
MoltenVK 翻译层
    ↓ 转换为 Metal API 调用
Apple Metal 驱动
    ↓
GPU
```

### 替代方案
Mesa 的 **KosmicKrisp** (Vulkan-On-Metal) 已达到 MoltenVK 功能对等，LunarG 在 Apple Silicon 上通过了 Vulkan 1.3 一致性测试。

---

## 4. WebGPU 方案

### reze-engine
**项目地址**: https://github.com/AmyangXYZ/reze-engine

最新的 WebGPU MMD 渲染器（2025 年发布）：
- 最小依赖（仅 Ammo.js 做物理）
- PMX 模型解析 + VMD 动画
- 跑在浏览器中，底层自动适配：
  - Android → Vulkan
  - iOS → Metal
  - PC → Vulkan / D3D12

### WebGPU vs Vulkan

| 维度 | WebGPU | Vulkan |
|------|--------|--------|
| 抽象层级 | 高（类似 Metal） | 低（显式控制） |
| 性能 | 稍低（浏览器开销） | 接近原生 |
| 跨平台 | 浏览器即跨平台 | 需要 MoltenVK 适配 iOS |
| 开发效率 | 高（JS/TS/Rust） | 低（C/C++） |
| 适用场景 | 轻量级、演示、Web | 游戏、专业应用 |

### 参考教程
- [How to Render an MMD Anime Character with WebGPU from Scratch](https://dev.to/amyangxyz/how-to-render-an-mmd-anime-character-with-webgpu-from-scratch-13cm)

---

## 5. 跑通 saba Vulkan Viewer 在 iOS 上的路线

如果要把 saba 的 Vulkan viewer 移植到 iOS：

### 步骤

1. **集成 MoltenVK**
   - 下载 Vulkan SDK（含 MoltenVK）
   - 链接 `MoltenVK.xcframework` 到 Xcode 项目

2. **编译 saba Vulkan viewer**
   - 替换 GLFW 窗口管理 → UIKit/CAMetalLayer
   - SPIR-V 着色器可直接使用（MoltenVK 自动转 MSL）
   - 保留 GLM 数学库

3. **替换着色器为 PBR**
   - 用 glslc 编译 GLSL → SPIR-V
   - 我们的 PBR 着色器（Cook-Torrance + IBL）改写为 GLSL
   - 编译为 .spv 文件

4. **添加进阶效果**
   - 和 Metal 方案一样：SSAO、Bloom、SSS 等
   - 但着色器用 GLSL 写，通过 SPIR-V 跨平台

### 工作量评估

| 任务 | 工作量 | 说明 |
|------|--------|------|
| MoltenVK 集成 | 1-2 天 | 替换窗口管理 |
| saba Vulkan viewer 移植 | 3-5 天 | 适配 iOS 生命周期 |
| PBR 着色器迁移 | 2-3 天 | Metal → GLSL + SPIR-V |
| 进阶效果 | 5-10 天 | SSAO/Bloom/SSS |
| **总计** | **~3 周** | |

---

## 6. 对比分析：Metal 原生 vs Vulkan+MoltenVK

### Metal 原生（当前方案）

**优势**：
- 零翻译开销，iOS 上性能最优
- Apple 原生工具链：Xcode Metal debugger、GPU profiler
- Metal Performance Shaders 可用
- 着色器用 MSL 编写，Apple 文档完善

**劣势**：
- 仅限 Apple 平台
- 着色器不可复用到 Android/PC

### Vulkan + MoltenVK

**优势**：
- **一套着色器跨 iOS + Android + PC + Linux**
- Vulkan 生态更大：更多开源 shader / 工具 / 教程
- SPIR-V 是中间格式，可从 GLSL/HLSL 编译
- saba 已有 Vulkan viewer 可复用
- 社区有大量 Vulkan PBR / Toon 着色器参考

**劣势**：
- MoltenVK 翻译层有 5-10% 性能损耗
- 不是所有 Vulkan 扩展都支持
- 调试工具不如 Metal 原生好用
- 增加了项目复杂度（需要同时理解 Vulkan 和 Metal）

### 决策建议

| 场景 | 推荐方案 |
|------|---------|
| 只做 iOS，追求最佳性能 | **Metal 原生** |
| iOS + Android，快速上线 | **saba Vulkan + MoltenVK** |
| iOS + Android + PC，长期项目 | **自写 Vulkan 渲染器 + MoltenVK** |
| 轻量级 Web 演示 | **WebGPU (reze-engine)** |

---

## 7. 相关资源

### Vulkan + MMD
- [saba Vulkan Viewer 源码](https://github.com/benikabocha/saba/blob/master/example/simple_mmd_viewer_vulkan.cpp)
- [saba GitHub](https://github.com/benikabocha/saba)
- [dexvt-saba-mmd (另一个 saba 基础的 MMD viewer)](https://github.com/onlyuser/dexvt-saba-mmd)

### MoltenVK
- [MoltenVK GitHub](https://github.com/KhronosGroup/MoltenVK)
- [MoltenVK Runtime User Guide](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md)
- [MoltenVK Release Notes](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md)
- [Vulkan SDK (含 MoltenVK)](https://vulkan.lunarg.com/sdk/home)

### WebGPU + MMD
- [reze-engine GitHub](https://github.com/AmyangXYZ/reze-engine)
- [WebGPU MMD 渲染教程](https://dev.to/amyangxyz/how-to-render-an-mmd-anime-character-with-webgpu-from-scratch-13cm)

### Vulkan PBR 参考实现
- [LightingInPBR (OpenGL, 但 shader 逻辑可移植)](https://github.com/PixelSenseiAvi/LightingInPBR)
- [Vulkan PBR 教程 (learnopengl 移植)](https://learnopengl.com/PBR/Theory)

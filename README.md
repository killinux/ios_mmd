# ios_mmd — iOS MMD 播放器

加载 PMX 模型，播放 VMD 动作的 iOS App。

## 架构设计

```
┌──────────────────────────────────────┐
│         SwiftUI App Shell            │
│  (文件选择器、播放控制、设置)           │
├──────────────────────────────────────┤
│      MetalMMDRenderer (Swift)        │
│  (MTKView, 渲染管线, Toon着色器)      │
├──────────────────────────────────────┤
│      SabaBridge (ObjC++ Wrapper)     │
│  (.h 纯ObjC接口, .mm 调用saba C++)   │
├──────────────────────────────────────┤
│         saba C++ Core (静态库)        │
│  src/Saba/Base + Model/MMD          │
│  + GLM + Bullet Physics             │
└──────────────────────────────────────┘
```

### 四层架构

1. **SwiftUI App Shell** — 纯 Swift 界面层，文件选择、播放控制、设置面板
2. **MetalMMDRenderer** — Metal 渲染层，管理 MTKView、渲染管线、着色器、纹理、相机
3. **SabaBridge** — ObjC++ 桥接层，将 saba 的 C++ API 封装为 ObjC 接口供 Swift 调用
4. **saba C++ Core** — C++ 解析和动画计算核心，包含 PMX/VMD 解析、IK、物理、Morph

### 为什么用 ObjC++ 桥接而不是 Swift/C++ interop

saba 大量使用 C++ 模板、STL 容器和 `std::unique_ptr`，Swift/C++ interop 对这些支持有限。ObjC++ wrapper 可以完全控制 C++ 对象生命周期，更稳定。

## 技术选型

### saba (MIT License)
- GitHub: https://github.com/benikabocha/saba
- 最完整的 MMD C++ 库：PMX/PMD/VMD/VPD 解析、IK 求解、Bullet 物理、所有 Morph 类型
- 核心库 `src/Saba/` 无渲染依赖，输出裸顶点数组，可直接喂给 Metal
- 依赖：GLM（header-only 数学库）+ Bullet Physics（刚体物理引擎）

### 通信方式
- saba 在 CPU 上计算完整的骨骼动画 + 顶点变形
- 每帧通过 `GetUpdatePositions()` / `GetUpdateNormals()` / `GetUpdateUVs()` 输出顶点数据
- Metal 端用三重缓冲接收顶点数据，GPU 只负责渲染

## 功能

| 功能 | 说明 | 实现阶段 |
|------|------|----------|
| PMX 模型加载 | 解析 PMX 格式，显示静态 T-pose | Phase 1 |
| 纹理渲染 | TGA/PNG/BMP 纹理加载 | Phase 1 |
| 轨道相机 | 旋转、平移、缩放手势控制 | Phase 1 |
| VMD 动画播放 | 骨骼关键帧动画 + 贝塞尔插值 | Phase 2 |
| 播放控制 | 播放/暂停、进度条、速度调节 | Phase 2 |
| IK 逆运动学 | 脚部落地等约束求解 | Phase 3 |
| Morph 表情 | 面部表情、顶点/材质变形 | Phase 3 |
| Bullet 物理 | 头发弹跳、裙子摆动 | Phase 4 |
| Toon 着色 | 球面贴图、Toon 渐变、边缘线 | Phase 5 |
| 相机动画 | VMD 相机关键帧 | Phase 5 |
| 文件管理 | Files app 导入 PMX/VMD | Phase 5 |

## 项目结构

```
ios_mmd/
├── ios_mmd.xcodeproj
├── ios_mmd/
│   ├── App/
│   │   ├── ios_mmdApp.swift              # @main App 入口
│   │   └── ContentView.swift             # 根视图
│   ├── Views/
│   │   ├── ModelViewerView.swift         # UIViewRepresentable 包装 MTKView
│   │   ├── PlaybackControlsView.swift    # 播放控制条
│   │   └── FilePickerView.swift          # 文件选择器
│   ├── Renderer/
│   │   ├── MetalMMDRenderer.swift        # MTKViewDelegate 渲染循环
│   │   ├── Camera.swift                  # 轨道相机 + 手势
│   │   ├── TextureManager.swift          # 纹理加载管理
│   │   └── Shaders/
│   │       ├── MMDShaderTypes.h          # Swift + Metal 共享结构体定义
│   │       └── MMDShaders.metal          # Toon 顶点 + 片段着色器
│   ├── Bridge/
│   │   ├── SabaBridge.h                  # 纯 ObjC 接口（无 C++ 暴露）
│   │   ├── SabaBridge.mm                 # ObjC++ 实现，调用 saba C++
│   │   ├── SabaModelData.h              # 顶点/材质 ObjC 数据结构
│   │   └── ios_mmd-Bridging-Header.h     # Swift 桥接头文件
│   └── Resources/
│       └── DefaultToon/                  # 内置 toon 渐变纹理 (toon01-10)
├── Libraries/
│   ├── saba/                             # git submodule
│   ├── glm/                              # git submodule (header-only)
│   └── bullet3/                          # git submodule
└── ios_mmd.xcconfig                      # 编译配置
```

## 关键接口设计

### ObjC++ Bridge (`SabaBridge.h`)

```objc
@interface SabaMMDModel : NSObject

// 加载
- (BOOL)loadModelFromPath:(NSString *)path;
- (BOOL)loadAnimationFromPath:(NSString *)path;

// 动画更新（每帧调用）
- (void)updateAnimation:(float)deltaTime;
- (void)resetPhysics;

// 顶点数据（指向 saba 内部数组，零拷贝）
@property (readonly) const float *positions;     // vec3 数组
@property (readonly) const float *normals;       // vec3 数组
@property (readonly) const float *uvs;           // vec2 数组
@property (readonly) const uint32_t *indices;    // 索引数组
@property (readonly) NSInteger vertexCount;
@property (readonly) NSInteger indexCount;

// 子网格 / 材质
@property (readonly) NSArray<SabaSubMesh *> *subMeshes;
@property (readonly) float maxAnimationTime;

@end
```

### Metal 顶点布局

```
每顶点 32 字节:
  Attribute 0: float3 position  (offset 0)
  Attribute 1: float3 normal    (offset 12)
  Attribute 2: float2 uv        (offset 24)
```

三重缓冲（triple buffer），每帧 `memcpy` saba 输出到 shared-storage `MTLBuffer`。10 万顶点模型约 3.2MB/帧，iPhone 轻松承受。

### 动画管线（每帧执行顺序）

```
BeginAnimation()
  → VMDAnimation::Evaluate(currentTime)     // 计算关键帧插值
  → UpdateMorphAnimation()                  // 应用表情变形
  → UpdateNodeAnimation(prePhysics=false)   // 骨骼变换 + IK
  → UpdatePhysicsAnimation(deltaTime)       // Bullet 物理步进
  → UpdateNodeAnimation(prePhysics=true)    // 物理后骨骼更新
  → Update()                               // 计算最终顶点位置
EndAnimation()
```

## 编译配置

### Build Settings (xcconfig)

```
CLANG_CXX_LANGUAGE_STANDARD = c++14
CLANG_CXX_LIBRARY = libc++
GCC_PREPROCESSOR_DEFINITIONS = USE_BULLET_PHYSICS=1
HEADER_SEARCH_PATHS = $(PROJECT_DIR)/Libraries/glm \
                      $(PROJECT_DIR)/Libraries/saba/src \
                      $(PROJECT_DIR)/Libraries/bullet3/src
IPHONEOS_DEPLOYMENT_TARGET = 17.0
```

### 依赖库

| 库 | 用途 | 引入方式 |
|----|------|----------|
| saba | PMX/VMD 解析 + 动画计算 | git submodule，编译 `src/Saba/` |
| GLM | 向量/矩阵数学 | git submodule，header-only |
| Bullet3 | 物理模拟（头发/裙子） | git submodule，编译 3 个模块 |

## 已知风险

| 风险 | 影响 | 应对 |
|------|------|------|
| PMX 文件用 Shift-JIS 编码 | 日文纹理路径解析 | saba 内置 SJIS→Unicode 转换表 |
| iOS security-scoped URL | 文件访问权限 | bridge 层调用 `startAccessingSecurityScopedResource()` |
| Bullet ARM64 编译警告 | 编译噪音 | 添加 `-Wno-deprecated` |
| 大模型内存 | 50+ 纹理的模型 | Instruments 监控，使用 mipmap |

## 使用方法

1. 用 Xcode 打开 `ios_mmd.xcodeproj`
2. 选择 iPhone 模拟器或真机
3. Cmd+R 运行
4. 点击界面上的"打开文件"按钮，选择 PMX 模型文件
5. 模型加载后可手势旋转/缩放查看
6. 点击"加载动作"选择 VMD 文件
7. 使用底部播放控制条控制动画

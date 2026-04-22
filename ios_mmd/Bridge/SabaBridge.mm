#import "SabaBridge.h"

#include <memory>
#include <string>
#include <Saba/Model/MMD/PMXModel.h>
#include <Saba/Model/MMD/VMDFile.h>
#include <Saba/Model/MMD/VMDAnimation.h>
#include <Saba/Model/MMD/MMDPhysics.h>
#include <btBulletDynamicsCommon.h>

// MARK: - SabaSubMesh

@implementation SabaSubMesh
@end

// MARK: - SabaMaterialInfo

@implementation SabaMaterialInfo
@end

// MARK: - SabaMMDModel

@interface SabaMMDModel () {
    std::shared_ptr<saba::PMXModel> _model;
    std::unique_ptr<saba::VMDAnimation> _vmdAnim;
    float _currentFrame;
}
@end

@implementation SabaMMDModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentFrame = 0.0f;
    }
    return self;
}

- (BOOL)loadModelFromPath:(NSString *)path mmdDataDir:(NSString *)dataDir {
    _model = std::make_shared<saba::PMXModel>();
    std::string cppPath = [path UTF8String];
    std::string cppDataDir = [dataDir UTF8String];
    if (!_model->Load(cppPath, cppDataDir)) {
        _model.reset();
        return NO;
    }
    _model->InitializeAnimation();
    _model->BeginAnimation();
    _model->UpdateMorphAnimation();
    _model->UpdateNodeAnimation(false);
    _model->UpdatePhysicsAnimation(0);
    _model->UpdateNodeAnimation(true);
    _model->Update();
    _model->EndAnimation();

    // Debug: print first few vertex positions and index info
    size_t vc = _model->GetVertexCount();
    const glm::vec3 *pos = _model->GetUpdatePositions();
    if (pos && vc > 0) {
        NSLog(@"[MMD] First vertex pos: (%f, %f, %f)", pos[0].x, pos[0].y, pos[0].z);
        NSLog(@"[MMD] IndexElementSize: %zu", _model->GetIndexElementSize());
        NSLog(@"[MMD] IndexCount: %zu", _model->GetIndexCount());
    }
    return YES;
}

- (BOOL)loadAnimationFromPath:(NSString *)path {
    if (!_model) return NO;

    saba::VMDFile vmdFile;
    std::string cppPath = [path UTF8String];
    if (!saba::ReadVMDFile(&vmdFile, cppPath.c_str())) {
        return NO;
    }

    _vmdAnim = std::make_unique<saba::VMDAnimation>();
    if (!_vmdAnim->Create(_model)) {
        _vmdAnim.reset();
        return NO;
    }
    if (!_vmdAnim->Add(vmdFile)) {
        _vmdAnim.reset();
        return NO;
    }

    return YES;
}

- (void)initializeAnimation {
    if (!_model) return;
    _currentFrame = 0.0f;
    if (_vmdAnim) {
        _model->BeginAnimation();
        _model->UpdateAllAnimation(_vmdAnim.get(), 0.0f, 0.0f);
        _model->EndAnimation();
    }
}

- (void)updateAnimation:(float)frame physicsElapsed:(float)elapsed {
    if (!_model || !_vmdAnim) return;
    _currentFrame = frame;
    _model->BeginAnimation();
    _model->UpdateAllAnimation(_vmdAnim.get(), frame, elapsed);
    _model->EndAnimation();
}

- (NSInteger)vertexCount {
    if (!_model) return 0;
    return (NSInteger)_model->GetVertexCount();
}

- (NSInteger)indexCount {
    if (!_model) return 0;
    return (NSInteger)_model->GetIndexCount();
}

- (NSInteger)indexElementSize {
    if (!_model) return 0;
    return (NSInteger)_model->GetIndexElementSize();
}

- (void)copyInterleavedVertices:(float *)dest {
    if (!_model) return;

    size_t count = _model->GetVertexCount();
    const glm::vec3 *positions = _model->GetUpdatePositions();
    const glm::vec3 *normals = _model->GetUpdateNormals();
    const glm::vec2 *uvs = _model->GetUpdateUVs();

    for (size_t i = 0; i < count; i++) {
        size_t base = i * 8;
        dest[base + 0] = positions[i].x;
        dest[base + 1] = positions[i].y;
        dest[base + 2] = positions[i].z;
        dest[base + 3] = normals[i].x;
        dest[base + 4] = normals[i].y;
        dest[base + 5] = normals[i].z;
        dest[base + 6] = uvs[i].x;
        dest[base + 7] = uvs[i].y;
    }
}

- (const void *)rawIndices {
    if (!_model) return nullptr;
    return _model->GetIndices();
}

- (NSArray<SabaSubMesh *> *)subMeshes {
    if (!_model) return @[];

    size_t count = _model->GetSubMeshCount();
    const saba::MMDSubMesh *subs = _model->GetSubMeshes();
    NSMutableArray<SabaSubMesh *> *result = [NSMutableArray arrayWithCapacity:count];

    for (size_t i = 0; i < count; i++) {
        SabaSubMesh *sm = [[SabaSubMesh alloc] init];
        sm.beginIndex = (int)subs[i].m_beginIndex;
        sm.vertexCount = (int)subs[i].m_vertexCount;
        sm.materialID = (int)subs[i].m_materialID;
        [result addObject:sm];
    }
    return [result copy];
}

- (NSArray<SabaMaterialInfo *> *)materials {
    if (!_model) return @[];

    size_t count = _model->GetMaterialCount();
    const saba::MMDMaterial *mats = _model->GetMaterials();
    NSMutableArray<SabaMaterialInfo *> *result = [NSMutableArray arrayWithCapacity:count];

    for (size_t i = 0; i < count; i++) {
        SabaMaterialInfo *mi = [[SabaMaterialInfo alloc] init];
        mi.diffuseR = mats[i].m_diffuse.x;
        mi.diffuseG = mats[i].m_diffuse.y;
        mi.diffuseB = mats[i].m_diffuse.z;
        mi.alpha = mats[i].m_alpha;
        mi.specularR = mats[i].m_specular.x;
        mi.specularG = mats[i].m_specular.y;
        mi.specularB = mats[i].m_specular.z;
        mi.specularPower = mats[i].m_specularPower;
        mi.ambientR = mats[i].m_ambient.x;
        mi.ambientG = mats[i].m_ambient.y;
        mi.ambientB = mats[i].m_ambient.z;
        mi.edgeSize = mats[i].m_edgeSize;

        std::string texPath = mats[i].m_texture;
        if (!texPath.empty()) {
            mi.texturePath = [NSString stringWithUTF8String:texPath.c_str()];
        } else {
            mi.texturePath = @"";
        }

        [result addObject:mi];
    }
    return [result copy];
}

- (void)setGravityX:(float)x y:(float)y z:(float)z {
    if (!_model) return;
    auto *physics = _model->GetMMDPhysics();
    if (!physics) return;
    auto *world = physics->GetDynamicsWorld();
    if (!world) return;
    world->setGravity(btVector3(x, y, z));
}

- (void)updatePhysics:(float)elapsed {
    if (!_model) return;
    _model->BeginAnimation();
    _model->UpdatePhysicsAnimation(elapsed);
    _model->UpdateNodeAnimation(true);
    _model->Update();
    _model->EndAnimation();
}

@end

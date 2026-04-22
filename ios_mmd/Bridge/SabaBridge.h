#import <Foundation/Foundation.h>
#import "SabaModelData.h"

NS_ASSUME_NONNULL_BEGIN

@interface SabaMMDModel : NSObject

- (BOOL)loadModelFromPath:(NSString *)path mmdDataDir:(NSString *)dataDir NS_SWIFT_NAME(loadModel(path:dataDir:));
- (BOOL)loadAnimationFromPath:(NSString *)path;
- (void)initializeAnimation;
- (void)updateAnimation:(float)frame physicsElapsed:(float)elapsed;

@property (nonatomic, readonly) NSInteger vertexCount;
@property (nonatomic, readonly) NSInteger indexCount;
@property (nonatomic, readonly) NSInteger indexElementSize;

/// Copies pos3+normal3+uv2 interleaved (8 floats = 32 bytes per vertex) into dest.
/// Caller must allocate at least vertexCount * 8 floats.
- (void)copyInterleavedVertices:(float *)dest;

/// Returns a pointer to the raw index data owned by the model.
- (const void *)rawIndices;

@property (nonatomic, readonly) NSArray<SabaSubMesh *> *subMeshes;
@property (nonatomic, readonly) NSArray<SabaMaterialInfo *> *materials;

@end

NS_ASSUME_NONNULL_END

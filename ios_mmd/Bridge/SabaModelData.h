#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SabaSubMesh : NSObject
@property (nonatomic) int beginIndex;
@property (nonatomic) int vertexCount;
@property (nonatomic) int materialID;
@end

@interface SabaMaterialInfo : NSObject
@property (nonatomic) float diffuseR, diffuseG, diffuseB, alpha;
@property (nonatomic) float specularR, specularG, specularB, specularPower;
@property (nonatomic) float ambientR, ambientG, ambientB;
@property (nonatomic, copy) NSString *texturePath;
@property (nonatomic) float edgeSize;
@end

NS_ASSUME_NONNULL_END

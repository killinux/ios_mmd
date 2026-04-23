import MetalKit
import simd

class MetalMMDRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let camera = Camera()

    private var pipelineState: MTLRenderPipelineState!
    private var depthStateWrite: MTLDepthStencilState!
    private var depthStateNoWrite: MTLDepthStencilState!
    private var samplerState: MTLSamplerState!
    private var dummyTexture: MTLTexture!

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexType: MTLIndexType = .uint16

    private var model: SabaMMDModel?
    private var subMeshes: [SabaSubMesh] = []
    private var materialInfos: [SabaMaterialInfo] = []
    private var textures: [Int: MTLTexture] = [:]

    private var viewportSize: CGSize = CGSize(width: 1, height: 1)
    private var lastFrameTime: CFTimeInterval = 0
    private let motion = MotionManager.shared

    var isPlaying = false
    var currentFrame: Float = 0
    var playbackSpeed: Float = 1.0
    private var animationLoaded = false

    // Studio lighting SH coefficients (warm key from upper-left, cool fill, warm ground bounce)
    private let studioSH: [SIMD3<Float>] = [
        SIMD3<Float>(0.7, 0.7, 0.8),       // L00 - ambient base
        SIMD3<Float>(0.0, 0.1, 0.1),       // L1-1 - top/bottom
        SIMD3<Float>(0.2, 0.2, 0.25),      // L10 - front/back
        SIMD3<Float>(0.15, 0.12, 0.1),     // L11 - left/right
        SIMD3<Float>(0.0, 0.0, 0.0),       // L2-2
        SIMD3<Float>(0.0, 0.0, 0.0),       // L2-1
        SIMD3<Float>(-0.05, -0.05, -0.05), // L20
        SIMD3<Float>(0.0, 0.0, 0.0),       // L21
        SIMD3<Float>(0.02, 0.01, 0.0),     // L22
    ]

    init?(mtkView: MTKView) {
        guard let device = mtkView.device,
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue

        super.init()

        mtkView.sampleCount = 1

        buildPipelines(mtkView: mtkView)
        buildDepthState()
        buildSamplerState()
        buildDummyTexture()
    }

    private func buildPipelines(mtkView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load Metal shader library")
        }

        let mainDesc = MTLRenderPipelineDescriptor()
        mainDesc.vertexFunction = library.makeFunction(name: "mmd_vertex")
        mainDesc.fragmentFunction = library.makeFunction(name: "mmd_fragment")
        mainDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        mainDesc.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        mainDesc.sampleCount = mtkView.sampleCount
        mainDesc.colorAttachments[0].isBlendingEnabled = true
        mainDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        mainDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        mainDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        mainDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: mainDesc)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    private func buildDepthState() {
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = .less
        desc.isDepthWriteEnabled = true
        depthStateWrite = device.makeDepthStencilState(descriptor: desc)

        let descNoWrite = MTLDepthStencilDescriptor()
        descNoWrite.depthCompareFunction = .less
        descNoWrite.isDepthWriteEnabled = false
        depthStateNoWrite = device.makeDepthStencilState(descriptor: descNoWrite)
    }

    private func buildSamplerState() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .repeat
        desc.tAddressMode = .repeat
        samplerState = device.makeSamplerState(descriptor: desc)
    }

    private func buildDummyTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = .shaderRead
        dummyTexture = device.makeTexture(descriptor: desc)
        let white: [UInt8] = [255, 255, 255, 255]
        dummyTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: white, bytesPerRow: 4)
    }

    func loadModel(path: String) {
        let modelDir = (path as NSString).deletingLastPathComponent
        print("[MMD] Loading model: \(path)")

        let sabaModel = SabaMMDModel()
        guard sabaModel.loadModel(path: path, dataDir: modelDir) else {
            print("[MMD] FAILED to load PMX model")
            return
        }

        let vc = Int(sabaModel.vertexCount)
        let ic = Int(sabaModel.indexCount)
        print("[MMD] Model loaded: \(vc) vertices, \(ic) indices, \(sabaModel.subMeshes.count) submeshes")

        self.model = sabaModel
        self.subMeshes = sabaModel.subMeshes
        self.materialInfos = sabaModel.materials

        let byteCount = vc * 8 * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
        if let vb = vertexBuffer {
            let dest = vb.contents().bindMemory(to: Float.self, capacity: vc * 8)
            sabaModel.copyInterleavedVertices(dest)
        }

        let elemSize = Int(sabaModel.indexElementSize)
        indexType = (elemSize == 4) ? .uint32 : .uint16
        let indexByteCount = ic * elemSize
        let rawPtr = sabaModel.rawIndices()
        indexBuffer = device.makeBuffer(bytes: rawPtr, length: indexByteCount, options: .storageModeShared)

        loadTextures(modelDir: modelDir)

        motion.start()
        lastFrameTime = CACurrentMediaTime()
        animationLoaded = false
        currentFrame = 0
        isPlaying = false
    }

    private func loadTextures(modelDir: String) {
        textures.removeAll()
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: true
        ]

        for (i, mat) in materialInfos.enumerated() {
            let texPath = mat.texturePath ?? ""
            if texPath.isEmpty { continue }

            let fullPath: String
            if (texPath as NSString).isAbsolutePath {
                fullPath = texPath
            } else {
                fullPath = (modelDir as NSString).appendingPathComponent(texPath)
            }

            let url = URL(fileURLWithPath: fullPath)
            do {
                let tex = try loader.newTexture(URL: url, options: options)
                textures[i] = tex
            } catch {
                print("[MMD] Warning: texture \(texPath): \(error.localizedDescription)")
            }
        }
    }

    func loadAnimation(path: String) {
        guard let model = model else { return }
        print("[MMD] Loading animation: \(path)")
        if model.loadAnimation(fromPath: path) {
            model.initializeAnimation()
            animationLoaded = true
            currentFrame = 0
            isPlaying = true
            print("[MMD] Animation loaded, playing")
        } else {
            print("[MMD] FAILED to load animation")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    private func buildSceneUniforms() -> MMDSceneUniforms {
        let aspect = Float(viewportSize.width / max(viewportSize.height, 1))
        let projection = Camera.perspective(fovYDegrees: 30.0, aspect: aspect, near: 0.1, far: 1000.0)

        var scene = MMDSceneUniforms()
        scene.modelMatrix = matrix_identity_float4x4
        scene.viewMatrix = camera.viewMatrix
        scene.projectionMatrix = projection
        scene.lightDirection = SIMD3<Float>(-0.5, -1.0, -0.5)
        scene._pad0 = 0
        scene.lightColor = SIMD3<Float>(1.0, 0.98, 0.95)
        scene._pad1 = 0
        scene.cameraPosition = camera.cameraPosition
        scene.ambientIntensity = 1.0

        // Pack SH coefficients into simd_float4 (xyz = coeff, w = 0)
        scene.sh.0 = SIMD4<Float>(studioSH[0].x, studioSH[0].y, studioSH[0].z, 0)
        scene.sh.1 = SIMD4<Float>(studioSH[1].x, studioSH[1].y, studioSH[1].z, 0)
        scene.sh.2 = SIMD4<Float>(studioSH[2].x, studioSH[2].y, studioSH[2].z, 0)
        scene.sh.3 = SIMD4<Float>(studioSH[3].x, studioSH[3].y, studioSH[3].z, 0)
        scene.sh.4 = SIMD4<Float>(studioSH[4].x, studioSH[4].y, studioSH[4].z, 0)
        scene.sh.5 = SIMD4<Float>(studioSH[5].x, studioSH[5].y, studioSH[5].z, 0)
        scene.sh.6 = SIMD4<Float>(studioSH[6].x, studioSH[6].y, studioSH[6].z, 0)
        scene.sh.7 = SIMD4<Float>(studioSH[7].x, studioSH[7].y, studioSH[7].z, 0)
        scene.sh.8 = SIMD4<Float>(studioSH[8].x, studioSH[8].y, studioSH[8].z, 0)

        return scene
    }

    func draw(in view: MTKView) {
        guard let renderPassDesc = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }

        if let vertexBuffer = vertexBuffer,
           let indexBuffer = indexBuffer,
           let model = model {

            let now = CACurrentMediaTime()
            let dt = Float(now - lastFrameTime)
            lastFrameTime = now

            if dt > 0 && dt < 0.1 {
                let g = motion.gravity
                model.setGravity(x: g.x, y: g.y, z: g.z)

                if animationLoaded && isPlaying {
                    currentFrame += 30.0 * dt * playbackSpeed
                    model.updateAnimation(currentFrame, physicsElapsed: dt)
                } else {
                    model.updatePhysics(dt)
                }

                let dest = vertexBuffer.contents().bindMemory(to: Float.self, capacity: Int(model.vertexCount) * 8)
                model.copyInterleavedVertices(dest)
            }

            var scene = buildSceneUniforms()

            // ── Main pass ──
            encoder.setRenderPipelineState(pipelineState)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&scene, length: MemoryLayout<MMDSceneUniforms>.size, index: 1)
            encoder.setFragmentBytes(&scene, length: MemoryLayout<MMDSceneUniforms>.size, index: 1)
            encoder.setFragmentSamplerState(samplerState, index: 0)

            // Opaque submeshes
            encoder.setDepthStencilState(depthStateWrite)
            for sub in subMeshes {
                let matID = Int(sub.materialID)
                guard let mat = (matID >= 0 && matID < materialInfos.count) ? materialInfos[matID] : nil else { continue }
                let texPath = (mat.texturePath ?? "").lowercased()
                if texPath.hasSuffix(".png") { continue }
                drawSubMesh(encoder: encoder, sub: sub, mat: mat, model: model, indexBuffer: indexBuffer)
            }

            // Transparent submeshes (PNG)
            encoder.setDepthStencilState(depthStateNoWrite)
            for sub in subMeshes {
                let matID = Int(sub.materialID)
                guard let mat = (matID >= 0 && matID < materialInfos.count) ? materialInfos[matID] : nil else { continue }
                let texPath = (mat.texturePath ?? "").lowercased()
                if !texPath.hasSuffix(".png") { continue }
                drawSubMesh(encoder: encoder, sub: sub, mat: mat, model: model, indexBuffer: indexBuffer)
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func drawSubMesh(encoder: MTLRenderCommandEncoder, sub: SabaSubMesh, mat: SabaMaterialInfo, model: SabaMMDModel, indexBuffer: MTLBuffer) {
        let matID = Int(sub.materialID)
        let hasTex = textures[matID] != nil

        // Convert MMD specularPower to PBR roughness
        let roughness = Float(1.0 - min(mat.specularPower / 100.0, 1.0))
        // Estimate metallic from specular intensity
        let specAvg = (mat.specularR + mat.specularG + mat.specularB) / 3.0
        let metallic: Float = specAvg > 0.5 ? 0.3 : 0.0

        var matUniforms = MMDMaterialUniforms(
            diffuse: SIMD4<Float>(mat.diffuseR, mat.diffuseG, mat.diffuseB, mat.alpha),
            specular: SIMD3<Float>(mat.specularR, mat.specularG, mat.specularB),
            specularPower: mat.specularPower,
            ambient: SIMD3<Float>(mat.ambientR, mat.ambientG, mat.ambientB),
            hasTexture: hasTex ? 1 : 0,
            roughness: roughness,
            metallic: metallic,
            _pad0: 0,
            _pad1: 0
        )

        encoder.setFragmentBytes(&matUniforms, length: MemoryLayout<MMDMaterialUniforms>.size, index: 0)
        encoder.setFragmentTexture(hasTex ? textures[matID] : dummyTexture, index: 0)

        let indexOffset = Int(sub.beginIndex) * Int(model.indexElementSize)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: Int(sub.vertexCount),
            indexType: indexType,
            indexBuffer: indexBuffer,
            indexBufferOffset: indexOffset
        )
    }
}

import MetalKit
import simd

class MetalMMDRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let camera = Camera()

    private var pipelineState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    private var samplerState: MTLSamplerState!
    private var dummyTexture: MTLTexture!

    private let maxInflightFrames = 3
    private var vertexBuffers: [MTLBuffer] = []
    private var currentBufferIndex = 0
    private let inflightSemaphore: DispatchSemaphore

    private var indexBuffer: MTLBuffer?
    private var indexType: MTLIndexType = .uint16

    private var model: SabaMMDModel?
    private var subMeshes: [SabaSubMesh] = []
    private var materialInfos: [SabaMaterialInfo] = []
    private var textures: [Int: MTLTexture] = [:]

    private var viewportSize: CGSize = .zero

    init?(mtkView: MTKView) {
        guard let device = mtkView.device,
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.inflightSemaphore = DispatchSemaphore(value: maxInflightFrames)

        super.init()

        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.clearColor = MTLClearColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)

        buildPipeline(mtkView: mtkView)
        buildDepthState()
        buildSamplerState()
        buildDummyTexture()
    }

    private func buildPipeline(mtkView: MTKView) {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "mmd_vertex"),
              let fragFn = library.makeFunction(name: "mmd_fragment") else {
            fatalError("Failed to load Metal shader functions")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        desc.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    private func buildDepthState() {
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = .less
        desc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: desc)
    }

    private func buildSamplerState() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .linear
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

        let sabaModel = SabaMMDModel()
        guard sabaModel.loadModel(path: path, dataDir: modelDir) else {
            print("Failed to load PMX model at \(path)")
            return
        }

        self.model = sabaModel
        self.subMeshes = sabaModel.subMeshes
        self.materialInfos = sabaModel.materials

        uploadVertexData()
        uploadIndexData()
        loadTextures(modelDir: modelDir)
    }

    private func uploadVertexData() {
        guard let model = model else { return }
        let vertexCount = Int(model.vertexCount)
        let byteCount = vertexCount * 8 * MemoryLayout<Float>.size

        vertexBuffers.removeAll()
        for _ in 0..<maxInflightFrames {
            guard let buf = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
                fatalError("Failed to allocate vertex buffer")
            }
            vertexBuffers.append(buf)
        }

        let dest = vertexBuffers[0].contents().bindMemory(to: Float.self, capacity: vertexCount * 8)
        model.copyInterleavedVertices(dest)

        for i in 1..<maxInflightFrames {
            memcpy(vertexBuffers[i].contents(), vertexBuffers[0].contents(), byteCount)
        }
    }

    private func uploadIndexData() {
        guard let model = model else { return }
        let count = Int(model.indexCount)
        let elemSize = Int(model.indexElementSize)
        indexType = (elemSize == 4) ? .uint32 : .uint16
        let byteCount = count * elemSize

        let rawPtr = model.rawIndices()
        indexBuffer = device.makeBuffer(bytes: rawPtr, length: byteCount, options: .storageModeShared)
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
                print("Warning: could not load texture \(fullPath): \(error)")
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    func draw(in view: MTKView) {
        guard let model = model,
              !vertexBuffers.isEmpty,
              let indexBuffer = indexBuffer else { return }

        inflightSemaphore.wait()
        currentBufferIndex = (currentBufferIndex + 1) % maxInflightFrames

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDesc = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            inflightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }

        let aspect = Float(viewportSize.width / max(viewportSize.height, 1))
        let projection = Camera.perspective(fovYDegrees: 30.0, aspect: aspect, near: 0.1, far: 1000.0)
        let viewMat = camera.viewMatrix

        var uniforms = MMDUniforms(
            modelMatrix: matrix_identity_float4x4,
            viewMatrix: viewMat,
            projectionMatrix: projection,
            lightDirection: SIMD3<Float>(-0.5, -1.0, -0.5),
            cameraPosition: camera.cameraPosition
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            commandBuffer.commit()
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffers[currentBufferIndex], offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MMDUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MMDUniforms>.size, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        for sub in subMeshes {
            let matID = Int(sub.materialID)
            let mat: SabaMaterialInfo? = (matID >= 0 && matID < materialInfos.count) ? materialInfos[matID] : nil

            let hasTex = (mat != nil && textures[matID] != nil)

            var matUniforms = MMDMaterialUniforms(
                diffuse: SIMD4<Float>(mat?.diffuseR ?? 0.8, mat?.diffuseG ?? 0.8, mat?.diffuseB ?? 0.8, mat?.alpha ?? 1.0),
                specular: SIMD3<Float>(mat?.specularR ?? 0, mat?.specularG ?? 0, mat?.specularB ?? 0),
                specularPower: mat?.specularPower ?? 0,
                ambient: SIMD3<Float>(mat?.ambientR ?? 0.2, mat?.ambientG ?? 0.2, mat?.ambientB ?? 0.2),
                hasTexture: hasTex ? 1 : 0
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

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

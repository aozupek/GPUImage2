import AVFoundation

public enum MovieDecoderError: Error, CustomStringConvertible {
    case noVideoTracks
    
    public var errorDescription: String {
        switch self {
        case .noVideoTracks:
            return "Given asset does not contain any video tracks!"
        }
    }
    
    public var description: String {
        return "<\(type(of: self)): errorDescription = \(self.errorDescription)>"
    }
}

public class MovieDecoder {
    private(set) var asset: AVAsset
    private(set) public var isDecoding = false
    private(set) public var framebuffers: [Framebuffer] = []
    public var overriddenOutputSize:Size?
    private var decodingQueue = DispatchQueue(label: "com.reinarc.camcorder.decoder", qos: .background)
    private var cancelFlag = false
    
    let yuvConversionShader:ShaderProgram
    var assetReader: AVAssetReader?
    
    public init(with _asset: AVAsset) throws {
        guard let _ = _asset.tracks(withMediaType: .video).first else {
            throw MovieDecoderError.noVideoTracks
        }
        asset = _asset
        yuvConversionShader = crashOnShaderCompileFailure("MovieDecoder") {
            try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionFullRangeFragmentShader)
        }
    }
    
    deinit {
        print("MovieDecoder.deinit()")
    }
    
    public func startDecoding(in timeRange:CMTimeRange, progress: ((Double) -> Void)? = nil, completion: @escaping (Bool, Bool) -> Void) {
        decodingQueue.async {
            guard !self.isDecoding else {
                fatalError("Decoding is already started!")
            }
            self.isDecoding = true
            self.cancelFlag = false
            
            let fail = {
                self.isDecoding = false
                completion(false, false)
            }
            
            let outputSettings:[String:AnyObject] = [
                (kCVPixelBufferPixelFormatTypeKey as String): NSNumber(value:Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))
            ]
            
            guard let assetReader = try? AVAssetReader.init(asset: self.asset) else {
                print("MovieDecoder: Failed to create asset reader for given asset.")
                return fail()
            }
            self.assetReader = assetReader
            
            let readerVideoTrackOutput = AVAssetReaderTrackOutput(track: self.asset.tracks(withMediaType: .video).first!, outputSettings:outputSettings)
            readerVideoTrackOutput.alwaysCopiesSampleData = false
            assetReader.add(readerVideoTrackOutput)
            assetReader.timeRange = timeRange
            
            do {
                try NSObject.catchException {
                    guard assetReader.startReading() else {
                        print("MovieDecoder: Unable to start reading: \(String(describing: assetReader.error))")
                        return fail()
                    }
                }
            }
            catch {
                print("MovieDecoder: Unable to start reading: \(error)")
                return fail()
            }
            
            var error = false
            while(assetReader.status == .reading && !error) {
                if self.cancelFlag {
                    assetReader.cancelReading()
                    break
                }
                
                if let sampleBuffer = readerVideoTrackOutput.copyNextSampleBuffer() {
                    let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                    let movieFrame = CMSampleBufferGetImageBuffer(sampleBuffer)!
                    sharedImageProcessingContext.runOperationSynchronously {
                        error = !self.process(movieFrame: movieFrame, withSampleTime: currentSampleTime)
                    }
                    CMSampleBufferInvalidate(sampleBuffer)
                    let relativeSampleTime = CMTimeSubtract(currentSampleTime, timeRange.start)
                    progress?(CMTimeGetSeconds(relativeSampleTime) / CMTimeGetSeconds(timeRange.duration))
                }
            }
            
            let cancelled = assetReader.status == .cancelled
            let succeed = assetReader.status == .completed
            
            assetReader.cancelReading()
            
            self.assetReader = nil
            self.isDecoding = false
            
            completion(succeed, cancelled)
        }
    }
    
    public func cancelDecoding(completion: @escaping () -> ()) {
        guard isDecoding else {
            fatalError("Decoding is not started yet!")
        }

        cancelFlag = true
   
        DispatchQueue.global().async {
            while self.isDecoding {
                usleep(1000)
            }
            print("Cancelled")
            completion()
        }
    }
    
    public func clearFramebuffers() {
        let block: () -> () = {
            sharedImageProcessingContext.runOperationAsynchronously {
                let cache = self.framebuffers.first?.cache
                self.framebuffers.forEach {
                    $0.unlock()
                }
                self.framebuffers.removeAll()
                cache?.purgeAllUnassignedFramebuffers()
                print("Unloaded")
            }
        }
        
        if isDecoding {
            cancelDecoding {
                block()
            }
        }
        else {
            block()
        }
        

    }
    
    func process(movieFrame:CVPixelBuffer, withSampleTime:CMTime) -> Bool {
        let bufferHeight = CVPixelBufferGetHeight(movieFrame)
        let bufferWidth = CVPixelBufferGetWidth(movieFrame)
        CVPixelBufferLockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        let conversionMatrix = colorConversionMatrix601FullRangeDefault
        var luminanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE0))
        
        let luminanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, movieFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), 0, &luminanceGLTexture)
        
        if(luminanceGLTextureResult != kCVReturnSuccess || luminanceGLTexture == nil) {
            print("Could not create LuminanceGLTexture")
            return false
        }
        
        let luminanceTexture = CVOpenGLESTextureGetName(luminanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let luminanceFramebuffer: Framebuffer
        do {
            luminanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext, orientation: .portrait, size: GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly: true, overriddenTexture: luminanceTexture)
        } catch {
            print("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
            return false
        }
        
        var chrominanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        
        let chrominanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, movieFrame, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), 1, &chrominanceGLTexture)
        
        if(chrominanceGLTextureResult != kCVReturnSuccess || chrominanceGLTexture == nil) {
            print("Could not create ChrominanceGLTexture")
            return false
        }
        
        let chrominanceTexture = CVOpenGLESTextureGetName(chrominanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let chrominanceFramebuffer: Framebuffer
        do {
            chrominanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext, orientation: .portrait, size: GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly: true, overriddenTexture: chrominanceTexture)
        } catch {
            print("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
            return false
        }
        
        var framebufferSize: GLSize?
        if let overriddenOutputSize = self.overriddenOutputSize {
            framebufferSize = GLSize(width:overriddenOutputSize.glWidth(), height:overriddenOutputSize.glHeight())
        }
        else {
            framebufferSize = GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight))
        }
        
        let movieFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation: .portrait, size:framebufferSize!, textureOnly:false)
        movieFramebuffer.lock()
        
        convertYUVToRGB(shader:self.yuvConversionShader, luminanceFramebuffer:luminanceFramebuffer, chrominanceFramebuffer:chrominanceFramebuffer, resultFramebuffer:movieFramebuffer, colorConversionMatrix:conversionMatrix)
        CVPixelBufferUnlockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        movieFramebuffer.timingStyle = .stillImage
        framebuffers.append(movieFramebuffer)
        
        return true
    }
    
}

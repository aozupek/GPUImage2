import Foundation
import AVFoundation

public class SimulatorCamera: NSObject, ImageSource {
    public let targets = TargetContainer()
    public weak var delegate: CameraDelegate?
    public var audioEncodingTarget:AudioEncodingTarget?
    public var audioInput:AVCaptureDeviceInput?
    public var audioOutput:AVCaptureAudioDataOutput?
    public var inputCamera:AVCaptureDevice!
    public var rotation: Rotation = .noRotation
    public private(set) var location:PhysicalCameraLocation = .backFacing
    
    public override init() {
        super.init()
    }
    
    
    public func changeLocation(to location: PhysicalCameraLocation) throws {
        
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
    }
    
    public func startCapture() {
        
    }
    
    public func stopCapture() {
        
    }
    
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        
    }
    
    public func addAudioInputsAndOutputs() throws {
        
    }
    
    public func removeAudioInputsAndOutputs() {
        
    }
    
    func processAudioSampleBuffer(_ sampleBuffer:CMSampleBuffer) {
        
    }
}


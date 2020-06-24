public enum ImageOrientation {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
    
    public func rotationNeededForOrientation(_ targetOrientation:ImageOrientation) -> Rotation {
        switch (self, targetOrientation) {
            case (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown), (.landscapeLeft, .landscapeLeft), (.landscapeRight, .landscapeRight): return .noRotation
            case (.portrait, .portraitUpsideDown): return .rotate180
            case (.portraitUpsideDown, .portrait): return .rotate180
            case (.portrait, .landscapeLeft): return .rotateCounterclockwise
            case (.landscapeLeft, .portrait): return .rotateClockwise
            case (.portrait, .landscapeRight): return .rotateClockwise
            case (.landscapeRight, .portrait): return .rotateCounterclockwise
            case (.landscapeLeft, .landscapeRight): return .rotate180
            case (.landscapeRight, .landscapeLeft): return .rotate180
            case (.portraitUpsideDown, .landscapeLeft): return .rotateClockwise
            case (.landscapeLeft, .portraitUpsideDown): return .rotateCounterclockwise
            case (.portraitUpsideDown, .landscapeRight): return .rotateCounterclockwise
            case (.landscapeRight, .portraitUpsideDown): return .rotateClockwise
        }
    }
    
    public func rotate(rotation: Rotation) -> ImageOrientation {
        guard rotation != .flipHorizontally, rotation != .flipVertically, rotation != .rotateClockwiseAndFlipVertically, rotation != .rotateClockwiseAndFlipHorizontally
            else {
                fatalError("Unsupported rotation!")
        }
        
        if rotation == .noRotation { return self }
        
        switch (self, rotation) {
            case (.portrait, .rotateCounterclockwise): return .landscapeLeft
            case (.portrait, .rotateClockwise): return .landscapeRight
            case (.portrait, .rotate180): return .portraitUpsideDown
            case (.landscapeRight, .rotateCounterclockwise): return .portrait
            case (.landscapeRight, .rotateClockwise):return .portraitUpsideDown
            case (.landscapeRight, .rotate180): return .landscapeLeft
            case (.portraitUpsideDown, .rotateCounterclockwise): return .landscapeRight
            case (.portraitUpsideDown, .rotateClockwise): return .landscapeLeft
            case (.portraitUpsideDown, .rotate180): return .portrait
            case (.landscapeLeft, .rotateCounterclockwise): return .portraitUpsideDown
            case (.landscapeLeft, .rotateClockwise): return .portrait
            case (.landscapeLeft, .rotate180): return .landscapeRight
            //TODO: Add support for other rotations when necessary
            default: return self
        }
    }
}

public enum Rotation {
    case noRotation
    case rotateCounterclockwise
    case rotateClockwise
    case rotate180
    case flipHorizontally
    case flipVertically
    case rotateClockwiseAndFlipVertically
    case rotateClockwiseAndFlipHorizontally
    
    public func flipsDimensions() -> Bool {
        switch self {
            case .noRotation, .rotate180, .flipHorizontally, .flipVertically: return false
            case .rotateCounterclockwise, .rotateClockwise, .rotateClockwiseAndFlipVertically, .rotateClockwiseAndFlipHorizontally: return true
        }
    }
}

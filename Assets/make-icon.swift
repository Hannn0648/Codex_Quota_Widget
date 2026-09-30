import AppKit
let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size)/1024); transform.concat()
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
    let track = NSBezierPath(ovalIn: NSRect(x: 218, y: 218, width: 588, height: 588))
    track.lineWidth = 48; NSColor.white.withAlphaComponent(0.18).setStroke(); track.stroke()
    let arc = NSBezierPath(); arc.lineWidth = 48; arc.lineCapStyle = .round
    arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 294, startAngle: 90, endAngle: -198, clockwise: true)
    NSColor.white.setStroke(); arc.stroke()
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 266, weight: .bold), .foregroundColor: NSColor.white]
    let text = "80" as NSString, dimensions = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (1024-dimensions.width)/2, y: (1024-dimensions.height)/2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try render(size*2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}

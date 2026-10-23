import AppKit
let output = CommandLine.arguments[1]
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
let outer = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 218, yRadius: 218)
let gradient = NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.36, blue: 0.85, alpha: 1), ending: NSColor(srgbRed: 0.47, green: 0.27, blue: 0.84, alpha: 1))!
gradient.draw(in: outer, angle: -45)
let arc = NSBezierPath();arc.appendArc(withCenter: NSPoint(x:512,y:512),radius:230,startAngle:110,endAngle:390,clockwise:false);arc.lineWidth=64;arc.lineCapStyle = .round;NSColor.white.withAlphaComponent(0.95).setStroke();arc.stroke()
let small = NSBezierPath();small.appendArc(withCenter:NSPoint(x:512,y:512),radius:230,startAngle:55,endAngle:86,clockwise:false);small.lineWidth=64;small.lineCapStyle = .round;NSColor.white.withAlphaComponent(0.4).setStroke();small.stroke()
NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:465,y:465,width:94,height:94)).fill()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

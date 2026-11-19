// Renders Medcezir's app icon from the editable SVG in design/ (top-down beach, tide, starfish).
// Edit design/app-icon-beach.svg in Illustrator, then rerun this to refresh the app icon.
// Output is exactly 1024×1024 with no alpha channel (App Store Connect rejects transparency).
// Drawing uses a 32-bit context whose 4th byte is ignored (`noneSkipLast`): CoreGraphics can't
// draw into 24-bit RGB, and drawing into an RGBA bitmap would keep an alpha channel.
// Usage: swift scripts/make-icon.swift design/app-icon-beach.svg \
//          Medcezir/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
guard let artwork = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    fatalError("Couldn't read \(CommandLine.arguments[1])")
}
NSColor.white.setFill()
bounds.fill()
artwork.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

let url = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "Couldn't write PNG")

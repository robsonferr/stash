import Cocoa

// NSApplication precisa ser inicializado para AppKit drawing funcionar
let _ = NSApplication.shared

let outputDir = "icon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

struct Spec { let file: String; let px: Int }
let specs: [Spec] = [
    Spec(file: "icon_16x16.png",      px: 16),
    Spec(file: "icon_16x16@2x.png",   px: 32),
    Spec(file: "icon_32x32.png",      px: 32),
    Spec(file: "icon_32x32@2x.png",   px: 64),
    Spec(file: "icon_128x128.png",    px: 128),
    Spec(file: "icon_128x128@2x.png", px: 256),
    Spec(file: "icon_256x256.png",    px: 256),
    Spec(file: "icon_256x256@2x.png", px: 512),
    Spec(file: "icon_512x512.png",    px: 512),
    Spec(file: "icon_512x512@2x.png", px: 1024),
]

// Renderiza o SF Symbol como imagem branca opaca
func whiteSymbol(name: String, ptSize: CGFloat) -> NSImage? {
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: ptSize, weight: .medium)
    guard let configured = sym.withSymbolConfiguration(cfg) else { return nil }
    let sz = configured.size
    let out = NSImage(size: sz)
    out.lockFocus()
    NSColor.white.set()
    configured.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 0.95)
    out.unlockFocus()
    return out
}

func makeIcon(px: Int) -> Data? {
    let s = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let cg = nsCtx.cgContext

    // — Clip ao rounded rect padrão macOS —
    let corner = s * 0.2237
    let clip = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: corner, cornerHeight: corner, transform: nil)
    cg.addPath(clip)
    cg.clip()

    // — Gradiente: índigo profundo → roxo → violeta-magenta —
    // Direção: canto inferior-esquerdo → superior-direito
    let cs = CGColorSpaceCreateDeviceRGB()
    let gc: [CGColor] = [
        CGColor(red: 0.06, green: 0.04, blue: 0.38, alpha: 1.0), // índigo profundo
        CGColor(red: 0.38, green: 0.07, blue: 0.65, alpha: 1.0), // roxo médio
        CGColor(red: 0.68, green: 0.13, blue: 0.58, alpha: 1.0), // violeta-magenta
    ]
    let locs: [CGFloat] = [0.0, 0.55, 1.0]
    let gradient = CGGradient(colorsSpace: cs, colors: gc as CFArray, locations: locs)!
    cg.drawLinearGradient(gradient,
        start: CGPoint(x: 0, y: 0),
        end:   CGPoint(x: s, y: s),
        options: [])

    // — Pontos de acento (neurônios / faíscas) —
    let dots: [(CGFloat, CGFloat, CGFloat)] = [
        (0.13, 0.80, 0.028), (0.84, 0.77, 0.020), (0.87, 0.17, 0.024),
        (0.07, 0.23, 0.016), (0.76, 0.89, 0.022), (0.23, 0.55, 0.014),
        (0.50, 0.93, 0.018), (0.93, 0.49, 0.016), (0.65, 0.12, 0.012),
    ]
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    for (rx, ry, rr) in dots {
        let cr = s * rr
        cg.fillEllipse(in: CGRect(x: s * rx - cr, y: s * ry - cr, width: cr * 2, height: cr * 2))
    }

    // — Anel de brilho central (halo suave atrás do cérebro) —
    let haloR = s * 0.32
    let haloX = s / 2
    let haloY = s / 2
    let haloColors: [CGColor] = [
        CGColor(red: 0.80, green: 0.65, blue: 1.0, alpha: 0.22),
        CGColor(red: 0.80, green: 0.65, blue: 1.0, alpha: 0.0),
    ]
    let haloGrad = CGGradient(colorsSpace: cs, colors: haloColors as CFArray, locations: [0.0, 1.0])!
    cg.drawRadialGradient(haloGrad,
        startCenter: CGPoint(x: haloX, y: haloY), startRadius: 0,
        endCenter:   CGPoint(x: haloX, y: haloY), endRadius: haloR,
        options: [])

    // — Ícone do cérebro (SF Symbol) em branco com glow —
    let ptSize = s * 0.50
    if let brain = whiteSymbol(name: "brain.head.profile", ptSize: ptSize) {
        let iw = brain.size.width
        let ih = brain.size.height
        let ix = (s - iw) / 2 + s * 0.01  // leve deslocamento para equilíbrio visual
        let iy = (s - ih) / 2

        cg.saveGState()
        cg.setShadow(offset: .zero, blur: s * 0.07,
                     color: CGColor(red: 0.85, green: 0.70, blue: 1.0, alpha: 0.60))
        brain.draw(at: NSPoint(x: ix, y: iy), from: .zero, operation: .sourceOver, fraction: 1.0)
        cg.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

print("Gerando ícone Stash...")
for spec in specs {
    if let data = makeIcon(px: spec.px) {
        let path = "\(outputDir)/\(spec.file)"
        try? data.write(to: URL(fileURLWithPath: path))
        print("  ✓ \(spec.file)")
    } else {
        print("  ✗ falhou: \(spec.file)")
    }
}
print("Iconset → ./\(outputDir)/")

// Cue Pilot — procedural illustration generator.
//
// Draws the onboarding backgrounds and sprite illustrations with CoreGraphics
// ("a small modern theatre in glossy 3D") and writes them into the app:
//   CuePilot/Resources/Onboarding/*.webp          (via /opt/homebrew/bin/cwebp)
//   CuePilot/Assets.xcassets/<name>.imageset/*.png
// Intermediate PNGs go to Tools/AssetGen/out/.
//
// Usage (from anywhere):
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift Tools/AssetGen/generate_assets.swift [cp01 cp04 ...]
// or, faster:
//   swiftc -O Tools/AssetGen/generate_assets.swift -o /tmp/cpgen && /tmp/cpgen [ids]
//
// This file intentionally lives OUTSIDE the CuePilot/ folder, which is synchronized into the app target.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths

let scriptURL = URL(fileURLWithPath: #filePath)
let toolDir = scriptURL.deletingLastPathComponent()
let projectRoot = toolDir.deletingLastPathComponent().deletingLastPathComponent()
let outDir = toolDir.appendingPathComponent("out")
let onboardingDir = projectRoot.appendingPathComponent("CuePilot/Resources/Onboarding")
let assetsDir = projectRoot.appendingPathComponent("CuePilot/Assets.xcassets")
let cwebpPath = "/opt/homebrew/bin/cwebp"

// MARK: - Color

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

struct Col {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        self.a = a
    }
    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) { self.r = r; self.g = g; self.b = b; self.a = a }
    func mix(_ o: Col, _ t: CGFloat) -> Col {
        Col(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t, a: a + (o.a - a) * t)
    }
    func alpha(_ x: CGFloat) -> Col { Col(r: r, g: g, b: b, a: x) }
    var cg: CGColor { CGColor(colorSpace: sRGB, components: [r, g, b, a])! }
}

// Palette
let MIDNIGHT = Col(0x142B69)
let RED = Col(0xE74743)
let YELLOW = Col(0xFFDC58)
let PAPER = Col(0xFFF8EB)
let INK = Col(0x18243D)
let MUTED = Col(0x63708C)
let WHITE = Col(0xFFFFFF)
let SHADOW = Col(0x060D2A)

struct Ramp { var hi: Col; var light: Col; var base: Col; var dark: Col; var deep: Col }
let redRamp = Ramp(hi: Col(0xFFBDB1), light: Col(0xFF7467), base: RED, dark: Col(0xBC2F37), deep: Col(0x7A1A2A))
let yellowRamp = Ramp(hi: Col(0xFFFCE8), light: Col(0xFFEC96), base: YELLOW, dark: Col(0xF4B03C), deep: Col(0xD9822A))
let blueRamp = Ramp(hi: Col(0xA4BEFF), light: Col(0x4A70D0), base: Col(0x2A4CA8), dark: Col(0x1A3680), deep: Col(0x0C1B4C))
let navyRamp = Ramp(hi: Col(0x9DB6F7), light: Col(0x3D60B2), base: Col(0x23418A), dark: Col(0x152B62), deep: Col(0x0A173C))

// MARK: - Geometry helpers

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
extension CGPoint {
    var len: CGFloat { sqrt(x * x + y * y) }
    var norm: CGPoint { let l = len; return l > 0 ? CGPoint(x: x / l, y: y / l) : self }
    var perp: CGPoint { CGPoint(x: -y, y: x) }
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func mixP(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t)) }
func rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
func dirv(_ deg: CGFloat) -> CGPoint { CGPoint(x: cos(rad(deg)), y: sin(rad(deg))) }

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil)
}
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    let rr = max(0, min(r, w / 2 - 0.01, h / 2 - 0.01))
    return CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: rr, cornerHeight: rr, transform: nil)
}
func rrect2(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    let a = max(0, min(rx, w / 2 - 0.01)), b = max(0, min(ry, h / 2 - 0.01))
    return CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: a, cornerHeight: b, transform: nil)
}
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
}
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath { ellipse(cx, cy, r, r) }
func ellipseR(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, rot: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: rad(rot))
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &t)
}
func poly(_ pts: [CGPoint], closed: Bool = true) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    if closed { p.closeSubpath() }
    return p
}
func linePath(_ a: CGPoint, _ b: CGPoint) -> CGPath { poly([a, b], closed: false) }
func quadPath(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> CGPath {
    let p = CGMutablePath(); p.move(to: a); p.addQuadCurve(to: b, control: c); return p
}
func cubicPath(_ a: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ b: CGPoint) -> CGPath {
    let p = CGMutablePath(); p.move(to: a); p.addCurve(to: b, control1: c1, control2: c2); return p
}
func strokePath(_ p: CGPath, _ w: CGFloat, cap: CGLineCap = .round) -> CGPath {
    p.copy(strokingWithWidth: w, lineCap: cap, lineJoin: .round, miterLimit: 10)
}
func moved(_ p: CGPath, _ dx: CGFloat, _ dy: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: dx, y: dy)
    return p.copy(using: &t)!
}
func quadPt(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    return a * (u * u) + c * (2 * u * t) + b * (t * t)
}
func quadTan(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    (c - a) * (2 * (1 - t)) + (b - c) * (2 * t)
}
func ellipsePoints(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, rot: CGFloat = 0, n: Int = 72) -> [CGPoint] {
    let ca = cos(rad(rot)), sa = sin(rad(rot))
    return (0..<n).map { i in
        let a = CGFloat(i) / CGFloat(n) * 2 * .pi
        let x = cos(a) * rx, y = sin(a) * ry
        return P(c.x + x * ca - y * sa, c.y + x * sa + y * ca)
    }
}
func hull(_ input: [CGPoint]) -> [CGPoint] {
    let pts = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    if pts.count < 3 { return pts }
    func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
    var lower: [CGPoint] = []
    for p in pts {
        while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
        lower.append(p)
    }
    var upper: [CGPoint] = []
    for p in pts.reversed() {
        while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
        upper.append(p)
    }
    lower.removeLast(); upper.removeLast()
    return lower + upper
}

struct RNG {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 11) & ((1 << 53) - 1)) / CGFloat(1 << 53)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

// MARK: - Canvas & drawing primitives

var C: CGContext! = nil
var CW: CGFloat = 0
var CH: CGFloat = 0

func newCanvas(_ w: Int, _ h: Int, opaque: Bool) {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    C = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: sRGB, bitmapInfo: info)!
    CW = CGFloat(w); CH = CGFloat(h)
    C.translateBy(x: 0, y: CH)
    C.scaleBy(x: 1, y: -1)   // top-left origin, y grows downward
    C.setShouldAntialias(true)
    C.interpolationQuality = .high
    if !opaque { C.clear(CGRect(x: 0, y: 0, width: CW, height: CH)) }
}

func savePNG(_ url: URL) {
    var img = C.makeImage()!
    if C.alphaInfo == .premultipliedLast, let data = C.data {
        // Write straight (un-premultiplied) alpha ourselves. In nearly transparent pixels (soft glow and shadow tails)
        // the colour is invisible but noisy after un-premultiplying, which bloats the PNG, so quantize it there.
        let w = C.width, h = C.height, bpr = C.bytesPerRow
        let src = data.bindMemory(to: UInt8.self, capacity: bpr * h)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = y * bpr + x * 4, q = (y * w + x) * 4
                let a = Int(src[o + 3])
                if a == 0 { continue }
                let step = a < 24 ? 32 : (a < 64 ? 8 : 2)
                for k in 0..<3 {
                    var v = min(255, (Int(src[o + k]) * 255 + a / 2) / a)
                    if step > 1 { v = min(255, (v + step / 2) / step * step) }
                    out[q + k] = UInt8(v)
                }
                out[q + 3] = UInt8(a)
            }
        }
        let provider = CGDataProvider(data: Data(out) as CFData)!
        img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: sRGB,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                      decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

func group(_ body: () -> Void) { C.saveGState(); body(); C.restoreGState() }
func clipped(_ p: CGPath, _ body: () -> Void) { group { C.addPath(p); C.clip(); body() } }
func layer(_ alpha: CGFloat = 1, blend: CGBlendMode = .normal, _ body: () -> Void) {
    group {
        C.setAlpha(alpha); C.setBlendMode(blend)
        C.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        C.endTransparencyLayer()
    }
}
func fill(_ p: CGPath, _ c: Col, blend: CGBlendMode = .normal) {
    group { C.setBlendMode(blend); C.addPath(p); C.setFillColor(c.cg); C.fillPath() }
}
func strokeP(_ p: CGPath, _ c: Col, _ w: CGFloat, cap: CGLineCap = .round, dash: [CGFloat] = [], blend: CGBlendMode = .normal) {
    group {
        C.setBlendMode(blend)
        C.addPath(p); C.setStrokeColor(c.cg); C.setLineWidth(w); C.setLineCap(cap); C.setLineJoin(.round)
        if !dash.isEmpty { C.setLineDash(phase: 0, lengths: dash) }
        C.strokePath()
    }
}
func mkGrad(_ stops: [(CGFloat, Col)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1.cg } as CFArray, locations: stops.map { $0.0 })!
}
func linear(_ p: CGPath?, _ stops: [(CGFloat, Col)], _ a: CGPoint, _ b: CGPoint, blend: CGBlendMode = .normal) {
    group {
        if let p { C.addPath(p); C.clip() }
        C.setBlendMode(blend)
        C.drawLinearGradient(mkGrad(stops), start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
func radial(_ p: CGPath?, _ stops: [(CGFloat, Col)], _ c: CGPoint, _ r: CGFloat, sy: CGFloat = 1, rot: CGFloat = 0,
            blend: CGBlendMode = .normal, extend: Bool = true) {
    group {
        if let p { C.addPath(p); C.clip() }
        C.setBlendMode(blend)
        C.translateBy(x: c.x, y: c.y); C.rotate(by: rad(rot)); C.scaleBy(x: 1, y: sy)
        C.drawRadialGradient(mkGrad(stops), startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r,
                             options: extend ? [.drawsAfterEndLocation] : [])
    }
}
/// Soft round light falloff.
func glow(_ c: CGPoint, _ r: CGFloat, _ col: Col, _ a: CGFloat, sy: CGFloat = 1, rot: CGFloat = 0, blend: CGBlendMode = .normal) {
    radial(nil, [(0, col.alpha(a)), (0.18, col.alpha(a * 0.78)), (0.42, col.alpha(a * 0.4)),
                 (0.68, col.alpha(a * 0.13)), (1, col.alpha(0))], c, r, sy: sy, rot: rot, blend: blend, extend: false)
}

// Shadow offsets are specified canvas-aligned (y down), scaled by the current CTM scale, mirrored with the CTM.
func devScale() -> CGFloat { let m = C.ctm; return sqrt(abs(m.a * m.d - m.b * m.c)) }
func devOffset(_ dx: CGFloat, _ dy: CGFloat) -> CGSize {
    let m = C.ctm
    let det = m.a * m.d - m.b * m.c
    let s = sqrt(abs(det))
    let mir: CGFloat = det > 0 ? -1 : 1
    return CGSize(width: dx * s * mir, height: -dy * s)
}
/// Draws only a blurred copy of `p` (shadow-offset trick).
func blurred(_ p: CGPath, _ c: Col, _ blur: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0, blend: CGBlendMode = .normal) {
    group {
        C.setBlendMode(blend)
        let K: CGFloat = 40000
        let m = C.ctm
        let lin = CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: 0, ty: 0).inverted()
        let u = CGPoint(x: -K, y: 0).applying(lin)
        let off = devOffset(dx, dy)
        C.setShadow(offset: CGSize(width: off.width + K, height: off.height), blur: blur * devScale(), color: c.cg)
        C.translateBy(x: u.x, y: u.y)
        C.addPath(p); C.setFillColor(CGColor(gray: 0, alpha: 1)); C.fillPath()
    }
}
func innerShadow(_ p: CGPath, _ c: Col, blur: CGFloat, dx: CGFloat, dy: CGFloat) {
    group {
        C.addPath(p); C.clip()
        let pad = blur * 3 + abs(dx) + abs(dy) + 20
        let bb = p.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad)
        let m = CGMutablePath(); m.addRect(bb); m.addPath(p)
        // The ring itself is drawn far off-canvas so no fill pixels leak through the antialiased clip edge.
        let K: CGFloat = 40000
        let ctm = C.ctm
        let lin = CGAffineTransform(a: ctm.a, b: ctm.b, c: ctm.c, d: ctm.d, tx: 0, ty: 0).inverted()
        let u = CGPoint(x: -K, y: 0).applying(lin)
        let off = devOffset(dx, dy)
        C.setShadow(offset: CGSize(width: off.width + K, height: off.height), blur: blur * devScale(), color: c.cg)
        C.translateBy(x: u.x, y: u.y)
        C.addPath(m); C.setFillColor(CGColor(gray: 0, alpha: 1)); C.fillPath(using: .evenOdd)
    }
}

struct Gloss {
    var mid: CGFloat = 0.5
    var volume: CGFloat = 0.5
    var shade: CGFloat = 0.5
    var bounce: CGFloat = 0.3
    var rim: CGFloat = 0.5
    var spec: CGFloat = 0.8
    var specAt = CGPoint(x: 0.3, y: 0.2)
    var specSize = CGSize(width: 0.3, height: 0.13)
    var specRot: CGFloat = -28
}

/// Toy-plastic shading: base gradient, volume light, bottom occlusion, bounce light, rim light, specular blob.
func glossy(_ p: CGPath, _ r: Ramp, _ o: Gloss = Gloss()) {
    let bb = p.boundingBoxOfPath
    let s = min(bb.width, bb.height)
    linear(p, [(0, r.light), (o.mid, r.base), (1, r.dark)], P(bb.midX, bb.minY), P(bb.midX, bb.maxY))
    let sc = P(bb.minX + bb.width * o.specAt.x, bb.minY + bb.height * o.specAt.y)
    if o.volume > 0 {
        radial(p, [(0, r.light.alpha(o.volume)), (1, r.light.alpha(0))], sc, max(bb.width, bb.height) * 0.72)
    }
    if o.shade > 0 { innerShadow(p, r.deep.alpha(o.shade), blur: s * 0.2, dx: 0, dy: -s * 0.09) }
    if o.bounce > 0 { innerShadow(p, r.light.alpha(o.bounce), blur: s * 0.035, dx: 0, dy: -s * 0.02) }
    if o.rim > 0 { innerShadow(p, r.hi.alpha(o.rim), blur: s * 0.05, dx: s * 0.015, dy: s * 0.028) }
    if o.spec > 0 {
        let sp = ellipseR(sc, bb.width * o.specSize.width / 2, bb.height * o.specSize.height / 2, rot: o.specRot)
        clipped(p) { blurred(sp, WHITE.alpha(o.spec * 0.85), s * 0.03) }
    }
}

/// Extrudes a shape along `v` (thickness), shading the side from c1 (top) to c2 (bottom).
func extrude(_ p: CGPath, _ v: CGPoint, _ c1: Col, _ c2: Col, steps: Int = 16, bounce: Col? = nil) {
    let u = CGMutablePath()
    for i in 1...steps {
        let f = CGFloat(i) / CGFloat(steps)
        u.addPath(p, transform: CGAffineTransform(translationX: v.x * f, y: v.y * f))
    }
    let flat = u.normalized()
    let bb = flat.boundingBoxOfPath
    linear(flat, [(0, c1), (1, c2)], P(bb.midX, bb.minY), P(bb.midX, bb.maxY))
    if let bc = bounce { innerShadow(flat, bc, blur: 3, dx: 0, dy: -2.5) }
}

func noise(_ amount: Int, seed: UInt64) {
    guard let data = C.data else { return }
    let w = C.width, h = C.height, bpr = C.bytesPerRow
    let px = data.bindMemory(to: UInt8.self, capacity: bpr * h)
    var s = seed
    for y in 0..<h {
        for x in 0..<w {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let n = Int((s >> 33) % UInt64(2 * amount + 1)) - amount
            let o = y * bpr + x * 4
            for k in 0..<3 { px[o + k] = UInt8(clamping: Int(px[o + k]) + n) }
        }
    }
}

// MARK: - Small reusable pieces

/// Ribbon strip along a bent centerline from a to b, with a V-notched end.
func ribbonPath(_ a: CGPoint, _ b: CGPoint, bend: CGFloat, w0: CGFloat, w1: CGFloat, notch: CGFloat) -> CGPath {
    let d = (b - a).norm
    let ctrl = mixP(a, b, 0.5) + d.perp * bend
    var left: [CGPoint] = [], right: [CGPoint] = []
    let n = 40
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let p = quadPt(a, ctrl, b, t)
        let nn = quadTan(a, ctrl, b, t).norm.perp
        let w = lerp(w0, w1, t) / 2
        left.append(p + nn * w); right.append(p - nn * w)
    }
    let tanEnd = quadTan(a, ctrl, b, 1).norm
    return poly(left + [b - tanEnd * notch] + right.reversed())
}

func sparkle(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat, blend: CGBlendMode = .screen) {
    glow(c, r * 2.8, YELLOW, 0.32 * a, blend: blend)
    let p = CGMutablePath()
    let k: CGFloat = 0.16
    p.move(to: P(c.x, c.y - r))
    p.addQuadCurve(to: P(c.x + r * 0.8, c.y), control: P(c.x + r * k, c.y - r * k))
    p.addQuadCurve(to: P(c.x, c.y + r), control: P(c.x + r * k, c.y + r * k))
    p.addQuadCurve(to: P(c.x - r * 0.8, c.y), control: P(c.x - r * k, c.y + r * k))
    p.addQuadCurve(to: P(c.x, c.y - r), control: P(c.x - r * k, c.y - r * k))
    p.closeSubpath()
    fill(p, Col(0xFFF4C2, a))
}

/// Pencil lying from `a` (eraser end) to `b` (tip). `squash` flattens it for a perspective table top.
func drawPencil(from a: CGPoint, to b: CGPoint, w: CGFloat, squash: CGFloat = 1, shadow: Col? = SHADOW.alpha(0.4)) {
    group {
        C.translateBy(x: a.x, y: a.y)
        C.scaleBy(x: 1, y: squash)
        let v = P(b.x - a.x, (b.y - a.y) / squash)
        let L = v.len
        let T = CGAffineTransform(rotationAngle: atan2(v.y, v.x))
        func tp(_ p: CGPath) -> CGPath { var t = T; return p.copy(using: &t)! }
        func tpt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { P(x, y).applying(T) }
        let hw = w / 2
        let body = tp(rrect(0, -hw, L * 0.84, w, hw * 0.9))
        let cone = tp(poly([P(L * 0.8, -hw), P(L * 0.955, -w * 0.13), P(L * 0.955, w * 0.13), P(L * 0.8, hw)]))
        let lead = tp(poly([P(L * 0.95, -w * 0.15), P(L, 0), P(L * 0.95, w * 0.15)]))
        let whole = tp(rrect(0, -hw, L, w, hw))
        if let sc = shadow { blurred(whole, sc, w * 0.35, dx: w * 0.15, dy: w * 0.55) }
        // wood cone + graphite
        linear(cone, [(0, Col(0xFBE9C8)), (0.5, Col(0xF0D3A2)), (1, Col(0xCFA76D))], tpt(0, -hw), tpt(0, hw))
        linear(lead, [(0, Col(0x3A4A6E)), (1, INK)], tpt(0, -hw * 0.3), tpt(0, hw * 0.3))
        // body facets
        clipped(body) {
            linear(body, [(0, Col(0xFFF0A6)), (0.3, Col(0xFFE27A)), (0.34, YELLOW), (0.64, Col(0xFBCB4C)), (0.68, Col(0xF4B03C)), (1, Col(0xE39A33))],
                   tpt(0, -hw), tpt(0, hw))
            strokeP(tp(linePath(P(L * 0.17, -hw * 0.55), P(L * 0.8, -hw * 0.55))), WHITE.alpha(0.55), w * 0.09)
        }
        // painted scallop edge onto the cone
        for k in 0..<3 {
            let yy = -hw + w * (CGFloat(k) + 0.5) / 3
            fill(tp(ellipse(L * 0.8, yy, w * 0.07, w * 0.17)), k == 0 ? Col(0xFFE27A) : (k == 1 ? YELLOW : Col(0xF4B03C)))
        }
        // eraser + ferrule
        let eraser = tp(rrect(0, -hw, L * 0.12, w, hw * 0.9))
        linear(eraser, [(0, Col(0xFF8A7E)), (0.45, RED), (1, Col(0xB92E36))], tpt(0, -hw), tpt(0, hw))
        let ferrule = tp(rect(L * 0.1, -hw * 1.04, L * 0.075, w * 1.04))
        linear(ferrule, [(0, Col(0xF1F4FB)), (0.4, Col(0xB8C2D8)), (1, MUTED)], tpt(0, -hw), tpt(0, hw))
        for k in 1...2 {
            let x = L * 0.1 + L * 0.075 * CGFloat(k) / 3
            strokeP(tp(linePath(P(x, -hw), P(x, hw))), MUTED.alpha(0.8), w * 0.05)
        }
        strokeP(tp(linePath(P(w * 0.2, -hw * 0.5), P(L * 0.1, -hw * 0.5))), WHITE.alpha(0.45), w * 0.08)
    }
}

// MARK: - Flick (mascot)

enum Pose { case wave, pointer, present, think }
struct Arm { var elbow: CGPoint; var hand: CGPoint }
let armRest = Arm(elbow: P(236, -262), hand: P(252, -182))
let armOpen = Arm(elbow: P(252, -300), hand: P(318, -236))
let armWave = Arm(elbow: P(300, -432), hand: P(334, -600))
let armPresent = Arm(elbow: P(292, -378), hand: P(388, -440))
let armPointer = Arm(elbow: P(294, -386), hand: P(340, -520))


func headTilt(_ deg: CGFloat) {
    C.translateBy(x: 0, y: -440); C.rotate(by: rad(deg)); C.translateBy(x: 0, y: 440)
}

func drawWing(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ rot: CGFloat) {
    let p = ellipseR(c, rx, ry, rot: rot)
    linear(p, [(0, Col(0x3D60BC)), (0.5, Col(0x213D88)), (1, Col(0x14285F))], P(c.x, c.y - ry), P(c.x, c.y + ry))
    radial(p, [(0, Col(0x7E9DEE, 0.45)), (1, Col(0x7E9DEE, 0))], P(c.x, c.y - ry * 0.25), rx * 0.95, sy: ry / rx, rot: rot)
    clipped(p) {
        strokeP(p, Col(0xA9C1FF, 0.8), ry * 0.16)
        let d = dirv(rot)
        let a = c - d * (rx * 0.8), b = c + d * (rx * 0.62)
        strokeP(quadPath(a, mixP(a, b, 0.5) + P(0, -ry * 0.18), b), Col(0xB5CAFF, 0.35), ry * 0.07)
        blurred(ellipseR(c + P(-rx * 0.12, -ry * 0.42), rx * 0.34, ry * 0.13, rot: rot), WHITE.alpha(0.6), ry * 0.07)
    }
}

func drawAntenna(_ sx: CGFloat, _ gb: CGBlendMode) {
    let base = P(sx * 62, -770), c1 = P(sx * 64, -872), c2 = P(sx * 120, -934), tip = P(sx * 170, -950)
    let path = cubicPath(base, c1, c2, tip)
    let tube = strokePath(path, 22)
    fill(tube, Col(0x2A4AA0))
    clipped(tube) {
        strokeP(moved(path, 4, 3), Col(0x0E1E4E, 0.7), 8)
        strokeP(moved(path, -4, -3), Col(0x9DB6F7, 0.9), 6)
    }
    glow(tip, 105, YELLOW, 0.55, blend: gb)
    glossy(circle(tip.x, tip.y, 31), yellowRamp,
           Gloss(mid: 0.5, volume: 0.6, shade: 0.35, bounce: 0.3, rim: 0.5, spec: 0.95, specAt: P(0.34, 0.3),
                 specSize: CGSize(width: 0.42, height: 0.26), specRot: -30))
}

func drawFace(look: CGPoint) {
    let lx = look.x * 15, ly = look.y * 10
    for sx in [CGFloat(-1), 1] {
        let ec = P(sx * 90 + lx, -630 + ly)
        let eye = ellipse(ec.x, ec.y, 53, 67)
        blurred(eye, Col(0xB8741A, 0.35), 9, dy: 6)
        linear(eye, [(0, Col(0x0E172E)), (0.55, INK), (1, Col(0x2E4888))], P(ec.x, ec.y - 67), P(ec.x, ec.y + 67))
        clipped(eye) { blurred(ellipse(ec.x + 4, ec.y + 62, 40, 24), Col(0x6386E0, 0.7), 9) }
        fill(circle(ec.x - 17, ec.y - 25, 20), WHITE)
        fill(circle(ec.x + 18, ec.y + 21, 8.5), WHITE.alpha(0.92))
        blurred(ellipse(sx * 160, -548, 40, 23), Col(0xF25A55, 0.5), 11)
    }
    let m = CGMutablePath()
    m.move(to: P(-42 + lx * 0.6, -554))
    m.addQuadCurve(to: P(42 + lx * 0.6, -554), control: P(lx * 0.6, -562))
    m.addQuadCurve(to: P(-42 + lx * 0.6, -554), control: P(lx * 0.6, -484))
    m.closeSubpath()
    fill(m, INK)
    clipped(m) {
        fill(ellipse(lx * 0.6, -514, 28, 17), Col(0xE8504B))
        fill(ellipse(lx * 0.6 - 8, -520, 10, 5), Col(0xFF8C82, 0.8))
    }
    strokeP(m, Col(0xC9861F, 0.35), 3)
}

func drawStick(hand: CGPoint, sx: CGFloat, gb: CGBlendMode) {
    let d = P(0.5 * sx, -0.866)
    let butt = hand - d * 78, tip = hand + d * 392
    let path = linePath(butt, tip)
    let tube = strokePath(path, 18)
    fill(tube, Col(0xD83D3B))
    var n = d.perp
    if n.x + n.y > 0 { n = n * -1 }
    clipped(tube) {
        strokeP(linePath(butt + n * 4, tip + n * 4), Col(0xFF9489, 0.95), 5)
        strokeP(linePath(butt - n * 5, tip - n * 5), Col(0x8E1E2C, 0.7), 5)
    }
    fill(circle(butt.x, butt.y, 11), Col(0x1B3372))
    let tc = tip + d * 10
    glow(tc, 95, YELLOW, 0.6, blend: gb)
    glossy(circle(tc.x, tc.y, 25), yellowRamp,
           Gloss(mid: 0.5, volume: 0.6, shade: 0.35, bounce: 0.3, rim: 0.5, spec: 0.95, specAt: P(0.34, 0.3),
                 specSize: CGSize(width: 0.42, height: 0.26), specRot: -30))
}

func drawArm(_ sx: CGFloat, _ arm: Arm, stick: Bool, belly: CGPath, gb: CGBlendMode) {
    let sh = P(sx * 170, -338)
    let el = P(sx * arm.elbow.x, arm.elbow.y), hd = P(sx * arm.hand.x, arm.hand.y)
    let ctrl = el * 2 - (sh + hd) * 0.5
    let path = quadPath(sh, ctrl, hd)
    let tube = strokePath(path, 46)
    clipped(belly) { blurred(tube, Col(0xA2560F, 0.3), 12, dy: 12) }
    glossy(tube, navyRamp, Gloss(mid: 0.5, volume: 0.35, shade: 0.4, bounce: 0.25, rim: 0.55, spec: 0.0))
    clipped(tube) { blurred(strokePath(moved(path, -5, -6), 8), Col(0x9DB5F5, 0.55), 4) }
    if stick { drawStick(hand: hd, sx: sx, gb: gb) }
    let hand = circle(hd.x, hd.y, 39)
    blurred(hand, SHADOW.alpha(0.25), 8, dy: 6)
    glossy(hand, navyRamp, Gloss(mid: 0.5, volume: 0.5, shade: 0.45, bounce: 0.3, rim: 0.6, spec: 0.85, specAt: P(0.34, 0.28),
                                 specSize: CGSize(width: 0.38, height: 0.22), specRot: -30))
}

func scarfBand() -> CGPath {
    let p = CGMutablePath()
    p.move(to: P(-212, -490))
    p.addQuadCurve(to: P(212, -490), control: P(0, -418))
    p.addQuadCurve(to: P(212, -392), control: P(254, -441))
    p.addQuadCurve(to: P(-212, -392), control: P(0, -318))
    p.addQuadCurve(to: P(-212, -490), control: P(-254, -441))
    p.closeSubpath()
    return p
}

/// Flick, the firefly director. `o` = point between the feet on the ground, `height` ≈ feet to antenna tips.
func drawFlick(at o: CGPoint, height: CGFloat, pose: Pose, dir: CGFloat = 1, look: CGPoint = .zero, tilt: CGFloat = 0,
               glowAmt: CGFloat = 1, sceneGlow: Bool = false, contact: Col? = nil) {
    let s = height / 1000
    group {
        C.translateBy(x: o.x, y: o.y)
        C.scaleBy(x: s, y: s)
        let gb: CGBlendMode = sceneGlow ? .screen : .normal
        if let cc = contact { blurred(ellipse(0, -6, 250, 40), cc, 24) }
        glow(P(0, -330), 430, YELLOW, 0.4 * glowAmt, blend: gb)
        glow(P(0, -240), 300, Col(0xFFF1A8), 0.32 * glowAmt, blend: gb)

        // wings (behind)
        layer(0.93) {
            for sx in [CGFloat(-1), 1] {
                drawWing(P(sx * 226, -390), 100, 55, sx * 16)
                drawWing(P(sx * 250, -512), 142, 77, -sx * 30)
            }
        }
        // antennae (behind head)
        group {
            headTilt(tilt)
            for sx in [CGFloat(-1), 1] { drawAntenna(sx, gb) }
        }
        // feet
        for sx in [CGFloat(-1), 1] {
            let f = ellipse(sx * 84, -36, 80, 42)
            blurred(f, SHADOW.alpha(0.3), 8, dy: 5)
            glossy(f, navyRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.5, bounce: 0.3, rim: 0.55, spec: 0.7, specAt: P(0.36, 0.28),
                                      specSize: CGSize(width: 0.36, height: 0.2), specRot: -10))
        }
        // glowing abdomen
        let belly = ellipse(0, -250, 216, 228)
        radial(belly, [(0, Col(0xFFFEF2)), (0.28, Col(0xFFF6BC)), (0.6, Col(0xFFE574)), (0.84, Col(0xFFD34E)), (1, Col(0xF4AE3C))],
               P(-18, -205), 262)
        innerShadow(belly, Col(0xE48A28, 0.5), blur: 58, dx: 0, dy: -24)
        innerShadow(belly, Col(0xFFF8D2, 0.6), blur: 12, dx: 0, dy: -7)
        innerShadow(belly, WHITE.alpha(0.55), blur: 16, dx: 6, dy: 10)
        clipped(belly) {
            for yy in [CGFloat(-150), -82] {
                blurred(strokePath(quadPath(P(-240, yy - 42), P(0, yy + 46), P(240, yy - 42)), 11), Col(0xF0A035, 0.2), 6)
            }
            blurred(ellipseR(P(-118, -318), 58, 26, rot: -38), WHITE.alpha(0.85), 9)
            fill(circle(-66, -347, 10), WHITE.alpha(0.9))
        }
        // scarf
        let band = scarfBand()
        let ks = -dir
        clipped(belly) { blurred(band, Col(0xC26A22, 0.5), 22, dy: 20) }
        let t2 = ribbonPath(P(ks * 104, -394), P(ks * 96, -236), bend: ks * -14, w0: 64, w1: 60, notch: 24)
        let t1 = ribbonPath(P(ks * 128, -394), P(ks * 184, -204), bend: ks * 18, w0: 78, w1: 72, notch: 28)
        for t in [t2, t1] {
            blurred(t, Col(0x7A1A2A, 0.35), 12, dx: 4, dy: 10)
            glossy(t, redRamp, Gloss(mid: 0.45, volume: 0.35, shade: 0.45, bounce: 0.25, rim: 0.5, spec: 0.55, specAt: P(0.4, 0.22),
                                     specSize: CGSize(width: 0.2, height: 0.3), specRot: 70))
        }
        blurred(band, Col(0x7A1A2A, 0.3), 10, dy: 8)
        glossy(band, redRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.5, bounce: 0.3, rim: 0.6, spec: 0.7, specAt: P(0.26, 0.34),
                                    specSize: CGSize(width: 0.2, height: 0.16), specRot: 14))
        clipped(band) {
            blurred(strokePath(quadPath(P(-200, -447), P(0, -372), P(200, -447)), 10), Col(0x8E1E2C, 0.4), 7)
            blurred(strokePath(quadPath(P(-188, -470), P(0, -398), P(188, -470)), 7), Col(0xFFB8AC, 0.45), 5)
        }
        let knot = ellipse(ks * 118, -394, 60, 52)
        blurred(knot, Col(0x7A1A2A, 0.45), 12, dy: 8)
        glossy(knot, redRamp, Gloss(mid: 0.5, volume: 0.45, shade: 0.5, bounce: 0.3, rim: 0.55, spec: 0.75, specAt: P(0.35, 0.28),
                                    specSize: CGSize(width: 0.36, height: 0.2), specRot: -20))
        // head
        group {
            headTilt(tilt)
            let head = ellipse(0, -624, 231, 207)
            clipped(band) { blurred(head, Col(0x6A1422, 0.45), 16, dy: 14) }
            glossy(head, yellowRamp, Gloss(mid: 0.56, volume: 0.6, shade: 0.42, bounce: 0.35, rim: 0.6, spec: 0.9, specAt: P(0.3, 0.19),
                                           specSize: CGSize(width: 0.25, height: 0.11), specRot: -30))
            clipped(head) { fill(circle(-150, -742, 11), WHITE.alpha(0.85)) }
            drawFace(look: look)
        }
        // arms (in front)
        let act: Arm, oth: Arm
        var stick = false
        switch pose {
        case .wave: act = armWave; oth = armRest
        case .pointer: act = armPointer; oth = armOpen; stick = true
        case .present: act = armPresent; oth = armRest
        case .think: act = armPresent; oth = armRest
        }
        drawArm(-dir, oth, stick: false, belly: belly, gb: gb)
        drawArm(dir, act, stick: stick, belly: belly, gb: gb)
    }
}

// MARK: - Props

struct CardStyle {
    var tab = false
    var ribbon = false
    var lines = 0          // 0 none, 1 script lines, 2 review A, 3 review B
    var header: Ramp? = nil
}

func bar(_ x: CGFloat, _ y: CGFloat, _ len: CGFloat, _ th: CGFloat, _ c: Col) {
    fill(rrect(x, y - th / 2, len, th, th / 2), c)
}

/// Thick cream card with a blue edge. Drawn centered at `c`, rotated by `rot` degrees.
func drawCard(_ c: CGPoint, w: CGFloat, h: CGFloat, rot: CGFloat, t: CGFloat, style: CardStyle,
              shadow: Col? = SHADOW.alpha(0.42), clipBelow: CGFloat? = nil) {
    group {
        if let cy = clipBelow { C.clip(to: CGRect(x: -20000, y: -20000, width: 40000, height: cy + 20000)) }
        C.translateBy(x: c.x, y: c.y)
        C.rotate(by: rad(rot))
        let r = w * 0.1
        let face = rrect(-w / 2, -h / 2, w, h, r)
        let b = w * 0.048
        let tv = P(t * 0.2, t)
        if let sc = shadow { blurred(moved(face, tv.x * 0.5, tv.y * 0.5), sc, w * 0.07, dx: w * 0.04, dy: w * 0.07) }
        if style.tab {
            let tab = rrect(-w * 0.38, -h / 2 - h * 0.085, w * 0.3, h * 0.17, w * 0.06)
            extrude(tab, tv, yellowRamp.dark, yellowRamp.deep)
            glossy(tab, yellowRamp, Gloss(mid: 0.5, volume: 0.55, shade: 0.25, bounce: 0.2, rim: 0.65, spec: 0.85, specAt: P(0.3, 0.2),
                                          specSize: CGSize(width: 0.4, height: 0.14), specRot: -6))
        }
        extrude(face, tv, blueRamp.dark, blueRamp.deep, bounce: blueRamp.light.alpha(0.6))
        glossy(face, blueRamp, Gloss(mid: 0.5, volume: 0.35, shade: 0.3, bounce: 0.3, rim: 0.7, spec: 0))
        let paper = rrect(-w / 2 + b, -h / 2 + b, w - 2 * b, h - 2 * b, r - b * 0.6)
        linear(paper, [(0, WHITE), (0.45, PAPER), (1, Col(0xF1E2C4))], P(-w / 2, -h / 2), P(w / 2, h / 2))
        if let hr = style.header {
            clipped(paper) {
                let bandP = rect(-w, -h / 2 - 4, w * 2, h * 0.27 + 4)
                glossy(bandP, hr, Gloss(mid: 0.5, volume: 0.45, shade: 0.35, bounce: 0.35, rim: 0, spec: 0))
                blurred(ellipseR(P(-w * 0.18, -h / 2 + h * 0.07), w * 0.26, h * 0.03, rot: -3), WHITE.alpha(0.55), w * 0.02)
                strokeP(linePath(P(-w, -h / 2 + h * 0.27), P(w, -h / 2 + h * 0.27)), hr.deep.alpha(0.35), 3)
            }
        }
        innerShadow(paper, Col(0x5E4B30, 0.32), blur: b * 0.9, dx: b * 0.1, dy: b * 0.35)
        clipped(paper) {
            blurred(poly([P(-w * 0.7, -h * 0.05), P(-w * 0.12, -h * 0.66), P(w * 0.02, -h * 0.66), P(-w * 0.7, h * 0.1)]), WHITE.alpha(0.4), w * 0.05)
        }
        let th = w * 0.045
        let lineC = Col(0xA7B2CF, 0.85)
        switch style.lines {
        case 1:
            bar(-w * 0.33, -h * 0.17, w * 0.3, th * 1.25, MIDNIGHT.alpha(0.55))
            bar(-w * 0.33, -h * 0.03, w * 0.4, th, lineC)
            bar(-w * 0.33, h * 0.09, w * 0.33, th, lineC)
            bar(-w * 0.33, h * 0.21, w * 0.38, th, lineC)
        case 2:
            let y0 = -h / 2 + h * 0.4
            fill(rrect(-w * 0.36, y0 + h * 0.11 - th * 1.1, w * 0.6, th * 2.2, th * 1.1), YELLOW.alpha(0.75))
            bar(-w * 0.33, y0, w * 0.55, th, lineC)
            bar(-w * 0.33, y0 + h * 0.11, w * 0.46, th, Col(0x3A4F8E))
            bar(-w * 0.33, y0 + h * 0.22, w * 0.62, th, lineC)
            bar(-w * 0.33, y0 + h * 0.33, w * 0.38, th, lineC)
        case 3:
            let y0 = -h / 2 + h * 0.4
            for (i, l) in [CGFloat(0.48), 0.4, 0.52, 0.3].enumerated() {
                let yy = y0 + h * 0.11 * CGFloat(i)
                fill(circle(-w * 0.3, yy, th * 0.75), i == 1 ? RED.alpha(0.9) : MIDNIGHT.alpha(0.45))
                bar(-w * 0.22, yy, w * l, th, i == 1 ? RED.alpha(0.75) : lineC)
            }
        default: break
        }
        if style.ribbon {
            let rx0 = w * 0.13, rw = w * 0.16
            let top = -h / 2 - h * 0.012, bot = h / 2 + h * 0.15
            let rib = poly([P(rx0, top), P(rx0 + rw, top), P(rx0 + rw, bot), P(rx0 + rw / 2, bot - rw * 0.5), P(rx0, bot)])
            blurred(rib, Col(0x3A0A14, 0.35), w * 0.02, dx: w * 0.012, dy: w * 0.02)
            linear(rib, [(0, redRamp.light), (0.4, redRamp.base), (1, redRamp.dark)], P(rx0, 0), P(rx0 + rw, 0))
            linear(rib, [(0, redRamp.deep.alpha(0)), (0.72, redRamp.deep.alpha(0)), (1, redRamp.deep.alpha(0.4))], P(0, top), P(0, bot))
            clipped(rib) { strokeP(linePath(P(rx0 + rw * 0.28, top), P(rx0 + rw * 0.28, bot)), WHITE.alpha(0.4), rw * 0.12) }
            fill(rrect(rx0 - w * 0.006, top - h * 0.014, rw + w * 0.012, h * 0.036, h * 0.012), redRamp.dark)
        }
    }
}

/// Rounded "pill" block seen slightly from above: top face at `topY` (its center line), front face of height `h`.
func drawBlock(cx: CGFloat, topY: CGFloat, w: CGFloat, d: CGFloat, h: CGFloat, ramp: Ramp,
               topStops: [(CGFloat, Col)]? = nil, shadow: Col? = SHADOW.alpha(0.5)) {
    let x0 = cx - w / 2, x1 = cx + w / 2
    let cw = min(w / 2, d * 2.4)
    let k: CGFloat = 0.5523
    if let sc = shadow {
        blurred(rrect2(x0 - 6, topY + h - d * 0.5, w + 12, d * 2.4, cw, d * 1.2), sc, d * 0.9, dy: d * 0.3)
    }
    let yb = topY + h
    let sp = CGMutablePath()
    sp.move(to: P(x0, topY))
    sp.addLine(to: P(x0, yb))
    sp.addCurve(to: P(x0 + cw, yb + d), control1: P(x0, yb + d * k), control2: P(x0 + cw * (1 - k), yb + d))
    sp.addLine(to: P(x1 - cw, yb + d))
    sp.addCurve(to: P(x1, yb), control1: P(x1 - cw * (1 - k), yb + d), control2: P(x1, yb + d * k))
    sp.addLine(to: P(x1, topY))
    sp.closeSubpath()
    linear(sp, [(0, ramp.base), (1, ramp.dark)], P(0, topY), P(0, yb + d))
    linear(sp, [(0, ramp.deep.alpha(0.6)), (0.16, ramp.deep.alpha(0)), (0.78, ramp.deep.alpha(0)), (1, ramp.deep.alpha(0.65))],
           P(x0, 0), P(x1, 0))
    clipped(sp) { blurred(rect(x0 + cw * 0.55, topY, max(8, w * 0.035), h + d), WHITE.alpha(0.14), max(6, w * 0.03)) }
    innerShadow(sp, ramp.light.alpha(0.6), blur: 4, dx: 0, dy: -3)
    let top = rrect2(x0, topY - d, w, 2 * d, cw, d)
    linear(top, topStops ?? [(0, ramp.light.mix(ramp.hi, 0.15)), (1, ramp.light.mix(ramp.base, 0.5))], P(0, topY - d), P(0, topY + d))
    innerShadow(top, ramp.deep.alpha(0.25), blur: d * 0.25, dx: 0, dy: d * 0.12)
    clipped(top) { blurred(ellipse(cx - w * 0.2, topY - d * 0.25, w * 0.22, d * 0.3), WHITE.alpha(0.25), d * 0.3) }
    let rim = CGMutablePath()
    rim.move(to: P(x0, topY))
    rim.addCurve(to: P(x0 + cw, topY + d), control1: P(x0, topY + d * k), control2: P(x0 + cw * (1 - k), topY + d))
    rim.addLine(to: P(x1 - cw, topY + d))
    rim.addCurve(to: P(x1, topY), control1: P(x1 - cw * (1 - k), topY + d), control2: P(x1, topY + d * k))
    strokeP(rim, ramp.hi.alpha(0.85), max(2.5, d * 0.08))
}

/// Cylinder-ish disk: top ellipse + extruded front.
func drawDisk(c: CGPoint, rx: CGFloat, ry: CGFloat, h: CGFloat, ramp: Ramp, topStops: [(CGFloat, Col)]? = nil) {
    var pts: [CGPoint] = []
    for i in 0...80 { let a = CGFloat.pi * CGFloat(i) / 80; pts.append(P(c.x - rx * cos(a), c.y + ry * sin(a))) }
    for i in (0...80).reversed() { let a = CGFloat.pi * CGFloat(i) / 80; pts.append(P(c.x - rx * cos(a), c.y + h + ry * sin(a))) }
    let side = poly(pts)
    linear(side, [(0, ramp.deep), (0.12, ramp.dark), (0.32, ramp.base), (0.45, ramp.light), (0.6, ramp.base), (0.88, ramp.dark), (1, ramp.deep)],
           P(c.x - rx, 0), P(c.x + rx, 0))
    innerShadow(side, ramp.light.alpha(0.55), blur: 4, dx: 0, dy: -3)
    let top = ellipse(c.x, c.y, rx, ry)
    linear(top, topStops ?? [(0, ramp.light.mix(ramp.hi, 0.2)), (1, ramp.base)], P(0, c.y - ry), P(0, c.y + ry))
    innerShadow(top, ramp.hi.alpha(0.5), blur: ry * 0.1, dx: 0, dy: ry * 0.06)
    clipped(top) { blurred(ellipse(c.x - rx * 0.3, c.y - ry * 0.35, rx * 0.3, ry * 0.18), WHITE.alpha(0.4), ry * 0.15) }
    var fr: [CGPoint] = []
    for i in 0...80 { let a = CGFloat.pi * CGFloat(i) / 80; fr.append(P(c.x - rx * cos(a), c.y + ry * sin(a))) }
    strokeP(poly(fr, closed: false), ramp.hi.alpha(0.8), max(2.5, ry * 0.05))
}

/// Round blue stage timer with a thick yellow rim, a red top button and an EMPTY dial.
func drawTimer(c: CGPoint, R: CGFloat, shadow: Col? = SHADOW.alpha(0.45), gb: CGBlendMode = .normal) {
    if let sc = shadow { blurred(ellipse(c.x + R * 0.04, c.y + R * 1.02, R * 0.86, R * 0.12), sc, R * 0.08) }
    // feet
    for sx in [CGFloat(-1), 1] {
        let fc = P(c.x + sx * R * 0.55, c.y + R * 0.9)
        let foot = ellipseR(fc, R * 0.2, R * 0.12, rot: sx * -18)
        blurred(foot, SHADOW.alpha(0.3), R * 0.03, dy: R * 0.02)
        glossy(foot, blueRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.5, bounce: 0.3, rim: 0.55, spec: 0.6, specAt: P(0.35, 0.3),
                                     specSize: CGSize(width: 0.4, height: 0.2), specRot: sx * -18))
    }
    // stem + button
    let stem = rrect(c.x - R * 0.11, c.y - R * 1.13, R * 0.22, R * 0.22, R * 0.05)
    glossy(stem, yellowRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.4, bounce: 0.2, rim: 0.5, spec: 0.5, specAt: P(0.3, 0.3),
                                   specSize: CGSize(width: 0.25, height: 0.4), specRot: 90))
    let btn = rrect(c.x - R * 0.24, c.y - R * 1.29, R * 0.48, R * 0.19, R * 0.095)
    extrude(btn, P(0, R * 0.045), redRamp.dark, redRamp.deep)
    glossy(btn, redRamp, Gloss(mid: 0.5, volume: 0.55, shade: 0.35, bounce: 0.3, rim: 0.65, spec: 0.95, specAt: P(0.3, 0.3),
                               specSize: CGSize(width: 0.36, height: 0.26), specRot: -6))
    // side nub
    let nubC = c + dirv(-50) * (R * 0.98)
    let nub = ellipseR(nubC, R * 0.1, R * 0.07, rot: -50)
    glossy(nub, yellowRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.4, bounce: 0.2, rim: 0.5, spec: 0.6))
    // body with thickness
    let body = circle(c.x, c.y, R)
    let thick = circle(c.x + R * 0.035, c.y + R * 0.075, R)
    blurred(thick, SHADOW.alpha(0.35), R * 0.05, dx: R * 0.02, dy: R * 0.04)
    linear(thick, [(0, blueRamp.dark), (1, blueRamp.deep)], P(0, c.y), P(0, c.y + R * 1.08))
    innerShadow(thick, blueRamp.light.alpha(0.5), blur: 3, dx: 0, dy: -3)
    glossy(body, blueRamp, Gloss(mid: 0.45, volume: 0.5, shade: 0.5, bounce: 0.35, rim: 0.6, spec: 0.9, specAt: P(0.24, 0.17),
                                 specSize: CGSize(width: 0.2, height: 0.08), specRot: -42))
    // yellow rim (torus)
    let ro = R * 0.88, ri = R * 0.67
    let ring = CGMutablePath(); ring.addPath(circle(c.x, c.y, ro)); ring.addPath(circle(c.x, c.y, ri))
    blurred(circle(c.x, c.y, ro), SHADOW.alpha(0.4), R * 0.04, dx: R * 0.01, dy: R * 0.03)
    group {
        C.addPath(ring); C.clip(using: .evenOdd)
        let a0 = ri / ro
        radial(nil, [(0, yellowRamp.deep), (a0, yellowRamp.deep), (a0 + (1 - a0) * 0.35, yellowRamp.light), (a0 + (1 - a0) * 0.62, yellowRamp.base),
                     (1, yellowRamp.dark)], c, ro)
        linear(nil, [(0, yellowRamp.hi.alpha(0.45)), (0.45, yellowRamp.hi.alpha(0)), (0.6, yellowRamp.deep.alpha(0)), (1, yellowRamp.deep.alpha(0.55))],
               P(0, c.y - ro), P(0, c.y + ro))
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: (ro + ri) / 2 + R * 0.02, startAngle: rad(200), endAngle: rad(262), clockwise: false)
        blurred(strokePath(arc, R * 0.05), WHITE.alpha(0.85), R * 0.02)
        let arc2 = CGMutablePath()
        arc2.addArc(center: c, radius: (ro + ri) / 2, startAngle: rad(20), endAngle: rad(60), clockwise: false)
        blurred(strokePath(arc2, R * 0.03), WHITE.alpha(0.4), R * 0.02)
    }
    // dial (empty)
    let dial = circle(c.x, c.y, ri)
    radial(dial, [(0, WHITE), (0.55, PAPER), (1, Col(0xE9D9BC))], P(c.x - R * 0.12, c.y - R * 0.16), ri * 1.15)
    innerShadow(dial, MIDNIGHT.alpha(0.45), blur: R * 0.07, dx: R * 0.01, dy: R * 0.045)
    innerShadow(dial, Col(0xD9822A, 0.35), blur: R * 0.02, dx: 0, dy: -R * 0.012)
    clipped(dial) {
        blurred(ellipseR(P(c.x - R * 0.26, c.y - R * 0.34), R * 0.3, R * 0.1, rot: -38), WHITE.alpha(0.8), R * 0.035)
        blurred(ellipseR(P(c.x + R * 0.36, c.y + R * 0.3), R * 0.14, R * 0.04, rot: -40), WHITE.alpha(0.55), R * 0.02)
    }
}

/// Theatre lamp head. `d` = direction the lamp points (image plane), `k` = lens foreshortening (1 = facing viewer).
/// Returns (lens center, lens major-axis direction).
@discardableResult
func drawLamp(F: CGPoint, R: CGFloat, d: CGPoint, k: CGFloat, len: CGFloat, glowA: CGFloat, gb: CGBlendMode,
              shadow: Col? = SHADOW.alpha(0.45)) -> (CGPoint, CGPoint) {
    let dn = d.norm
    var n = dn.perp
    if n.y > 0 || (abs(n.y) < 1e-6 && n.x < 0) { n = n * -1 }
    let ang = atan2(n.y, n.x) * 180 / .pi
    let B = F - dn * len
    let housing = poly(hull(ellipsePoints(F, R * 1.1, R * 1.1 * k, rot: ang, n: 120) + ellipsePoints(B, R * 0.9, R * 0.9 * k, rot: ang, n: 120)))
    glow(F, R * 2.3, YELLOW, glowA * 0.6, blend: gb)
    if let sc = shadow { blurred(housing, sc, R * 0.22, dx: R * 0.06, dy: R * 0.14) }
    let mid = mixP(F, B, 0.5)
    linear(housing, [(0, Col(0x6186DE)), (0.28, Col(0x2E50AA)), (0.68, Col(0x1A3478)), (1, Col(0x0C1A45))], mid + n * (R * 1.1), mid - n * (R * 1.1))
    innerShadow(housing, Col(0xA4BEFF, 0.55), blur: R * 0.06, dx: R * 0.02, dy: R * 0.04)
    innerShadow(housing, Col(0x050B22, 0.4), blur: R * 0.2, dx: 0, dy: -R * 0.08)
    clipped(housing) {
        blurred(strokePath(linePath(B + n * (R * 0.7), F + n * (R * 0.78) - dn * (R * 0.25)), R * 0.1), WHITE.alpha(0.42), R * 0.05)
        for i in 0..<3 {
            let q = mixP(B, F, 0.18 + CGFloat(i) * 0.16) + n * (R * 0.25)
            strokeP(linePath(q - n * (R * 0.2), q + n * (R * 0.2)), Col(0x0A1535, 0.55), R * 0.07)
            strokeP(linePath(q - n * (R * 0.2) + dn * (R * 0.04), q + n * (R * 0.2) + dn * (R * 0.04)), Col(0x7F9DEB, 0.3), R * 0.025)
        }
    }
    let rimOuter = ellipseR(F, R * 1.1, R * 1.1 * k, rot: ang)
    let lens = ellipseR(F, R, R * k, rot: ang)
    group {
        let ringP = CGMutablePath(); ringP.addPath(rimOuter); ringP.addPath(lens)
        C.addPath(ringP); C.clip(using: .evenOdd)
        linear(nil, [(0, Col(0xB3C8FF)), (0.4, Col(0x4A70D0)), (1, Col(0x14296A))], F + n * (R * 1.1), F - n * (R * 1.1))
    }
    radial(lens, [(0, Col(0xFFFFF4)), (0.35, Col(0xFFF3A8)), (0.72, YELLOW), (1, Col(0xF0A636))], F + n * (R * 0.12), R, sy: k, rot: ang)
    for f in [CGFloat(0.8), 0.6, 0.4] {
        strokeP(ellipseR(F, R * f, R * k * f, rot: ang), WHITE.alpha(0.3), R * 0.028)
    }
    innerShadow(lens, Col(0xC96F1E, 0.5), blur: R * 0.08, dx: 0, dy: R * 0.03)
    clipped(lens) {
        blurred(ellipseR(F + n * (R * 0.5) - dn * (R * k * 0.25), R * 0.3, R * k * 0.1, rot: ang), WHITE.alpha(0.9), R * 0.035)
    }
    glow(F, R * 1.25, Col(0xFFF3B0), glowA * 0.55, blend: gb)
    return (F, n)
}

func drawBeam(src: CGPoint, n: CGPoint, half: CGFloat, pool: CGPoint, prx: CGFloat, pry: CGFloat, strength: CGFloat) {
    let warm = Col(0xFFC53D)
    for kk in 0..<14 {
        let f = 1.08 - CGFloat(kk) * 0.055
        let pts = [src + n * (half * f), src - n * (half * f)] + ellipsePoints(pool, prx * f, pry * f, n: 64)
        linear(poly(hull(pts)), [(0, warm.alpha(0.075 * strength)), (0.55, warm.alpha(0.034 * strength)), (1, warm.alpha(0.02 * strength))],
               src, pool, blend: .screen)
    }
    glow(pool, prx * 1.12, warm, 0.5 * strength, sy: pry / prx, blend: .screen)
    glow(pool, prx * 0.62, Col(0xFFF6D0), 0.32 * strength, sy: pry / prx, blend: .screen)
    var rng = RNG(s: UInt64(src.x * 31 + src.y))
    for _ in 0..<26 {
        let t = rng.range(0.12, 0.85)
        let axis = mixP(src, pool, t)
        let wdt = lerp(half, prx, t) * 0.8
        let pnt = axis + P(rng.range(-wdt, wdt), rng.range(-12, 12))
        let rr = rng.range(2.5, 6)
        glow(pnt, rr * 3, Col(0xFFF3C0), 0.45, blend: .screen)
    }
}

// MARK: - Theatre set

let FLOOR_BACK: CGFloat = 1330
let FRONT_Y: CGFloat = 1598
let FRONT_CTRL: CGFloat = 1700
let FACE_H: CGFloat = 84

func drawBackdrop(warm: CGPoint) {
    let full = rect(0, 0, CW, CH)
    linear(full, [(0, Col(0x0A1840)), (0.5, Col(0x122864)), (0.62, MIDNIGHT), (1, Col(0x0D1D4E))], P(0, 0), P(0, CH))
    let wall = rect(0, 0, CW, FLOOR_BACK + 10)
    linear(wall, [(0, Col(0x091640)), (0.55, Col(0x132A68)), (1, Col(0x1B397F))], P(0, 0), P(0, FLOOR_BACK))
    var dstops: [(CGFloat, Col)] = [], lstops: [(CGFloat, Col)] = []
    let period: CGFloat = 150
    let N = 260
    for i in 0...N {
        let u = CGFloat(i) / CGFloat(N)
        let v = (cos(u * CW / period * 2 * .pi + 0.6) + 1) / 2
        dstops.append((u, Col(0x040A26, 0.42 * pow(1 - v, 1.5))))
        lstops.append((u, Col(0x4A70D0, 0.16 * pow(v, 3))))
    }
    linear(wall, dstops, P(0, 0), P(CW, 0))
    linear(wall, lstops, P(0, 0), P(CW, 0), blend: .screen)
    glow(P(CW / 2, 1050), 950, Col(0x2E56BE), 0.38, sy: 0.8, blend: .screen)
    glow(warm, 560, YELLOW, 0.15, sy: 0.85, blend: .screen)
    linear(wall, [(0, SHADOW.alpha(0)), (0.8, SHADOW.alpha(0)), (1, SHADOW.alpha(0.5))], P(0, 0), P(0, FLOOR_BACK))
    linear(wall, [(0, SHADOW.alpha(0.5)), (0.25, SHADOW.alpha(0))], P(0, 0), P(0, FLOOR_BACK))
}

func drawBottomZone(from y0: CGFloat) {
    let z = rect(0, y0, CW, CH - y0)
    linear(z, [(0, Col(0x122864)), (0.3, MIDNIGHT), (1, Col(0x0E1F52))], P(0, y0), P(0, CH))
    blurred(rect(-100, y0 - 40, CW + 200, 40), SHADOW.alpha(0.55), 40, dy: 24)
}

func drawStageFull() {
    drawBottomZone(from: FRONT_Y + FACE_H - 10)
    let top = CGMutablePath()
    top.move(to: P(-60, FLOOR_BACK)); top.addLine(to: P(CW + 60, FLOOR_BACK)); top.addLine(to: P(CW + 60, FRONT_Y))
    top.addQuadCurve(to: P(-60, FRONT_Y), control: P(CW / 2, FRONT_CTRL)); top.closeSubpath()
    let midFront = FRONT_Y + (FRONT_CTRL - FRONT_Y) / 2
    linear(top, [(0, Col(0x10255E)), (0.5, Col(0x1C3984)), (1, Col(0x2B4CA6))], P(0, FLOOR_BACK), P(0, midFront))
    clipped(top) {
        let vp = P(CW / 2, 760)
        for i in -12...24 {
            let a = P(CGFloat(i) * 92 - 20, 1780)
            let t = (a.y - FLOOR_BACK) / (a.y - vp.y)
            let b = mixP(a, vp, t)
            strokeP(linePath(a, b), Col(0x081640, 0.3), 3)
            strokeP(linePath(a + P(4, 0), b + P(2, 0)), Col(0x5A80E0, 0.09), 2)
        }
    }
    linear(top, [(0, SHADOW.alpha(0.55)), (0.3, SHADOW.alpha(0))], P(0, FLOOR_BACK), P(0, midFront))
    let face = CGMutablePath()
    face.move(to: P(-60, FRONT_Y)); face.addQuadCurve(to: P(CW + 60, FRONT_Y), control: P(CW / 2, FRONT_CTRL))
    face.addLine(to: P(CW + 60, FRONT_Y + FACE_H)); face.addQuadCurve(to: P(-60, FRONT_Y + FACE_H), control: P(CW / 2, FRONT_CTRL + FACE_H))
    face.closeSubpath()
    linear(face, [(0, Col(0x1D397F)), (0.3, Col(0x162E6E)), (1, Col(0x0F2256))], P(0, midFront), P(0, midFront + FACE_H))
    let lip = quadPath(P(-60, FRONT_Y), P(CW / 2, FRONT_CTRL), P(CW + 60, FRONT_Y))
    blurred(strokePath(lip, 14), Col(0x6F8FE8, 0.45), 8)
    strokeP(lip, Col(0x9DB5F8, 0.9), 4)
    strokeP(quadPath(P(-60, FRONT_Y + 24), P(CW / 2, FRONT_CTRL + 24), P(CW + 60, FRONT_Y + 24)), Col(0xF4B03C, 0.5), 5)
}

func drawStageRound(c: CGPoint, rx: CGFloat, ry: CGFloat, h: CGFloat, bulbs: Bool) {
    drawBottomZone(from: FLOOR_BACK + 150)
    let floor = rect(0, FLOOR_BACK, CW, 400)
    linear(floor, [(0, Col(0x0E2159)), (1, Col(0x122864))], P(0, FLOOR_BACK), P(0, FLOOR_BACK + 400))
    linear(floor, [(0, SHADOW.alpha(0.5)), (0.3, SHADOW.alpha(0))], P(0, FLOOR_BACK), P(0, FLOOR_BACK + 400))
    blurred(ellipse(c.x, c.y + h + 12, rx * 1.03, ry * 1.08), SHADOW.alpha(0.6), 36, dy: 12)
    drawDisk(c: c, rx: rx, ry: ry, h: h, ramp: blueRamp,
             topStops: [(0, Col(0x14306F)), (0.55, Col(0x21428F)), (1, Col(0x2F52AE))])
    clipped(ellipse(c.x, c.y, rx, ry)) {
        for f in [CGFloat(0.82), 0.62] { strokeP(ellipse(c.x, c.y, rx * f, ry * f), Col(0x6F8FE8, 0.16), 4) }
        linear(nil, [(0, SHADOW.alpha(0.45)), (0.35, SHADOW.alpha(0))], P(0, c.y - ry), P(0, c.y + ry))
    }
    var tr: [CGPoint] = []
    for i in 0...80 { let a = CGFloat.pi * CGFloat(i) / 80; tr.append(P(c.x - rx * cos(a), c.y + ry * sin(a) + h * 0.28)) }
    strokeP(poly(tr, closed: false), Col(0xF4B03C, 0.55), 5)
    if bulbs {
        for i in 0..<9 {
            let a = CGFloat.pi * (0.14 + 0.72 * CGFloat(i) / 8)
            let p = P(c.x - rx * cos(a), c.y + ry * sin(a) + h * 0.62)
            glow(p, 46, YELLOW, 0.5, blend: .screen)
            glossy(circle(p.x, p.y, 11), yellowRamp, Gloss(mid: 0.4, volume: 0.7, shade: 0.2, bounce: 0.2, rim: 0.4, spec: 0.9, specAt: P(0.35, 0.3),
                                                            specSize: CGSize(width: 0.4, height: 0.3), specRot: -30))
        }
    }
}

func drawCurtain(right: Bool, topW: CGFloat, tieY: CGFloat, bottomY: CGFloat, folds: Int, tieF: CGFloat = 0.42, botF: CGFloat = 0.72) {
    group {
        if right { C.translateBy(x: CW, y: 0); C.scaleBy(x: -1, y: 1) }
        let xL: CGFloat = -40, topY: CGFloat = -30
        let tieX = topW * tieF, botX = topW * botF
        func innerX(_ y: CGFloat) -> CGFloat {
            if y <= tieY {
                let t = max(0, (y - topY) / (tieY - topY))
                let e = t * t * (3 - 2 * t)
                return topW + (tieX - topW) * e
            }
            let t = min(1, (y - tieY) / (bottomY - tieY))
            let e = 1 - (1 - t) * (1 - t)
            return tieX + (botX - tieX) * e
        }
        func xAt(_ t: CGFloat, _ y: CGFloat) -> CGFloat { xL + (innerX(min(y, bottomY)) - xL) * t }
        var pts: [CGPoint] = [P(xL, topY)]
        var y = topY
        while y < bottomY { pts.append(P(innerX(y), y)); y += 6 }
        pts.append(P(innerX(bottomY), bottomY))
        let n = folds
        let fn = CGFloat(n)
        for i in 0..<n {
            let xa = xAt(1 - CGFloat(i) / fn, bottomY), xb = xAt(1 - CGFloat(i + 1) / fn, bottomY)
            for j in 1...12 {
                let t = CGFloat(j) / 12
                pts.append(P(lerp(xa, xb, t), bottomY + 26 * sin(.pi * t)))
            }
        }
        let shape = poly(pts)
        func band(_ t0: CGFloat, _ t1: CGFloat) -> CGPath {
            var l: [CGPoint] = [], r: [CGPoint] = []
            var yy = topY
            while yy <= bottomY + 44 { l.append(P(xAt(t0, yy), yy)); r.append(P(xAt(t1, yy), yy)); yy += 10 }
            return poly(l + r.reversed())
        }
        blurred(shape, SHADOW.alpha(0.6), 46, dx: 34, dy: 14)
        linear(shape, [(0, Col(0x9A2331)), (0.3, Col(0xD03B3E)), (0.75, RED), (1, Col(0xC4363A))], P(0, 0), P(0, bottomY + 30))
        let foldW = (topW - xL) / fn
        clipped(shape) {
            for i in 1..<n {
                let tv = CGFloat(i) / fn
                blurred(band(tv - 0.12 / fn, tv + 0.1 / fn), Col(0x6A1222, 0.85), foldW * 0.28)
            }
            for i in 0..<n {
                let tc = (CGFloat(i) + 0.5) / fn
                blurred(band(tc - 0.22 / fn, tc + 0.12 / fn), Col(0xFF7A6B, 0.6), foldW * 0.2)
                blurred(band(tc - 0.1 / fn, tc - 0.04 / fn), Col(0xFFC6BA, 0.6), 4)
            }
            linear(nil, [(0, SHADOW.alpha(0.62)), (0.28, SHADOW.alpha(0))], P(0, 0), P(0, 1000))
            linear(nil, [(0, SHADOW.alpha(0.4)), (0.55, SHADOW.alpha(0))], P(xL, 0), P(topW, 0))
            glow(P(innerX(tieY), tieY), 150, SHADOW, 0.35)
        }
        innerShadow(shape, Col(0x5A0E1C, 0.6), blur: 34, dx: 0, dy: -20)
        innerShadow(shape, Col(0xFF9E90, 0.6), blur: 10, dx: -9, dy: 0)
        // tie-back
        let te = innerX(tieY)
        let tiePath = quadPath(P(xL, tieY - 22), P((xL + te) / 2, tieY + 26), P(te + 12, tieY - 2))
        let tube = strokePath(tiePath, 54)
        blurred(tube, SHADOW.alpha(0.45), 14, dx: 4, dy: 14)
        glossy(tube, yellowRamp, Gloss(mid: 0.45, volume: 0.4, shade: 0.45, bounce: 0.3, rim: 0.55, spec: 0.75, specAt: P(0.55, 0.3),
                                       specSize: CGSize(width: 0.45, height: 0.14), specRot: 5))
        let kc = P(te + 20, tieY + 4)
        let tas = CGMutablePath()
        tas.move(to: P(kc.x - 12, kc.y + 10))
        tas.addCurve(to: P(kc.x - 34, kc.y + 128), control1: P(kc.x - 16, kc.y + 50), control2: P(kc.x - 40, kc.y + 92))
        tas.addQuadCurve(to: P(kc.x + 34, kc.y + 128), control: P(kc.x, kc.y + 150))
        tas.addCurve(to: P(kc.x + 12, kc.y + 10), control1: P(kc.x + 40, kc.y + 92), control2: P(kc.x + 16, kc.y + 50))
        tas.closeSubpath()
        blurred(tas, SHADOW.alpha(0.45), 10, dx: 4, dy: 12)
        glossy(tas, yellowRamp, Gloss(mid: 0.45, volume: 0.45, shade: 0.5, bounce: 0.3, rim: 0.5, spec: 0.6, specAt: P(0.35, 0.3),
                                      specSize: CGSize(width: 0.3, height: 0.25), specRot: 70))
        clipped(tas) {
            for q in -3...3 {
                let qq = CGFloat(q)
                strokeP(linePath(P(kc.x + qq * 8, kc.y + 76), P(kc.x + qq * 11, kc.y + 150)), Col(0xC9731F, 0.5), 3)
            }
            strokeP(linePath(P(kc.x - 40, kc.y + 70), P(kc.x + 40, kc.y + 70)), Col(0xD9822A, 0.7), 6)
        }
        glossy(circle(kc.x, kc.y, 28), yellowRamp, Gloss(mid: 0.5, volume: 0.55, shade: 0.4, bounce: 0.3, rim: 0.55, spec: 0.9, specAt: P(0.35, 0.3),
                                                          specSize: CGSize(width: 0.4, height: 0.25), specRot: -30))
    }
}

func drawValance(swags: Int = 4, baseY: CGFloat = 150, depth: CGFloat = 62) {
    let x0: CGFloat = -30
    let sw = (CW + 60) / CGFloat(swags)
    let p = CGMutablePath()
    p.move(to: P(x0, -20)); p.addLine(to: P(x0 + sw * CGFloat(swags), -20)); p.addLine(to: P(x0 + sw * CGFloat(swags), baseY))
    for i in (0..<swags).reversed() {
        let xa = x0 + sw * CGFloat(i + 1), xb = x0 + sw * CGFloat(i)
        p.addQuadCurve(to: P(xb, baseY), control: P((xa + xb) / 2, baseY + depth * 2))
    }
    p.closeSubpath()
    blurred(p, SHADOW.alpha(0.65), 40, dy: 30)
    linear(p, [(0, Col(0x6E1424)), (0.45, Col(0xB42F37)), (1, Col(0xE54642))], P(0, 0), P(0, baseY + depth))
    clipped(p) {
        for i in 0..<swags {
            let xa = x0 + sw * CGFloat(i), xb = xa + sw
            let m = (xa + xb) / 2
            for (off, dark) in [(CGFloat(24), false), (46, true), (70, false), (96, true)] {
                let path = quadPath(P(xa + off * 0.5, baseY - off * 0.9), P(m, baseY + depth * 2 - off * 1.5), P(xb - off * 0.5, baseY - off * 0.9))
                if dark { blurred(strokePath(path, 14), Col(0x5A0E1C, 0.45), 9) }
                else { blurred(strokePath(path, 9), Col(0xFF9A8C, 0.4), 6) }
            }
        }
    }
    innerShadow(p, Col(0xFF8C7E, 0.55), blur: 6, dx: 0, dy: -5)
    let trim = CGMutablePath()
    trim.move(to: P(x0, baseY))
    for i in 0..<swags {
        let xa = x0 + sw * CGFloat(i), xb = xa + sw
        trim.addQuadCurve(to: P(xb, baseY), control: P((xa + xb) / 2, baseY + depth * 2))
    }
    let tt = strokePath(trim, 15)
    blurred(tt, SHADOW.alpha(0.4), 8, dy: 8)
    fill(tt, yellowRamp.dark)
    clipped(tt) {
        blurred(strokePath(moved(trim, 0, -3), 5), yellowRamp.hi.alpha(0.9), 2)
    }
    for i in 0...swags {
        let x = x0 + sw * CGFloat(i)
        let k = circle(x, baseY + 6, 22)
        blurred(k, SHADOW.alpha(0.4), 8, dy: 8)
        glossy(k, yellowRamp, Gloss(mid: 0.5, volume: 0.55, shade: 0.4, bounce: 0.3, rim: 0.55, spec: 0.9, specAt: P(0.35, 0.3),
                                    specSize: CGSize(width: 0.4, height: 0.25), specRot: -30))
    }
}

func drawHangingRod(x: CGFloat, to y: CGFloat) {
    let r = rrect(x - 9, -20, 18, y + 20, 9)
    fill(r, Col(0x0E1F50))
    clipped(r) { strokeP(linePath(P(x - 3, -20), P(x - 3, y)), Col(0x5A80E0, 0.5), 4) }
}

func vignette() {
    radial(rect(0, 0, CW, CH), [(0, SHADOW.alpha(0)), (0.62, SHADOW.alpha(0)), (1, SHADOW.alpha(0.5))], P(CW / 2, 1150), 1750, sy: 1.0)
}

// MARK: - Onboarding scenes (1290 x 2796)

func sceneSegments() {
    newCanvas(1290, 2796, opaque: true)
    let pool = P(660, 1500)
    drawBackdrop(warm: P(660, 1080))
    drawStageFull()
    let lampF = P(930, 330)
    drawHangingRod(x: lampF.x - 30, to: 250)
    let dl = (pool - lampF).norm
    drawBeam(src: lampF, n: dl.perp, half: 62, pool: pool, prx: 500, pry: 118, strength: 1)
    drawCurtain(right: false, topW: 450, tieY: 1010, bottomY: 1612, folds: 6)
    drawCurtain(right: true, topW: 250, tieY: 800, bottomY: 1604, folds: 4)
    drawValance()
    drawLamp(F: lampF, R: 64, d: dl, k: 0.5, len: 96, glowA: 0.55, gb: .screen)
    // three steps with cards
    let xs: [CGFloat] = [694, 894, 1094], hs: [CGFloat] = [64, 150, 236], rots: [CGFloat] = [-4, 3, -2]
    for i in 0..<3 {
        let floorY: CGFloat = 1530
        let d: CGFloat = 31
        let topY = floorY - hs[i] - d
        drawBlock(cx: xs[i], topY: topY, w: 180, d: d, h: hs[i], ramp: blueRamp)
        let cw: CGFloat = 204, chh: CGFloat = 266, t: CGFloat = 21
        blurred(ellipse(xs[i] + 6, topY + 2, cw * 0.5, 13), SHADOW.alpha(0.55), 10)
        drawCard(P(xs[i], topY + 4 - chh / 2 - t), w: cw, h: chh, rot: rots[i], t: t,
                 style: CardStyle(tab: true, ribbon: true, lines: 1), shadow: nil)
    }
    drawFlick(at: P(318, 1570), height: 770, pose: .present, dir: 1, look: P(0.7, 0.2), tilt: 4, sceneGlow: true,
              contact: SHADOW.alpha(0.55))
    sparkle(P(560, 820), 20, 0.9)
    sparkle(P(1040, 900), 14, 0.8)
    sparkle(P(210, 700), 12, 0.7)
    sparkle(P(760, 1000), 10, 0.6)
    vignette()
    noise(2, seed: 11)
}

func sceneStage() {
    newCanvas(1290, 2796, opaque: true)
    let stageC = P(645, 1466)
    let pool = P(650, 1470)
    drawBackdrop(warm: P(650, 1060))
    drawStageRound(c: stageC, rx: 604, ry: 150, h: 92, bulbs: true)
    let lampF = P(330, 330)
    drawHangingRod(x: lampF.x + 26, to: 250)
    let dl = (pool - lampF).norm
    drawBeam(src: lampF, n: dl.perp, half: 62, pool: pool, prx: 480, pry: 112, strength: 1.1)
    drawCurtain(right: false, topW: 320, tieY: 820, bottomY: 1590, folds: 5)
    drawCurtain(right: true, topW: 440, tieY: 840, bottomY: 1600, folds: 6)
    drawValance()
    drawLamp(F: lampF, R: 64, d: dl, k: 0.5, len: 96, glowA: 0.55, gb: .screen)
    drawTimer(c: P(832, 1206), R: 272, shadow: SHADOW.alpha(0.5), gb: .screen)
    drawFlick(at: P(386, 1552), height: 740, pose: .wave, dir: -1, look: P(0.35, 0.1), tilt: -5, sceneGlow: true,
              contact: SHADOW.alpha(0.55))
    sparkle(P(600, 800), 18, 0.9)
    sparkle(P(1090, 780), 13, 0.8)
    sparkle(P(230, 1000), 11, 0.6)
    vignette()
    noise(2, seed: 22)
}

func drawFlatBookmark(_ c: CGPoint, len: CGFloat, w: CGFloat, rot: CGFloat, squash: CGFloat) {
    group {
        C.translateBy(x: c.x, y: c.y)
        C.scaleBy(x: 1, y: squash)
        C.rotate(by: rad(rot))
        let p = poly([P(-len / 2, -w / 2), P(len / 2, -w / 2), P(len / 2 - w * 0.45, 0), P(len / 2, w / 2), P(-len / 2, w / 2)])
        blurred(p, SHADOW.alpha(0.45), w * 0.25, dx: w * 0.08, dy: w * 0.3)
        linear(p, [(0, redRamp.light), (0.45, redRamp.base), (1, redRamp.dark)], P(0, -w / 2), P(0, w / 2))
        clipped(p) {
            strokeP(linePath(P(-len / 2, -w * 0.25), P(len / 2, -w * 0.25)), WHITE.alpha(0.35), w * 0.1)
            strokeP(poly([P(-len / 2 + 10, -w * 0.36), P(len / 2 - 8, -w * 0.36)], closed: false), Col(0xFFB8AC, 0.7), 3, dash: [10, 8])
            strokeP(poly([P(-len / 2 + 10, w * 0.36), P(len / 2 - 8, w * 0.36)], closed: false), Col(0xFFB8AC, 0.5), 3, dash: [10, 8])
        }
        let cap = rrect(-len / 2 - 6, -w / 2 - 4, len * 0.16, w + 8, 8)
        glossy(cap, yellowRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.4, bounce: 0.2, rim: 0.5, spec: 0.6))
    }
}

func sceneReview() {
    newCanvas(1290, 2796, opaque: true)
    let pool = P(560, 1480)
    drawBackdrop(warm: P(560, 1060))
    drawStageFull()
    let lampF = P(300, 330)
    drawHangingRod(x: lampF.x + 26, to: 250)
    let dl = (pool - lampF).norm
    drawBeam(src: lampF, n: dl.perp, half: 62, pool: pool, prx: 500, pry: 115, strength: 1)
    drawCurtain(right: false, topW: 250, tieY: 930, bottomY: 1604, folds: 4)
    drawCurtain(right: true, topW: 460, tieY: 1010, bottomY: 1612, folds: 6)
    drawValance()
    drawLamp(F: lampF, R: 64, d: dl, k: 0.5, len: 96, glowA: 0.55, gb: .screen)
    // table
    let tcx: CGFloat = 486, topY: CGFloat = 1236, tw: CGFloat = 720, td: CGFloat = 64, floorY: CGFloat = 1540
    blurred(ellipse(tcx + 10, floorY + 4, tw * 0.5, 34), SHADOW.alpha(0.55), 26)
    for sx in [CGFloat(-1), 1] {
        let lx = tcx + sx * (tw / 2 - 96)
        let leg = rrect(lx - 24, topY, 48, floorY - topY, 24)
        linear(leg, [(0, blueRamp.deep), (0.3, blueRamp.light), (0.55, blueRamp.base), (1, blueRamp.deep)], P(lx - 24, 0), P(lx + 24, 0))
        linear(leg, [(0, SHADOW.alpha(0.6)), (0.35, SHADOW.alpha(0))], P(0, topY), P(0, floorY))
        let foot = ellipse(lx, floorY - 4, 42, 16)
        glossy(foot, blueRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.5, bounce: 0.3, rim: 0.5, spec: 0.4))
    }
    drawBlock(cx: tcx, topY: topY, w: tw, d: td, h: 40, ramp: blueRamp, shadow: SHADOW.alpha(0.3))
    // cards standing on the table
    let cw: CGFloat = 250, chh: CGFloat = 330, t: CGFloat = 22
    blurred(ellipse(356, topY - 16, cw * 0.5, 12), SHADOW.alpha(0.5), 10)
    blurred(ellipse(622, topY - 18, cw * 0.5, 12), SHADOW.alpha(0.5), 10)
    drawCard(P(350, topY - 14 - chh / 2 - t), w: cw, h: chh, rot: -5, t: t, style: CardStyle(lines: 2, header: redRamp), shadow: nil)
    drawCard(P(618, topY - 16 - chh / 2 - t), w: cw, h: chh, rot: 5, t: t, style: CardStyle(lines: 3, header: yellowRamp), shadow: nil)
    // bookmark + pencil lying on the table
    drawFlatBookmark(P(300, topY + 26), len: 230, w: 50, rot: -8, squash: 0.62)
    drawPencil(from: P(520, topY + 38), to: P(770, topY + 8), w: 30, squash: 0.8)
    drawFlick(at: P(1010, 1576), height: 740, pose: .think, dir: -1, look: P(-0.8, 0.15), tilt: -6, sceneGlow: true,
              contact: SHADOW.alpha(0.55))
    sparkle(P(760, 820), 18, 0.9)
    sparkle(P(180, 1060), 12, 0.7)
    sparkle(P(1140, 760), 12, 0.7)
    vignette()
    noise(2, seed: 33)
}

// MARK: - Sprites

func spriteFlick() {
    newCanvas(1050, 1200, opaque: false)
    drawFlick(at: P(446, 1112), height: 1000, pose: .pointer, dir: 1, look: P(0.25, -0.1), tilt: -3, glowAmt: 0.75,
              contact: SHADOW.alpha(0.28))
}

func spriteCards() {
    newCanvas(1200, 1028, opaque: false)
    blurred(ellipse(610, 918, 430, 36), SHADOW.alpha(0.22), 30)
    let st = CardStyle(tab: true, ribbon: true, lines: 1)
    drawCard(P(418, 520), w: 400, h: 520, rot: -13, t: 30, style: st, shadow: SHADOW.alpha(0.3))
    drawCard(P(604, 482), w: 400, h: 520, rot: -1, t: 30, style: st, shadow: SHADOW.alpha(0.32))
    drawCard(P(790, 530), w: 400, h: 520, rot: 12, t: 30, style: st, shadow: SHADOW.alpha(0.32))
}

func spriteSpotlight() {
    newCanvas(960, 1200, opaque: false)
    // Tripod stand (red)
    let hub = P(466, 900)
    let fL = P(236, 1108), fR = P(712, 1108), fB = P(540, 1040)
    for f in [fL, fR, fB] { blurred(ellipse(f.x + 8, f.y + 10, 58, 16), SHADOW.alpha(0.35), 12) }
    blurred(ellipse(476, 1090, 260, 44), SHADOW.alpha(0.16), 36)
    func leg(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat, dim: Bool) {
        let t = strokePath(linePath(a, b), w)
        glossy(t, redRamp, Gloss(mid: 0.45, volume: 0.35, shade: 0.45, bounce: 0.25, rim: 0.55, spec: 0))
        clipped(t) { blurred(strokePath(moved(linePath(a, b), -w * 0.18, -w * 0.12), w * 0.22), Col(0xFFBDB1, 0.75), w * 0.1) }
        if dim { fill(t, SHADOW.alpha(0.3)) }
        let foot = ellipse(b.x, b.y, w * 1.2, w * 0.5)
        glossy(foot, redRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.5, bounce: 0.3, rim: 0.5, spec: 0.5))
        if dim { fill(foot, SHADOW.alpha(0.3)) }
    }
    leg(hub, fB, 26, dim: true)
    let pole = rrect(hub.x - 22, 560, 44, hub.y - 560 + 10, 22)
    linear(pole, [(0, redRamp.deep), (0.26, redRamp.light), (0.5, redRamp.base), (1, redRamp.deep)], P(hub.x - 22, 0), P(hub.x + 22, 0))
    leg(hub, fL, 30, dim: false)
    leg(hub, fR, 30, dim: false)
    for (y, w) in [(CGFloat(hub.y - 6), CGFloat(80)), (740, 70)] {
        let col = rrect(hub.x - w / 2, y - 20, w, 40, 20)
        blurred(col, SHADOW.alpha(0.3), 6, dy: 5)
        glossy(col, yellowRamp, Gloss(mid: 0.5, volume: 0.5, shade: 0.4, bounce: 0.3, rim: 0.55, spec: 0.8, specAt: P(0.3, 0.3),
                                      specSize: CGSize(width: 0.3, height: 0.3), specRot: 0))
    }
    // Lamp head (blue can, pointing to the side) with barn doors
    let F = P(575, 418), R: CGFloat = 148, k: CGFloat = 0.6
    let d = P(0.94, 0.34).norm
    var n = d.perp; if n.y > 0 { n = n * -1 }
    let len: CGFloat = 232
    let mid = mixP(F, F - d * len, 0.5)
    // short soft light cone + glow in front of the lens
    let coneEnd = F + d * 200
    let cone = poly(hull([F + n * (R * 0.9), F - n * (R * 0.9)] + ellipsePoints(coneEnd, 70, 190, rot: atan2(n.y, n.x) * 180 / .pi - 90, n: 40)))
    linear(cone, [(0, Col(0xFFE27A, 0.42)), (0.45, Col(0xFFE27A, 0.1)), (1, Col(0xFFE27A, 0))], F, coneEnd)
    glow(F + d * 40, R * 1.55, Col(0xFFE27A), 0.55)
    drawLamp(F: F, R: R, d: d, k: k, len: len, glowA: 0.0, gb: .normal, shadow: SHADOW.alpha(0.3))
    // barn doors (top & bottom), hinged on the rim
    for side in [CGFloat(1), -1] {
        let hc = F + n * (R * 1.08 * side)
        let along = d * (R * k * 0.95)
        let fwd = d * (R * 0.42) + n * (R * 0.5 * side)
        let door = poly([hc - along, hc + along, hc + along * 1.15 + fwd, hc - along * 0.85 + fwd])
        let dd = door.copy(strokingWithWidth: 16, lineCap: .round, lineJoin: .round, miterLimit: 10).union(door)
        blurred(dd, SHADOW.alpha(0.3), 10, dx: 4, dy: 8)
        linear(dd, [(0, Col(0x3E63BF)), (1, Col(0x173276))], hc, hc + fwd)
        // warm light spilling on the inner face of the door
        clipped(dd) { linear(nil, [(0, YELLOW.alpha(side > 0 ? 0.35 : 0.2)), (0.6, YELLOW.alpha(0))], hc, hc + fwd) }
        innerShadow(dd, Col(0xA4BEFF, 0.6), blur: 5, dx: 2, dy: 3)
        let hinge = strokePath(linePath(hc - along * 0.9, hc + along * 0.9), 16)
        glossy(hinge, navyRamp, Gloss(mid: 0.5, volume: 0.4, shade: 0.4, bounce: 0.2, rim: 0.5, spec: 0))
    }
    // yoke arm in front (near side) + pivot knob
    let yokeNear = linePath(P(hub.x, 590), mid)
    let yt = strokePath(yokeNear, 40)
    blurred(yt, SHADOW.alpha(0.3), 10, dx: 5, dy: 8)
    glossy(yt, redRamp, Gloss(mid: 0.45, volume: 0.4, shade: 0.45, bounce: 0.3, rim: 0.6, spec: 0))
    clipped(yt) { blurred(strokePath(moved(yokeNear, -8, 0), 8), Col(0xFFBDB1, 0.8), 4) }
    let kn = circle(mid.x, mid.y, 36)
    blurred(kn, SHADOW.alpha(0.35), 8, dy: 6)
    glossy(kn, yellowRamp, Gloss(mid: 0.5, volume: 0.55, shade: 0.4, bounce: 0.3, rim: 0.55, spec: 0.9, specAt: P(0.35, 0.3),
                                 specSize: CGSize(width: 0.4, height: 0.25), specRot: -30))
    // lens glow on top
    glow(F, R * 1.15, Col(0xFFF3B0), 0.4)
}

func spriteTimer() {
    newCanvas(1090, 1200, opaque: false)
    drawTimer(c: P(540, 662), R: 390, shadow: SHADOW.alpha(0.28))
}

func spriteBookmark() {
    newCanvas(900, 1200, opaque: false)
    let cx: CGFloat = 450
    let top: CGFloat = 372, bot: CGFloat = 1112, rw: CGFloat = 316, notch: CGFloat = 132
    func off(_ y: CGFloat) -> CGFloat { 18 * sin((y - top) / (bot - top) * .pi * 1.25) }
    var l: [CGPoint] = [], r: [CGPoint] = []
    var y = top
    while y <= bot { l.append(P(cx - rw / 2 + off(y), y)); r.append(P(cx + rw / 2 + off(y), y)); y += 8 }
    let rib = poly(l + [P(cx + off(bot - notch), bot - notch)] + r.reversed())
    // loop (behind cap)
    let loopC = P(cx + 12, 212)
    let loopE = ellipseR(loopC, 112, 128, rot: 10)
    let loop = strokePath(loopE, 42)
    blurred(loop, SHADOW.alpha(0.3), 12, dx: 8, dy: 12)
    glossy(loop, blueRamp, Gloss(mid: 0.45, volume: 0.45, shade: 0.55, bounce: 0.3, rim: 0.65, spec: 0))
    clipped(loop) {
        let hl = CGMutablePath()
        hl.addArc(center: .zero, radius: 1, startAngle: rad(190), endAngle: rad(285), clockwise: false)
        var t = CGAffineTransform(translationX: loopC.x, y: loopC.y).rotated(by: rad(10)).scaledBy(x: 112, y: 128)
        let hlp = hl.copy(using: &t)!
        blurred(strokePath(moved(hlp, -6, -6), 10), WHITE.alpha(0.75), 5)
    }
    // shadow of the whole marker
    let capR = rrect(cx - 176, 292, 352, 112, 44)
    let all = CGMutablePath(); all.addPath(rib); all.addPath(capR)
    blurred(all, SHADOW.alpha(0.3), 30, dx: 22, dy: 30)
    // ribbon thickness + face
    extrude(rib, P(16, 10), redRamp.dark, redRamp.deep)
    linear(rib, [(0, Col(0xFF7B6E)), (0.22, Col(0xF55C52)), (0.6, RED), (1, Col(0xB42D35))], P(cx - rw / 2, 0), P(cx + rw / 2, 0))
    clipped(rib) {
        blurred(rect(cx - rw / 2 + rw * 0.18, top, rw * 0.1, bot - top), WHITE.alpha(0.32), 16)
        linear(nil, [(0, SHADOW.alpha(0.45)), (0.12, SHADOW.alpha(0)), (0.78, SHADOW.alpha(0)), (1, redRamp.deep.alpha(0.45))], P(0, top), P(0, bot))
        blurred(ellipseR(P(cx - 40, 640), 60, 260, rot: 3), Col(0x7A1A2A, 0.18), 50)
    }
    innerShadow(rib, Col(0xFFBDB1, 0.6), blur: 10, dx: 5, dy: 0)
    innerShadow(rib, Col(0x5A0E1C, 0.4), blur: 20, dx: -6, dy: -10)
    // stitches
    var sl: [CGPoint] = [], sr: [CGPoint] = []
    y = top + 30
    let sb = bot - 40
    while y <= sb { sl.append(P(cx - rw / 2 + 28 + off(y), y)); sr.append(P(cx + rw / 2 - 28 + off(y), y)); y += 8 }
    let stitch = poly(sl + [P(cx + off(bot - notch), bot - notch - 34)] + sr.reversed(), closed: false)
    strokeP(stitch, Col(0xFFC2B6, 0.8), 6, cap: .round, dash: [18, 14])
    // yellow top cap
    extrude(capR, P(8, 16), yellowRamp.dark, yellowRamp.deep)
    glossy(capR, yellowRamp, Gloss(mid: 0.5, volume: 0.55, shade: 0.4, bounce: 0.3, rim: 0.65, spec: 0.9, specAt: P(0.26, 0.28),
                                   specSize: CGSize(width: 0.3, height: 0.16), specRot: -4))
    strokeP(linePath(P(cx - 150, 380), P(cx + 150, 380)), Col(0xD9822A, 0.4), 4)
}

func spriteNotebook() {
    newCanvas(1200, 1036, opaque: false)
    group {
        C.translateBy(x: 600, y: 492)
        C.rotate(by: rad(-4))
        let cover = rrect(-505, -330, 1010, 660, 48)
        blurred(moved(cover, 10, 30), SHADOW.alpha(0.35), 34, dx: 10, dy: 20)
        extrude(cover, P(6, 30), blueRamp.dark, blueRamp.deep, bounce: blueRamp.light.alpha(0.5))
        glossy(cover, blueRamp, Gloss(mid: 0.5, volume: 0.3, shade: 0.35, bounce: 0.3, rim: 0.6, spec: 0))
        // spine crease on cover
        linear(rect(-30, -330, 60, 660), [(0, SHADOW.alpha(0)), (0.5, SHADOW.alpha(0.3)), (1, SHADOW.alpha(0))], P(-30, 0), P(30, 0))
        // page block thickness
        let pages = rrect(-474, -306, 948, 616, 26)
        extrude(pages, P(3, 16), Col(0xE9D6B2), Col(0xC9AE82))
        for k in 1...3 {
            let yy = 310 + CGFloat(k) * 4
            strokeP(linePath(P(-450, yy), P(450, yy)), Col(0xFFF4DE, 0.8), 1.5)
        }
        func page(_ sx: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: P(0, -296))
            p.addQuadCurve(to: P(sx * 446, -310), control: P(sx * 200, -318))
            p.addQuadCurve(to: P(sx * 474, -282), control: P(sx * 474, -310))
            p.addLine(to: P(sx * 474, 282))
            p.addQuadCurve(to: P(sx * 446, 310), control: P(sx * 474, 310))
            p.addQuadCurve(to: P(0, 320), control: P(sx * 200, 316))
            p.closeSubpath()
            return p
        }
        let lp = page(-1), rp = page(1)
        linear(lp, [(0, Col(0xFFFDF6)), (0.8, PAPER), (1, Col(0xE3CFA8))], P(-474, 0), P(0, 0))
        linear(rp, [(0, Col(0xE0CBA2)), (0.14, Col(0xF7EDDA)), (1, Col(0xFFFBF2))], P(0, 0), P(474, 0))
        for pg in [lp, rp] { innerShadow(pg, Col(0x8A7250, 0.25), blur: 8, dx: 0, dy: -3) }
        clipped(lp) { blurred(poly([P(-470, -80), P(-300, -330), P(-230, -330), P(-470, 20)]), WHITE.alpha(0.4), 30) }
        strokeP(linePath(P(0, -296), P(0, 320)), Col(0xB89D70, 0.6), 3)
        // abstract lines — left page
        let lc = Col(0xA7B2CF, 0.9)
        bar(-410, -222, 190, 20, MIDNIGHT.alpha(0.6))
        let lens: [CGFloat] = [330, 290, 320, 250, 310, 200]
        for (i, l) in lens.enumerated() { bar(-410, -150 + CGFloat(i) * 62, l, 15, lc) }
        fill(rrect(-418, -150 + 2 * 62 - 17, 250, 34, 17), YELLOW.alpha(0.7))
        bar(-410, -150 + 2 * 62, 230, 15, Col(0x3A4F8E))
        // right page
        bar(90, -222, 160, 20, MIDNIGHT.alpha(0.6))
        for (i, l) in [CGFloat(300), 260, 320, 180].enumerated() { bar(90, -150 + CGFloat(i) * 62, l, 15, i == 1 ? RED.alpha(0.7) : lc) }
        fill(circle(96, 118, 12), RED.alpha(0.85))
        bar(124, 118, 190, 15, lc)
        // bookmark ribbon
        let rib = ribbonPath(P(46, -334), P(92, 420), bend: -26, w0: 62, w1: 62, notch: 24)
        blurred(rib, Col(0x3A0A14, 0.35), 10, dx: 8, dy: 10)
        glossy(rib, redRamp, Gloss(mid: 0.4, volume: 0.35, shade: 0.4, bounce: 0.2, rim: 0.5, spec: 0.5, specAt: P(0.35, 0.15),
                                   specSize: CGSize(width: 0.25, height: 0.2), specRot: 80))
        fill(rrect(40, -344, 74, 20, 10), redRamp.dark)
        // pencil
        drawPencil(from: P(120, 262), to: P(540, 86), w: 48, squash: 1, shadow: SHADOW.alpha(0.35))
    }
}

func spriteComparison() {
    newCanvas(1200, 1066, opaque: false)
    let baseTop: CGFloat = 700, d: CGFloat = 66, h: CGFloat = 104
    blurred(ellipse(605, baseTop + h + d + 6, 470, 40), SHADOW.alpha(0.3), 28)
    drawBlock(cx: 600, topY: baseTop, w: 960, d: d, h: h, ramp: blueRamp, shadow: nil)
    let slotY = baseTop - 4
    let cw: CGFloat = 360, chh: CGFloat = 560
    let cards: [(CGFloat, CGFloat, Ramp)] = [(374, -6, redRamp), (826, 6, yellowRamp)]
    for (x, rot, ramp) in cards {
        let slot = rrect2(x - 200, slotY - 13, 400, 26, 60, 13)
        fill(slot, Col(0x0A1640))
        innerShadow(slot, SHADOW.alpha(0.8), blur: 6, dx: 0, dy: 4)
        drawCard(P(x, slotY - chh / 2 + 44), w: cw, h: chh, rot: rot, t: 26, style: CardStyle(header: ramp),
                 shadow: nil, clipBelow: slotY)
        let lip = quadPath(P(x - 198, slotY + 8), P(x, slotY + 14), P(x + 198, slotY + 8))
        strokeP(lip, blueRamp.hi.alpha(0.7), 4)
    }
}

// MARK: - Output

struct Asset { let id: String; let name: String; let kind: Kind; let draw: () -> Void }
enum Kind { case onboarding, sprite }

let assets: [Asset] = [
    Asset(id: "cp01", name: "cp_onboarding_segments", kind: .onboarding, draw: sceneSegments),
    Asset(id: "cp02", name: "cp_onboarding_stage", kind: .onboarding, draw: sceneStage),
    Asset(id: "cp03", name: "cp_onboarding_review", kind: .onboarding, draw: sceneReview),
    Asset(id: "cp04", name: "cp_flick_director", kind: .sprite, draw: spriteFlick),
    Asset(id: "cp05", name: "cp_script_cards", kind: .sprite, draw: spriteCards),
    Asset(id: "cp06", name: "cp_spotlight", kind: .sprite, draw: spriteSpotlight),
    Asset(id: "cp07", name: "cp_stage_timer", kind: .sprite, draw: spriteTimer),
    Asset(id: "cp08", name: "cp_review_marker", kind: .sprite, draw: spriteBookmark),
    Asset(id: "cp09", name: "cp_rehearsal_notebook", kind: .sprite, draw: spriteNotebook),
    Asset(id: "cp10", name: "cp_comparison_cards", kind: .sprite, draw: spriteComparison),
]

func run(_ exe: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.standardError = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    do { try p.run() } catch { print("failed to run \(exe): \(error)"); return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

let fm = FileManager.default
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
try? fm.createDirectory(at: onboardingDir, withIntermediateDirectories: true)

let wanted = Set(CommandLine.arguments.dropFirst().map { $0.lowercased() })
for a in assets where wanted.isEmpty || wanted.contains(a.id) || wanted.contains(a.name) {
    let t0 = Date()
    a.draw()
    switch a.kind {
    case .onboarding:
        let png = outDir.appendingPathComponent("\(a.name).png")
        savePNG(png)
        let webp = onboardingDir.appendingPathComponent("\(a.name).webp")
        let st = run(cwebpPath, ["-q", "88", "-m", "6", "-sharp_yuv", "-mt", png.path, "-o", webp.path])
        print("\(a.id) \(a.name).webp  cwebp=\(st)  \(String(format: "%.1fs", Date().timeIntervalSince(t0)))")
    case .sprite:
        let set = assetsDir.appendingPathComponent("\(a.name).imageset")
        try? fm.createDirectory(at: set, withIntermediateDirectories: true)
        savePNG(set.appendingPathComponent("\(a.name).png"))
        let json = """
        {
          "images" : [
            {
              "filename" : "\(a.name).png",
              "idiom" : "universal",
              "scale" : "3x"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """
        try? json.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        // Preview: sprite over the app's dark and light surfaces (for review only).
        let sprite = C.makeImage()!
        let w = sprite.width, h = sprite.height
        newCanvas(w * 2, h, opaque: true)
        fill(rect(0, 0, CGFloat(w), CGFloat(h)), MIDNIGHT)
        fill(rect(CGFloat(w), 0, CGFloat(w), CGFloat(h)), PAPER)
        group {
            C.translateBy(x: 0, y: CGFloat(h)); C.scaleBy(x: 1, y: -1)
            C.draw(sprite, in: CGRect(x: 0, y: 0, width: w, height: h))
            C.draw(sprite, in: CGRect(x: w, y: 0, width: w, height: h))
        }
        savePNG(outDir.appendingPathComponent("preview_\(a.name).png"))
        print("\(a.id) \(a.name).png  \(String(format: "%.1fs", Date().timeIntervalSince(t0)))")
    }
}

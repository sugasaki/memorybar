// MemoryBar の OGP 画像(GitHub のソーシャルプレビュー)を生成する。
//
// 生成物ではなくこの生成コードを置いているのは make-icon.swift と同じ理由で、
// 文言や配置を後から直して作り直せるようにするため。
// 素材は docs/screenshots/ の実機キャプチャをそのまま合成する
// (作り物のモックを載せると、値の正確さという本題と食い違うため)。
//
//   swift scripts/ogp/make-ogp.swift [出力先.png]
//
// 既定の出力先は docs/ogp.png。
// GitHub のソーシャルプレビューは 1280x640 が推奨で、1MB を超えると弾かれる。
// リポジトリ設定 > General > Social preview から手で上げる(API は無い)。

import AppKit
import CoreGraphics
import Foundation

// MARK: - 配色(アイコン・構成比の帯と揃える)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let backgroundTop = rgb(52, 57, 69)
let backgroundBottom = rgb(24, 26, 33)
let titleColor = rgb(245, 247, 250)
let bodyColor = rgb(196, 202, 214)
let mutedColor = rgb(142, 150, 166)

/// アプリメモリ・確保済み・圧縮・その他・キャッシュ・未使用に対応する色
let segmentColors = [
    rgb(255, 214, 10), rgb(255, 159, 10), rgb(100, 210, 255),
    rgb(255, 105, 220), rgb(50, 110, 190), rgb(48, 209, 88),
]

// MARK: - 画布

/// GitHub のソーシャルプレビューの推奨サイズ
let canvas = CGSize(width: 1280, height: 640)
/// 2倍で描いてから縮小すると文字と縮小画像の縁が滑らかになる
let scale: CGFloat = 2

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ogp
    .deletingLastPathComponent()  // scripts
    .deletingLastPathComponent()  // リポジトリ直下
let shots = repoRoot.appendingPathComponent("docs/screenshots")
let outputURL =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repoRoot.appendingPathComponent("docs/ogp.png")

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// 上端を原点にした座標で書けるようにする(CoreGraphics は左下原点)
func flip(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX, y: canvas.height - rect.maxY, width: rect.width, height: rect.height)
}

/// 縦横比を保ったまま、指定した高さに合わせた矩形を作る
func fitted(_ image: CGImage, height: CGFloat, right: CGFloat, centerY: CGFloat) -> CGRect {
    let width = height * CGFloat(image.width) / CGFloat(image.height)
    return CGRect(x: right - width, y: centerY - height / 2, width: width, height: height)
}

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded),
        let rounded = NSFont(descriptor: descriptor, size: size)
    else { return base }
    return rounded
}

func draw(
    _ text: String, font: NSFont, color: CGColor, at point: CGPoint, tracking: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .kern: tracking,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    // point は文字の上端。NSAttributedString は左下から描くため高さ分下げる
    let size = string.size()
    string.draw(at: CGPoint(x: point.x, y: canvas.height - point.y - size.height))
}

// MARK: - 描画

guard
    let context = CGContext(
        data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("描画コンテキストを作れませんでした") }

context.scaleBy(x: scale, y: scale)
context.setShouldAntialias(true)
context.interpolationQuality = .high

// 背景。アイコンの板と同じ上明るく下暗いグラデーション
let colorSpace = CGColorSpaceCreateDeviceRGB()
if let gradient = CGGradient(
    colorsSpace: colorSpace, colors: [backgroundTop, backgroundBottom] as CFArray,
    locations: [0, 1])
{
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: 0, y: 0), options: [])
}

// 上端の細い帯。アプリの構成比の帯を意匠として引く
let stripeHeight: CGFloat = 6
let stripeWidths: [CGFloat] = [0.20, 0.26, 0.24, 0.04, 0.16, 0.10]
var stripeX: CGFloat = 0
for (index, fraction) in stripeWidths.enumerated() {
    let width = canvas.width * fraction
    context.setFillColor(segmentColors[index])
    context.fill(flip(CGRect(x: stripeX, y: 0, width: width, height: stripeHeight)))
    stripeX += width
}

// テキストの描画は AppKit 側の座標系に載せる
let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsContext

let left: CGFloat = 76

// アイコン
if let icon = loadImage(repoRoot.appendingPathComponent("docs/icon.png")) {
    context.draw(icon, in: flip(CGRect(x: left, y: 92, width: 96, height: 96)))
}

draw("MemoryBar", font: roundedFont(size: 62, weight: .bold), color: titleColor,
    at: CGPoint(x: left, y: 218), tracking: -0.5)

draw("Real-time memory in your macOS menu bar",
    font: NSFont.systemFont(ofSize: 26, weight: .medium), color: bodyColor,
    at: CGPoint(x: left, y: 310))

draw("Same formula as Activity Monitor",
    font: NSFont.systemFont(ofSize: 26, weight: .medium), color: bodyColor,
    at: CGPoint(x: left, y: 348))

draw("Swift + SwiftUI  ·  no dependencies  ·  macOS 14+",
    font: NSFont.systemFont(ofSize: 20, weight: .regular), color: mutedColor,
    at: CGPoint(x: left, y: 410))

// メニューバーの実機キャプチャ。左下に敷いて「常駐する場所」を示す
if let menubar = loadImage(shots.appendingPathComponent("menubar.png")) {
    let width: CGFloat = 452
    let height = width * CGFloat(menubar.height) / CGFloat(menubar.width)
    let rect = CGRect(x: left, y: 488, width: width, height: height)
    // 実物のメニューバーは黒く、背景に沈むため薄い縁を回す
    let border = CGPath(
        roundedRect: flip(rect.insetBy(dx: -1, dy: -1)), cornerWidth: 7, cornerHeight: 7,
        transform: nil)
    context.setFillColor(rgb(255, 255, 255, 0.10))
    context.addPath(border)
    context.fillPath()
    context.saveGState()
    context.addPath(
        CGPath(roundedRect: flip(rect), cornerWidth: 6, cornerHeight: 6, transform: nil))
    context.clip()
    context.draw(menubar, in: flip(rect))
    context.restoreGState()
}

// パネルの実機キャプチャ。影を含んだまま合成する
if let panel = loadImage(shots.appendingPathComponent("floating.png")) {
    let rect = fitted(panel, height: 500, right: canvas.width - 44, centerY: canvas.height / 2 + 10)
    context.draw(panel, in: flip(rect))
}

NSGraphicsContext.restoreGraphicsState()

// MARK: - 書き出し

guard let rendered = context.makeImage() else { fatalError("画像を作れませんでした") }

// 2倍で描いたものを等倍へ落とす。GitHub の推奨は 1280x640 で、
// そのまま 2倍で出すと 1MB の上限に当たりやすい
guard
    let output = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("縮小用のコンテキストを作れませんでした") }
output.interpolationQuality = .high
output.draw(rendered, in: CGRect(origin: .zero, size: canvas))
guard let image = output.makeImage() else { fatalError("縮小に失敗しました") }

try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("出力先を開けませんでした") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("書き出しに失敗しました") }

let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
let bytes = (attributes?[.size] as? Int) ?? 0
print("\(outputURL.path) \(image.width)x\(image.height) \(bytes / 1024)KB")
if bytes > 1_000_000 {
    print("警告: 1MB を超えています。GitHub のソーシャルプレビューは受け付けません")
}

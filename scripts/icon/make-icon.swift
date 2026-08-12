// MemoryBar のアプリアイコンを生成する。
//
// 生成物(.icns)ではなく、この生成コードをリポジトリに置いている。
// 後から色や形を調整して作り直せるようにするため。
//
//   swift scripts/icon/make-icon.swift <出力ディレクトリ>
//
// 出力先に AppIcon.iconset を作るので、iconutil で .icns へ変換する。
// 通常は scripts/make-app.sh から呼ばれる。

import AppKit
import CoreGraphics
import Foundation

// MARK: - 配色(アプリの構成比の帯と揃える)

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let backgroundTop = rgb(52, 57, 69)
let backgroundBottom = rgb(24, 26, 33)
let chipFill = rgb(242, 245, 250)
let pinColor = rgb(150, 160, 178)

/// アプリメモリ・確保済み・圧縮・その他・キャッシュ・未使用に対応する色
let segmentColors = [
    rgb(255, 214, 10), rgb(255, 159, 10), rgb(100, 210, 255),
    rgb(255, 105, 220), rgb(50, 110, 190), rgb(48, 209, 88),
]

// MARK: - 描画

/// 小さいサイズでは要素を減らす。16px で帯を3段描いても潰れて判別できないため
func barRowCount(for size: CGFloat) -> Int {
    switch size {
    case ..<40: return 1
    case ..<128: return 2
    default: return 3
    }
}

func drawIcon(size: CGFloat) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setShouldAntialias(true)

    let unit = size / 512  // 512pt を基準に設計している

    // 背景の角丸板。macOS のアイコンは周囲に余白を取る
    let inset = 40 * unit
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let platePath = CGPath(
        roundedRect: plate, cornerWidth: plate.width * 0.225, cornerHeight: plate.height * 0.225,
        transform: nil)
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: cs, colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // チップ本体。16px ではピンが1ドット未満に潰れるため、
    // 描かずにチップを大きく取り、帯を確実に読ませる
    let isTiny = size < 40
    let chip =
        isTiny
        ? CGRect(x: 116 * unit, y: 122 * unit, width: 280 * unit, height: 268 * unit)
        : CGRect(x: 150 * unit, y: 156 * unit, width: 212 * unit, height: 200 * unit)

    if !isTiny {
        let pinLength = 32 * unit
        let pinThickness = max(1, 13 * unit)
        ctx.setFillColor(pinColor)
        let pinCount = 5
        let pinSpacing = (chip.height - pinThickness * CGFloat(pinCount)) / CGFloat(pinCount + 1)
        for i in 0..<pinCount {
            let y = chip.minY + pinSpacing * CGFloat(i + 1) + pinThickness * CGFloat(i)
            ctx.fill(CGRect(x: chip.minX - pinLength, y: y, width: pinLength, height: pinThickness))
            ctx.fill(CGRect(x: chip.maxX, y: y, width: pinLength, height: pinThickness))
        }
    }

    ctx.setFillColor(chipFill)
    ctx.addPath(
        CGPath(
            roundedRect: chip, cornerWidth: 26 * unit, cornerHeight: 26 * unit, transform: nil))
    ctx.fillPath()

    // 中の帯。構成比を表す
    let rows = barRowCount(for: size)
    let padding = (isTiny ? 34 : 24) * unit
    let barWidth = chip.width - padding * 2
    let barHeight = (isTiny ? 56 : 26) * unit
    let rowGap = 20 * unit
    let totalHeight = barHeight * CGFloat(rows) + rowGap * CGFloat(rows - 1)
    var y = chip.midY + totalHeight / 2 - barHeight

    // 段ごとに使用量が減る様子を表す
    // 16px では区画を3つに絞る。6色を並べても混ざって濁るだけ
    let tinyFractions: [CGFloat] = [0.42, 0.30, 0.28, 0, 0, 0]
    let fractionRows: [[CGFloat]] = [
        isTiny ? tinyFractions : [0.32, 0.24, 0.20, 0.05, 0.13, 0.06],
        [0.26, 0.20, 0.17, 0.05, 0.11, 0.21],
        [0.18, 0.14, 0.12, 0.04, 0.08, 0.44],
    ]
    let cornerRadius = min(barHeight / 2, 9 * unit)

    for row in 0..<rows {
        let fractions = fractionRows[row]
        var x = chip.minX + padding
        for (index, fraction) in fractions.enumerated() {
            let width = barWidth * fraction
            // 最後の区画は「未使用」。小さすぎる区画は描かない(潰れて濁るため)
            if width >= 1 {
                ctx.setFillColor(segmentColors[index])
                ctx.addPath(
                    CGPath(
                        roundedRect: CGRect(x: x, y: y, width: max(width - unit, 1), height: barHeight),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
                ctx.fillPath()
            }
            x += width
        }
        y -= barHeight + rowGap
    }

    return ctx.makeImage()
}

// MARK: - 出力

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(outputDirectory)/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: iconset, withIntermediateDirectories: true)

/// macOS が要求する名前とピクセル数の対応
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let image = drawIcon(size: variant.pixels) else {
        FileHandle.standardError.write(Data("描画に失敗: \(variant.name)\n".utf8))
        exit(1)
    }
    write(image, to: "\(iconset)/\(variant.name).png")
}
print("生成しました: \(iconset)")

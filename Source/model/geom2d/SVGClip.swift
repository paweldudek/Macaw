import QuartzCore

/// Each child of an SVG clipPath contributes its filled silhouette independently.
final class SVGClip: Locus {
    struct Part {
        let form: Locus
        let place: Transform
        let rule: CGPathFillRule
        let path: CGPath

        init(_ form: Locus, place: Transform, rule: CGPathFillRule) {
            self.form = form
            self.place = place
            self.rule = rule
            self.path = (place == .identity ? form : TransformedLocus(locus: form, transform: place)).toCGPath()
        }

        var placedForm: Locus {
            return place == .identity ? form : TransformedLocus(locus: form, transform: place)
        }
    }

    let parts: [Part]
    private let vectorUnion: CGPath?

    init(_ parts: [Part]) {
        self.parts = parts
        if #available(macOS 13, iOS 16, *) {
            vectorUnion = parts.map { $0.path.normalized(using: $0.rule) }
                .reduce(nil as CGPath?) { result, path in result?.union(path) ?? path }
        } else {
            vectorUnion = nil
        }
    }

    override func toPath() -> Path {
        return geometryPath.toMacaw()
    }

    var geometryPath: CGPath {
        if let vectorUnion = vectorUnion { return vectorUnion }
        // Older Core Graphics can expose the original contours through the public conversion API.
        // Drawing and masks still use the independently filled parts on those systems.
        let contours = CGMutablePath()
        parts.forEach { contours.addPath($0.path) }
        return contours
    }

    override func bounds() -> Rect {
        let rect = parts.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
        return rect.isNull ? Rect() : rect.toMacaw()
    }

    func applying(_ transform: Transform) -> SVGClip {
        return SVGClip(parts.map { Part($0.form, place: transform.concat(with: $0.place), rule: $0.rule) })
    }

    func contains(_ point: CGPoint) -> Bool {
        return parts.contains { $0.path.contains(point, using: $0.rule) }
    }

    func apply(in context: CGContext) {
        if parts.count == 1 {
            context.beginPath()
            context.addPath(parts[0].path)
            context.clip(using: parts[0].rule)
        } else if let vectorUnion = vectorUnion {
            context.beginPath()
            context.addPath(vectorUnion)
            context.clip()
        } else {
            applyCoverageMask(in: context)
        }
    }

    /// Portable Core Graphics fallback for bitmap and PDF destinations without vector path unions.
    func applyCoverageMask(in context: CGContext) {
        let rect = bounds().toCG().intersection(context.boundingBoxOfClipPath)
        guard !rect.isEmpty, rect.width.isFinite, rect.height.isFinite else {
            context.clip(to: .zero)
            return
        }
        let ctm = context.ctm
        // Rasterize only the visible mask, at device density, with a 16 MiB allocation ceiling.
        let width = min(4096, ceil(rect.width * hypot(ctm.a, ctm.b)))
        let height = min(4096, ceil(rect.height * hypot(ctm.c, ctm.d)))
        guard width >= 1, height >= 1,
              let coverage = CGContext(data: nil, width: Int(width), height: Int(height),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                       bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            context.clip(to: .zero)
            return
        }
        coverage.scaleBy(x: width / rect.width, y: height / rect.height)
        coverage.translateBy(x: -rect.minX, y: -rect.minY)
        coverage.setFillColor(gray: 0, alpha: 1)
        coverage.fill(rect)
        coverage.setFillColor(gray: 1, alpha: 1)
        for part in parts {
            coverage.addPath(part.path)
            coverage.drawPath(using: part.rule == .evenOdd ? .eoFill : .fill)
        }
        if let mask = coverage.makeImage() { context.clip(to: rect, mask: mask) }
        else { context.clip(to: .zero) }
    }

    func animationMask() -> CALayer {
        let mask = CALayer()
        for part in parts {
            let child = CAShapeLayer()
            child.path = part.path
            child.fillRule = part.rule == .evenOdd ? .evenOdd : .nonZero
            mask.addSublayer(child)
        }
        return mask
    }
}

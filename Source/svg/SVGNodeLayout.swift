enum SVGLength {
    case percent(Double)
    case pixels(Double)

    init(percent: Double) {
        self = .percent(percent)
    }

    init(pixels: Double) {
        self = .pixels(pixels)
    }

    func toPixels(total: Double) -> Double {
        switch self {
        case let .percent(percent):
            return total * percent / 100.0
        case let .pixels(pixels):
            return pixels
        }
    }

}

class SVGSize {

    let width: SVGLength
    let height: SVGLength

    public init(width: SVGLength, height: SVGLength) {
        self.width = width
        self.height = height
    }

    func toPixels(total: Size) -> Size {
        return Size(w: width.toPixels(total: total.w),
                    h: height.toPixels(total: total.h))
    }

}

protocol NodeLayout {

    var intrinsicSize: Size? { get }
    var hasValidDimensions: Bool { get }

    func computeSize(parent: Size) -> Size

    func layout(node: Node, in size: Size)
}

class SVGNodeLayout: NodeLayout {

    let svgSize: SVGSize
    let viewBox: Rect?
    let scaling: AspectRatio
    let xAlign: Align
    let yAlign: Align

    init(svgSize: SVGSize, viewBox: Rect? = .none, scaling: AspectRatio? = nil, xAlign: Align? = nil, yAlign: Align? = nil) {
        self.svgSize = svgSize
        self.viewBox = viewBox
        self.scaling = scaling ?? .meet
        self.xAlign = xAlign ?? .mid
        self.yAlign = yAlign ?? .mid
    }

    var intrinsicSize: Size? {
        guard hasValidDimensions else { return nil }
        let viewBoxSize = validSize(viewBox?.size())

        switch (svgSize.width, svgSize.height) {
        case let (.pixels(width), .pixels(height)):
            return validSize(Size(w: width, h: height))
        case let (.pixels(width), _):
            guard width.isFinite, width > 0 else { return nil }
            guard let viewBoxSize = viewBoxSize else { return nil }
            return validSize(Size(
                w: width,
                h: width * viewBoxSize.h / viewBoxSize.w
            ))
        case let (_, .pixels(height)):
            guard height.isFinite, height > 0 else { return nil }
            guard let viewBoxSize = viewBoxSize else { return nil }
            return validSize(Size(
                w: height * viewBoxSize.w / viewBoxSize.h,
                h: height
            ))
        default:
            return viewBoxSize
        }
    }

    var hasValidDimensions: Bool {
        return isValidDimension(svgSize.width) && isValidDimension(svgSize.height)
    }

    func computeSize(parent: Size) -> Size {
        return svgSize.toPixels(total: parent)
    }

    func layout(node: Node, in size: Size) {
        let svgSizeInPixels = svgSize.toPixels(total: size)

        let viewBox = self.viewBox ?? Rect(x: 0, y: 0, w: svgSizeInPixels.w, h: svgSizeInPixels.h)
        let clipsToViewport = self.viewBox != nil || scaling === AspectRatio.slice
        if clipsToViewport && (validSize(viewBox.size()) == nil || validSize(svgSizeInPixels) == nil ||
                               !viewBox.x.isFinite || !viewBox.y.isFinite) {
            node.place = .identity
            if node.clip as? Rect != Rect() { node.clip = Rect() }
            return
        }
        let layout = ContentLayout.of(scaling: scaling, xAlign: xAlign, yAlign: yAlign)
        node.place = layout.layout(size: viewBox.size(), into: svgSizeInPixels)
            .move(dx: -viewBox.x, dy: -viewBox.y)

        // The viewBox maps coordinates; the viewport defines the clipping boundary. With
        // aspect-fit, content outside the viewBox can still be inside the viewport margins.
        if clipsToViewport {
            let clip = node.place.invert().map { svgSizeInPixels.rect().applying($0) } ?? Rect()
            if node.clip as? Rect != clip { node.clip = clip }
        }
    }

    private func validSize(_ size: Size?) -> Size? {
        guard let size = size,
              size.w.isFinite,
              size.h.isFinite,
              size.w > 0,
              size.h > 0 else {
            return nil
        }
        return size
    }

    private func isValidDimension(_ length: SVGLength) -> Bool {
        let value: Double
        switch length {
        case let .percent(percent):
            value = percent
        case let .pixels(pixels):
            value = pixels
        }
        return value.isFinite && value > 0
    }
}

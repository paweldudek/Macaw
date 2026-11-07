import XCTest
#if os(macOS)
import AppKit
@testable import Macaw

final class SVGClippingTests: XCTestCase {
    func testGroupClipClipsPaintedPixels() throws {
        let image = try render("""
        <defs><clipPath id="clip"><rect x="30" y="20" width="40" height="60"/></clipPath></defs>
        <g clip-path="url(#clip)"><rect width="100" height="100" fill="blue"/></g>
        """)
        try assertTransparent(image, at: [(10, 50), (90, 50), (50, 10), (50, 90)])
        try assertOpaque(image, at: [(50, 50)])
    }

    func testCircularClipPreservesOnlyItsInterior() throws {
        let image = try render("""
        <defs><clipPath id="clip"><circle cx="50" cy="50" r="25"/></clipPath></defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#clip)"/>
        """)
        try assertTransparent(image, at: [(20, 50), (80, 50), (30, 30)])
        try assertOpaque(image, at: [(50, 50), (40, 40)])
    }

    func testTransformedClipUsesItsAuthoredCoordinates() throws {
        let image = try render("""
        <defs><clipPath id="clip"><rect width="20" height="60" transform="translate(40 20)"/></clipPath></defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#clip)"/>
        """)
        try assertTransparent(image, at: [(10, 50), (70, 50)])
        try assertOpaque(image, at: [(50, 50)])
    }

    func testClipMovesWithTransformedShape() throws {
        let image = try render("""
        <defs><clipPath id="clip"><rect x="10" y="20" width="20" height="60"/></clipPath></defs>
        <rect width="100" height="100" fill="blue" transform="translate(30 0)" clip-path="url(#clip)"/>
        """)
        try assertTransparent(image, at: [(20, 50), (35, 50), (80, 50)])
        try assertOpaque(image, at: [(50, 50)])
    }

    func testNestedClipsIntersectWithoutLeakingIntoFollowingSibling() throws {
        let inner = Shape(form: Rect(x: 0, y: 0, w: 100, h: 100), fill: Color.blue,
                          clip: Rect(x: 40, y: 0, w: 60, h: 100))
        let clipped = Group(contents: [inner], clip: Rect(x: 20, y: 20, w: 40, h: 60))
        let sibling = Shape(form: Rect(x: 80, y: 40, w: 10, h: 20), fill: Color.red)
        let image = try bitmap(Group(contents: [clipped, sibling]), layout: .none)
        try assertTransparent(image, at: [(30, 50), (70, 50), (50, 10)])
        try assertOpaque(image, at: [(50, 50), (85, 50)])
    }

    func testPathClipKeepsItsWindingHole() throws {
        let image = try render("""
        <defs><clipPath id="clip"><path d="M10 10H90V90H10Z M35 35V65H65V35Z"/></clipPath></defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#clip)"/>
        """)
        try assertTransparent(image, at: [(50, 50), (5, 50)])
        try assertOpaque(image, at: [(20, 50), (80, 50)])
    }

    func testGroupClipRemainsInGroupCoordinatesWhenChildIsTranslated() throws {
        let image = try render("""
        <defs><clipPath id="clip"><rect x="20" y="20" width="60" height="60"/></clipPath></defs>
        <g clip-path="url(#clip)"><rect width="100" height="100" fill="blue" transform="translate(50 0)"/></g>
        """)
        try assertTransparent(image, at: [(40, 50), (90, 50)])
        try assertOpaque(image, at: [(60, 50)])
    }

    func testParsedNestedGroupClipsIntersect() throws {
        let image = try render("""
        <defs>
          <clipPath id="outer"><rect x="20" y="20" width="60" height="60"/></clipPath>
          <clipPath id="inner"><rect x="40" y="0" width="60" height="100"/></clipPath>
        </defs>
        <g clip-path="url(#outer)"><g clip-path="url(#inner)">
          <rect width="100" height="100" fill="blue"/>
        </g></g>
        """)
        try assertTransparent(image, at: [(30, 50), (90, 50), (50, 10)])
        try assertOpaque(image, at: [(50, 50)])
    }

    func testGroupBoundingBoxClipUsesWholeGroupBounds() throws {
        let image = try render("""
        <defs><clipPath id="clip" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath></defs>
        <g clip-path="url(#clip)">
          <rect x="20" y="20" width="20" height="60" fill="blue"/>
          <rect x="60" y="20" width="20" height="60" fill="blue"/>
        </g>
        """)
        try assertOpaque(image, at: [(25, 50), (35, 50)])
        try assertTransparent(image, at: [(65, 50), (75, 50)])
    }

    func testBoundingBoxClipUsesGeometryBeforeDescendantClipping() throws {
        let image = try render("""
        <defs>
          <clipPath id="half" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
          <clipPath id="inner"><rect width="50" height="100"/></clipPath>
        </defs>
        <g clip-path="url(#half)"><g clip-path="url(#inner)">
          <rect width="100" height="100" fill="blue"/>
        </g></g>
        """)
        try assertOpaque(image, at: [(10, 50), (40, 50)])
        try assertTransparent(image, at: [(60, 50), (90, 50)])
    }

    func testBoundingBoxClipPreservesNestedTransformsBeforeClipping() throws {
        let image = try render("""
        <defs>
          <clipPath id="half" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
          <clipPath id="inner"><rect width="50" height="100"/></clipPath>
        </defs>
        <g transform="translate(10 0) scale(0.8)" clip-path="url(#half)">
          <g transform="translate(10 0)"><g clip-path="url(#inner)">
            <rect width="100" height="100" fill="blue"/>
          </g></g>
        </g>
        """)
        try assertOpaque(image, at: [(25, 50), (50, 50)])
        try assertTransparent(image, at: [(10, 50), (65, 50)])
    }

    func testBoundingBoxClipExcludesStrokeFromGeometry() throws {
        let image = try render("""
        <defs><clipPath id="quarter" clipPathUnits="objectBoundingBox"><rect width="0.25" height="1"/></clipPath></defs>
        <g clip-path="url(#quarter)"><rect x="10" y="10" width="80" height="80" fill="blue" stroke="blue" stroke-width="20"/></g>
        """)
        try assertOpaque(image, at: [(15, 50), (28, 50)])
        try assertTransparent(image, at: [(5, 50), (35, 50)])
    }

    func testCompoundClipPreservesChildTranslations() throws {
        let image = try render("""
        <defs><clipPath id="all">
          <rect width="50" height="100"/>
          <rect width="50" height="100" transform="translate(50 0)"/>
        </clipPath></defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#all)"/>
        """)
        try assertOpaque(image, at: [(10, 50), (40, 50), (60, 50), (90, 50)])
    }

    func testCompoundClipPreservesChildRotationAndCurves() throws {
        let image = try render("""
        <defs><clipPath id="parts">
          <rect width="20" height="50" transform="translate(80 10) rotate(90)"/>
          <circle r="15" transform="translate(75 65)"/>
        </clipPath></defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#parts)"/>
        """)
        try assertOpaque(image, at: [(50, 20), (75, 65)])
        try assertTransparent(image, at: [(10, 20), (50, 65), (90, 90)])
    }

    func testCompoundClipKeepsReflectedOverlapFilledForEitherChildOrder() throws {
        for shapes in [
            "<rect width=\"60\" height=\"100\"/><rect width=\"60\" height=\"100\" transform=\"translate(100 0) scale(-1 1)\"/>",
            "<rect width=\"60\" height=\"100\" transform=\"translate(100 0) scale(-1 1)\"/><rect width=\"60\" height=\"100\"/>"
        ] {
            let image = try render("""
            <defs><clipPath id="all">\(shapes)</clipPath></defs>
            <rect width="100" height="100" fill="blue" clip-path="url(#all)"/>
            """)
            try assertOpaque(image, at: [(10, 50), (50, 50), (90, 50)])
        }
    }

    func testCompoundClipPreservesReflectedChildWindingHole() throws {
        let image = try render("""
        <defs><clipPath id="parts">
          <rect width="10" height="100"/>
          <path d="M10 10H60V90H10Z M20 30V70H40V30Z" transform="translate(100 0) scale(-1 1)"/>
        </clipPath></defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#parts)"/>
        """)
        try assertOpaque(image, at: [(5, 50), (50, 50), (85, 50)])
        try assertTransparent(image, at: [(20, 50), (70, 50)])
    }

    func testCompoundClipUnionsIndependentlyWoundChildrenInEitherOrder() throws {
        let left = #"<path d="M10 15H60V85H10Z"/>"#
        let right = #"<path d="M40 15V85H90V15Z"/>"#
        for children in [left + right, right + left] {
            let image = try render("""
            <defs><clipPath id="c">\(children)</clipPath></defs>
            <rect width="100" height="100" fill="blue" clip-path="url(#c)"/>
            """)
            try assertOpaque(image, at: [(15, 50), (50, 50), (85, 50)])
            try assertTransparent(image, at: [(5, 50), (50, 5)])
        }
    }

    func testClipRuleControlsEachSilhouetteBeforeUnion() throws {
        let rings = "M10 10H90V90H10Z M30 30H70V70H30Z"
        for (parent, child) in [("", #"clip-rule="evenodd""#), (#"clip-rule="evenodd""#, "")] {
            for extra in ["", #"<rect x="46" y="46" width="8" height="8"/>"#] {
                let image = try render("""
                <defs><clipPath id="c" \(parent)><path \(child) d="\(rings)"/>\(extra)</clipPath></defs>
                <rect width="100" height="100" fill="blue" clip-path="url(#c)"/>
                """)
                try assertOpaque(image, at: [(15, 50), (85, 50)])
                try assertTransparent(image, at: [(40, 50)])
                if extra.isEmpty { try assertTransparent(image, at: [(50, 50)]) }
                else { try assertOpaque(image, at: [(50, 50)]) }
            }
        }
    }

    func testTextDefinesASilhouetteAloneAndBesideAShape() throws {
        let glyph = #"<text x="42" y="70" font-size="70" font-family="Helvetica">H</text>"#
        for extra in ["", #"<rect x="10" width="15" height="100"/>"#] {
            let image = try render("""
            <defs><clipPath id="c">\(extra)\(glyph)</clipPath></defs>
            <rect width="100" height="100" fill="blue" clip-path="url(#c)"/>
            """)
            try assertOpaque(image, at: [(50, 50), (85, 50)])
            try assertTransparent(image, at: [(3, 50), (65, 60)])
            if extra.isEmpty { try assertTransparent(image, at: [(15, 50)]) }
            else { try assertOpaque(image, at: [(15, 50)]) }
        }
    }

    func testReferencedClipGeometryKeepsItsOwnRuleAndTransform() throws {
        let image = try render("""
        <defs xmlns:xlink="http://www.w3.org/1999/xlink">
          <path id="p" clip-rule="evenodd" d="M0 10H80V90H0Z M20 30H60V70H20Z"/>
          <clipPath id="c"><use xlink:href="#p" x="10"/><rect width="5" height="5"/></clipPath>
        </defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#c)"/>
        """)
        try assertOpaque(image, at: [(15, 50), (85, 50)])
        try assertTransparent(image, at: [(5, 50), (50, 50)])
    }

    func testForwardReferencedClipUsesTheWinningClipRuleDeclaration() throws {
        let image = try render("""
        <defs>
          <clipPath id="c"><use href="#p"/></clipPath>
          <path id="p" clip-rule="nonzero" style="clip-rule:evenodd" d="M10 10H90V90H10Z M30 30H70V70H30Z"/>
        </defs>
        <rect width="100" height="100" fill="blue" clip-path="url(#c)"/>
        """)
        try assertOpaque(image, at: [(15, 50), (85, 50)])
        try assertTransparent(image, at: [(50, 50)])
    }

    func testCompoundBoundsAndChildTransformSurviveSVGSerialization() throws {
        let node = try parse("""
        <defs><clipPath id="c" clipPathUnits="objectBoundingBox">
          <rect width="0.2" height="1" transform="translate(0.2 0)"/>
          <rect x="0.8" width="0.2" height="1"/>
        </clipPath></defs>
        <rect x="10" y="20" width="80" height="60" clip-path="url(#c)" fill="blue"/>
        """)
        for candidate in [node, try SVGParser.parse(text: SVGSerializer.serialize(node: node))] {
            let image = try bitmap(candidate, layout: .none)
            try assertOpaque(image, at: [(34, 50), (82, 50)])
            try assertTransparent(image, at: [(15, 50), (55, 50), (96, 50)])
        }
    }

    func testCompoundClipPreservesFollowingSiblingAndPaintsOverlapOnlyOnce() throws {
        let image = try render("""
        <defs><clipPath id="c"><circle cx="38" cy="50" r="24"/><circle cx="62" cy="50" r="24"/></clipPath></defs>
        <rect width="100" height="100" fill="blue" fill-opacity="0.5" clip-path="url(#c)"/>
        <rect x="90" y="40" width="8" height="20" fill="red"/>
        """)
        for x in [20, 50, 80] {
            XCTAssertEqual(try XCTUnwrap(image.colorAt(x: x, y: 50)).alphaComponent, 0.5, accuracy: 0.02)
        }
        try assertTransparent(image, at: [(6, 50), (50, 10)])
        try assertOpaque(image, at: [(94, 50)])
    }

    func testCompoundClipSurvivesPDFRoundTrip() throws {
        let node = try parse("""
        <defs><clipPath id="c">
          <rect x="5" y="10" width="30" height="60"/>
          <rect x="25" y="10" width="30" height="60"/>
          <rect x="80" y="10" width="10" height="60"/>
        </clipPath></defs>
        <rect width="100" height="100" fill="red"/>
        <rect width="100" height="100" fill="blue" opacity="0.5" clip-path="url(#c)"/>
        """)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        let renderer = RenderUtils.createNodeRenderer(node, view: nil)
        defer { renderer.dispose() }
        pdf.beginPDFPage(nil)
        renderer.render(in: pdf, force: true, opacity: 1)
        pdf.endPDFPage()
        pdf.closePDF()
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.drawPDFPage(try XCTUnwrap(document.page(at: 1)))
        let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        for x in [10, 30, 45, 65, 85, 95] {
            let offset = 50 * bitmap.bytesPerRow + x * 4
            if [65, 95].contains(x) {
                XCTAssertGreaterThan(pixels[offset], 245)
                XCTAssertLessThan(pixels[offset + 2], 10)
            } else {
                XCTAssertEqual(Int(pixels[offset]), 128, accuracy: 8)
                XCTAssertEqual(Int(pixels[offset + 2]), 128, accuracy: 8)
            }
        }
    }

    func testCompoundClipPreservesShapeGeometryForLayout() throws {
        let node = try parse("""
        <defs><clipPath id="c"><rect width="20" height="20"/><circle cx="70" cy="50" r="15"/></clipPath></defs>
        <rect id="subject" x="5" y="10" width="80" height="60" clip-path="url(#c)"/>
        """)
        let shape = try XCTUnwrap(node.nodeBy(predicate: { $0.tag.contains("subject") }) as? Shape)
        let bounds = try XCTUnwrap(shape.bounds)
        XCTAssertEqual(bounds.x, 5)
        XCTAssertEqual(bounds.y, 10)
        XCTAssertEqual(bounds.w, 80)
        XCTAssertEqual(bounds.h, 60)
    }

    func testCoverageMaskUsesIndependentSilhouettesInUserCoordinates() throws {
        let clip = SVGClip([
            .init(Rect(x: 5, y: 10, w: 25, h: 30), place: .identity, rule: .winding),
            .init(Rect(x: 20, y: 10, w: 25, h: 30), place: .identity, rule: .winding),
            .init(Rect(x: 70, y: 60, w: 15, h: 20), place: .identity, rule: .winding)
        ])
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
            bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.scaleBy(x: 2, y: 2)
        clip.applyCoverageMask(in: bitmap)
        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        for (x,y,alpha) in [(10,20,255),(25,20,255),(40,20,255),(55,20,0),(75,70,255),(75,20,0)] {
            XCTAssertEqual(Int(pixels[(199-y*2)*bitmap.bytesPerRow+x*2*4+3]), alpha)
        }
        if #available(macOS 13, *) {
            XCTAssertTrue(clip.toCGPath().contains(CGPoint(x: 25, y: 20)))
            XCTAssertFalse(clip.toPath().toCGPath().contains(CGPoint(x: 55, y: 20)))
        }
    }

    func testBoundingBoxClipAccumulatesNestedRotationsBeforeMeasuringGeometry() throws {
        let image = try render("""
        <defs>
          <clipPath id="half" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
          <clipPath id="inner"><rect width="50" height="100"/></clipPath>
        </defs>
        <g clip-path="url(#half)"><g transform="rotate(45 50 50)">
          <g transform="rotate(-45 50 50)" clip-path="url(#inner)">
            <rect width="100" height="100" fill="blue"/>
          </g>
        </g></g>
        """)
        try assertOpaque(image, at: [(10, 50), (40, 50)])
        try assertTransparent(image, at: [(60, 50), (90, 50)])
    }

    func testUnclippedShapeRemainsUnclipped() throws {
        let image = try render("<rect width=\"100\" height=\"100\" fill=\"blue\"/>")
        try assertOpaque(image, at: [(10, 10), (90, 90), (50, 50)])
    }

    func testSVGViewPreservesClipWhenDrawingIntoBitmap() throws {
        let node = try parse("""
        <defs><clipPath id="clip"><rect x="30" y="20" width="40" height="60"/></clipPath></defs>
        <g clip-path="url(#clip)"><rect width="100" height="100" fill="blue"/></g>
        """)
        let view = SVGView(node: node, frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.backgroundColor = .clear
        view.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        // Cached view bitmaps follow the display's backing scale.
        let scale = image.pixelsWide / 100
        try assertTransparent(image, at: [(10 * scale, 50 * scale), (90 * scale, 50 * scale)])
        try assertOpaque(image, at: [(50 * scale, 50 * scale)])
    }

    private func parse(_ body: String) throws -> Node {
        try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">\(body)</svg>
        """)
    }

    private func render(_ body: String) throws -> NSBitmapImageRep {
        try bitmap(parse(body))
    }

    private func bitmap(_ node: Node, layout: ContentLayout = .of()) throws -> NSBitmapImageRep {
        let image = node.toNativeImage(size: Size(w: 100, h: 100), layout: layout, scale: 1)
        return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
    }

    private func assertTransparent(_ image: NSBitmapImageRep, at points: [(Int, Int)],
                                   file: StaticString = #file, line: UInt = #line) throws {
        for (x, y) in points {
            XCTAssertLessThan(try XCTUnwrap(image.colorAt(x: x, y: y)).alphaComponent, 0.01,
                              "Expected transparent pixel at (\(x), \(y))", file: file, line: line)
        }
    }

    private func assertOpaque(_ image: NSBitmapImageRep, at points: [(Int, Int)],
                              file: StaticString = #file, line: UInt = #line) throws {
        for (x, y) in points {
            XCTAssertGreaterThan(try XCTUnwrap(image.colorAt(x: x, y: y)).alphaComponent, 0.99,
                                 "Expected opaque pixel at (\(x), \(y))", file: file, line: line)
        }
    }
}
#endif

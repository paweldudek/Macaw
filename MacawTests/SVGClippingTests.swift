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

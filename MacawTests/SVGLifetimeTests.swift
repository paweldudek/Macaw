#if os(macOS)
import AppKit
import XCTest
#if SWIFT_PACKAGE
import Macaw
#else
import MacawOSX
#endif

final class SVGLifetimeTests: XCTestCase {
    func testRasterizingAnSVGReleasesItsSceneGraph() throws {
        weak var releasedNode: Node?
        var image: NSImage?
        autoreleasepool {
            let node = Group(contents: [Shape(form: Rect(x: 0, y: 0, w: 16, h: 16), fill: Color.red)])
            releasedNode = node
            image = node.toNativeImage(size: Size(w: 16, h: 16))
        }
        XCTAssertEqual(image?.size, NSSize(width: 16, height: 16))
        let bitmap = try XCTUnwrap(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let pixel = try XCTUnwrap(NSBitmapImageRep(cgImage: bitmap).colorAt(x: 8, y: 8)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(pixel.redComponent, 0.9)
        XCTAssertLessThan(pixel.greenComponent, 0.1)
        XCTAssertLessThan(pixel.blueComponent, 0.1)
        XCTAssertNil(releasedNode, "A raster image must not keep the SVG scene graph alive")
    }

    func testRepeatedSVGRasterizationDoesNotAccumulateSceneGraphs() throws {
        final class WeakNode {
            weak var node: Node?
            init(_ node: Node) { self.node = node }
        }
        var references: [WeakNode] = []
        var images: [NSImage] = []
        for cycle in 1...10 {
            try autoreleasepool {
                for _ in 0..<7 {
                    let node = try SVGParser.parse(text: """
                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
                            <g><rect width="16" height="16" fill="red"/></g>
                        </svg>
                        """)
                    references.append(WeakNode(node))
                    images.append(node.toNativeImage(size: Size(w: 16, h: 16)))
                }
            }
            XCTAssertEqual(references.filter { $0.node != nil }.count, 0, "Scene graphs remain after cycle \(cycle)")
        }
        XCTAssertEqual(images.count, 70)
    }

    @MainActor
    func testReleasingAnSVGViewReleasesItsSceneGraph() {
        weak var releasedNode: Node?
        weak var releasedView: SVGView?
        autoreleasepool {
            let node = Group(contents: [Shape(form: Rect(w: 16, h: 16), fill: Color.red)])
            let view = SVGView(node: node, frame: CGRect(x: 0, y: 0, width: 16, height: 16))
            releasedNode = node
            releasedView = view
        }
        XCTAssertNil(releasedView)
        XCTAssertNil(releasedNode, "Releasing a view must release its source scene graph")
    }

    @MainActor
    func testReplacingAnSVGViewsNodeReleasesThePreviousSceneGraph() {
        weak var releasedNode: Node?
        var view: SVGView!
        autoreleasepool {
            let node = Group(contents: [Shape(form: Rect(w: 16, h: 16), fill: Color.red)])
            view = SVGView(node: node, frame: CGRect(x: 0, y: 0, width: 16, height: 16))
            releasedNode = node
        }
        autoreleasepool {
            view.node = Group(contents: [Shape(form: Rect(w: 16, h: 16), fill: Color.blue)])
        }
        XCTAssertNotNil(view.node)
        XCTAssertNil(releasedNode, "Replacing a view's node must release its previous scene graph")
    }

    @MainActor
    func testReplacingAMacawViewsNodeReleasesThePreviousSceneGraph() {
        weak var releasedNode: Node?
        var view: MacawView!
        autoreleasepool {
            let node = Group(contents: [Shape(form: Rect(w: 16, h: 16), fill: Color.red)])
            view = MacawView(node: node, frame: CGRect(x: 0, y: 0, width: 16, height: 16))
            releasedNode = node
        }
        autoreleasepool {
            view.node = Group(contents: [Shape(form: Rect(w: 16, h: 16), fill: Color.blue)])
        }
        XCTAssertNotNil(view.node)
        XCTAssertNil(releasedNode, "Replacing a view's node must release every previous renderer")
    }
}
#endif

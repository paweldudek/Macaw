import XCTest
import CoreGraphics
#if SWIFT_PACKAGE
import Macaw
#elseif os(OSX)
import MacawOSX
#endif

final class NodeContextRenderingTests: XCTestCase {
    func testDrawsIntoTheExistingContextWithoutClearingOrChangingItsTransform() throws {
        let context = try bitmap()
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.translateBy(x: 1, y: 1)
        let transform = context.ctm
        let node = Shape(form: Rect(x: 7, y: 7, w: 16, h: 16), fill: Color(0x00ff00))
        node.render(in: context, size: Size(w: 32, h: 32), layout: .none)
        XCTAssertEqual(context.ctm, transform)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(pixels[(16 * 32 + 16) * 4 + 1], 240)
        XCTAssertEqual(pixels[2], 255, "Existing pixels outside the node must remain intact")
    }

    func testRootOpacityIsAppliedOnce() throws {
        let context = try bitmap()
        let node = Shape(form: Rect(x: 0, y: 0, w: 32, h: 32), fill: Color.red, opacity: 0.5)
        node.render(in: context, size: Size(w: 32, h: 32))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(Int(pixels[(16 * 32 + 16) * 4 + 3]), 128, accuracy: 1)
    }

    func testSimpleShapesRemainVectorContentInPDF() throws {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        Shape(form: Rect(x: 0, y: 0, w: 32, h: 32), fill: Color.red)
            .render(in: context, size: Size(w: 32, h: 32))
        context.endPDFPage()
        context.closePDF()
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        var resources: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(page.dictionary!, "Resources", &resources))
        var images: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(try XCTUnwrap(resources), "XObject", &images) {
            XCTAssertEqual(CGPDFDictionaryGetCount(try XCTUnwrap(images)), 0,
                           "A simple vector shape must not become an image XObject")
        }
    }

    func testIndependentNodesAndContextsRenderOnConcurrentWorkers() {
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            do {
                let context = try bitmap()
                Shape(form: Rect(x: 0, y: 0, w: 32, h: 32), fill: Color.red)
                    .render(in: context, size: Size(w: 32, h: 32))
                let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                XCTAssertEqual(pixels[(16 * 32 + 16) * 4], 255)
            } catch { XCTFail("Rendering failed: \(error)") }
        }
    }

    func testDrawingDoesNotRetainTheSceneGraph() throws {
        let context = try bitmap()
        weak var releasedNode: Node?
        autoreleasepool {
            let node = Group(contents: [Shape(form: Rect(w: 32, h: 32), fill: Color.red)])
            releasedNode = node
            for _ in 0..<10 { node.render(in: context, size: Size(w: 32, h: 32)) }
        }
        XCTAssertNil(releasedNode, "The caller-owned context must not retain temporary renderers or their tree")
    }

    func testIndependentMaskedNodesRenderOnConcurrentWorkers() {
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            do {
                let context = try bitmap()
                let mask = Shape(form: Rect(w: 32, h: 32), fill: Color.white)
                Shape(form: Rect(w: 32, h: 32), fill: Color.red, mask: mask)
                    .render(in: context, size: Size(w: 32, h: 32))
                let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                XCTAssertEqual(pixels[(16 * 32 + 16) * 4], 255)
            } catch { XCTFail("Masked rendering failed: \(error)") }
        }
    }

    func testMaskedDrawingReleasesTheMaskScene() throws {
        let context = try bitmap()
        weak var releasedMask: Node?
        autoreleasepool {
            let mask = Shape(form: Rect(w: 32, h: 32), fill: Color.white)
            releasedMask = mask
            let node = Shape(form: Rect(w: 32, h: 32), fill: Color.red, mask: mask)
            node.render(in: context, size: Size(w: 32, h: 32))
        }
        XCTAssertNil(releasedMask)
    }

    func testMaskedPDFDrawingUsesTheDestinationResolution() throws {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 128, height: 128)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data)), mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.scaleBy(x: 4, y: 4)
        let mask = Shape(form: Rect(w: 32, h: 32), fill: Color.white)
        Shape(form: Rect(w: 32, h: 32), fill: Color.red, mask: mask)
            .render(in: context, size: Size(w: 32, h: 32))
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: data))))
        let page = try XCTUnwrap(document.page(at: 1))
        var resources: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(page.dictionary!, "Resources", &resources))
        var images: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(resources), "XObject", &images))
        var width = 0
        CGPDFDictionaryApplyFunction(try XCTUnwrap(images), { _, object, userInfo in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream), let userInfo else { return }
            var width: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(dictionary, "Width", &width) {
                userInfo.assumingMemoryBound(to: Int.self).pointee = Int(width)
            }
        }, &width)
        XCTAssertEqual(width, 128, "Masks must use destination pixels instead of the attached screen's scale")
    }

    private func bitmap() throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
    }
}

import XCTest

#if os(OSX)
import AppKit
#endif

#if SWIFT_PACKAGE
@testable import Macaw
#elseif os(OSX)
@testable import MacawOSX
#endif

#if os(OSX)
final class GraphicsContextConcurrencyTests: XCTestCase {
    func testImageContextScaleIsIsolatedBetweenThreads() {
        let size = CGSize(width: 10, height: 6)
        let firstContextReady = DispatchSemaphore(value: 0)
        let secondContextReady = DispatchSemaphore(value: 0)
        let firstContextRead = DispatchSemaphore(value: 0)
        let completion = DispatchGroup()
        var firstImage: NSImage?
        var secondImage: NSImage?

        completion.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            MGraphicsBeginImageContextWithOptions(size, false, 1)
            firstContextReady.signal()
            secondContextReady.wait()
            firstImage = MGraphicsGetImageFromCurrentImageContext()
            firstContextRead.signal()
            MGraphicsEndImageContext()
            completion.leave()
        }

        completion.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            firstContextReady.wait()
            MGraphicsBeginImageContextWithOptions(size, false, 3)
            secondContextReady.signal()
            firstContextRead.wait()
            secondImage = MGraphicsGetImageFromCurrentImageContext()
            MGraphicsEndImageContext()
            completion.leave()
        }

        XCTAssertEqual(completion.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(firstImage?.size, size)
        XCTAssertEqual(secondImage?.size, size)
    }

    func testImageContextScaleSupportsNestedContexts() {
        let outerSize = CGSize(width: 12, height: 8)
        let innerSize = CGSize(width: 7, height: 5)

        MGraphicsBeginImageContextWithOptions(outerSize, false, 1)
        MGraphicsBeginImageContextWithOptions(innerSize, false, 2)
        let innerImage = MGraphicsGetImageFromCurrentImageContext()
        MGraphicsEndImageContext()
        let outerImage = MGraphicsGetImageFromCurrentImageContext()
        MGraphicsEndImageContext()

        XCTAssertEqual(innerImage?.size, innerSize)
        XCTAssertEqual(outerImage?.size, outerSize)
    }
}
#endif

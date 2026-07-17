//
//  SVGParserTest.swift
//  MacawTests
//
//  Created by Julius Lundang on 19/08/2018.
//  Copyright © 2018 Exyte. All rights reserved.
//

import XCTest
#if canImport(Darwin)
import Darwin
#endif

#if SWIFT_PACKAGE
@testable import Macaw
#elseif os(OSX)
@testable import MacawOSX
#elseif os(iOS)
@testable import Macaw
#endif

class SVGParserTest: XCTestCase {
    private let scientificNotationClipSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="0 0 200 200">
      <clipPath id="clip">
        <path d="m2.2737368E-13 -2.842171E-14l164 0l0 114.73389l-164 0z"/>
      </clipPath>
      <rect clip-path="url(#clip)" x="0" y="0" width="200" height="200" fill="#000"/>
    </svg>
    """

    func testParseFromOtherBundle() throws {
        let bundle = Bundle(for: type(of: TestUtils()))
        guard let bundleMacawTestsURL = bundle.resourceURL?.appendingPathComponent("MacawTests.bundle"),
              let macawTestsBundle = Bundle(url: bundleMacawTestsURL) else {
            throw XCTSkip("MacawTests.bundle is not available in this test environment")
        }
        do {
            let node = try SVGParser.parse(resource: "circle", fromBundle: macawTestsBundle)
            XCTAssertNotNil(node)
            if let fullPath = macawTestsBundle.path(forResource: "circle", ofType: "svg") {
                let node2 = try SVGParser.parse(fullPath: fullPath)
                XCTAssertNotNil(node2)
            } else {
                XCTFail("No circle.svg found")
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testParseGivenInvalidPath() {
        let fullPath = "invalid fullPath"
        XCTAssertThrowsError(try SVGParser.parse(fullPath: fullPath)) { error in
            XCTAssertEqual(error as! SVGParserError, SVGParserError.noSuchFile(path: "invalid fullPath"))
        }
    }
    
    func testParseGiventEmptyPath() {
        XCTAssertThrowsError(try SVGParser.parse(fullPath: "")) { error in
            XCTAssertEqual(error as! SVGParserError, SVGParserError.noSuchFile(path: ""))
        }
    }

    func testUppercaseExponentInClipPathDataKeepsInitialMoveSegment() throws {
        let node = try SVGParser.parse(text: scientificNotationClipSVG)
        let shapes = flatten(node).compactMap { $0 as? Shape }

        guard let shape = shapes.first, let clipPath = shape.clip as? Path else {
            return XCTFail("Expected a clipped shape with a parsed Path clip")
        }

        XCTAssertEqual(clipPath.segments.first?.type, .m)

        let rendered = node.toNativeImage(size: Size(w: 200, h: 200))
        #if os(OSX)
        XCTAssertNotNil(rendered.tiffRepresentation)
        #elseif os(iOS)
        XCTAssertNotNil(rendered.pngData())
        #endif
    }

    func testTopLevelClipPathDoesNotPrintUnsupportedWarning() throws {
        let output = try captureStdout {
            _ = try SVGParser.parse(text: scientificNotationClipSVG)
        }

        XCTAssertFalse(output.contains("Shape clipPath not supported"))
    }

    func testViewBoxProvidesIntrinsicSizeWithoutLayout() throws {
        let node = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)

        XCTAssertEqual(node.intrinsicSize?.w, 120)
        XCTAssertEqual(node.intrinsicSize?.h, 32)
    }

    func testAbsoluteDimensionsProvideIntrinsicSizeWithoutLayout() throws {
        let node = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" width="48" height="24" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)

        XCTAssertEqual(node.intrinsicSize?.w, 48)
        XCTAssertEqual(node.intrinsicSize?.h, 24)
    }

    func testSingleAbsoluteDimensionUsesViewBoxAspectRatioForIntrinsicSize() throws {
        let node = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" width="60" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)

        XCTAssertEqual(node.intrinsicSize?.w, 60)
        XCTAssertEqual(node.intrinsicSize?.h, 16)
    }

    func testZeroAbsoluteDimensionsDoNotFallBackToViewBoxForIntrinsicSize() throws {
        let node = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" width="0" height="0" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)

        XCTAssertNil(node.intrinsicSize)
    }

    func testSingleZeroAbsoluteDimensionDoesNotUseViewBoxAspectRatioForIntrinsicSize() throws {
        let zeroWidthNode = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" width="0" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)
        let zeroHeightNode = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" height="0" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)

        XCTAssertNil(zeroWidthNode.intrinsicSize)
        XCTAssertNil(zeroHeightNode.intrinsicSize)
    }

    func testZeroPercentageDimensionDoesNotFallBackToViewBoxForIntrinsicSize() throws {
        let zeroWidthNode = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" width="0%" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)
        let zeroHeightNode = try SVGParser.parse(text: """
        <svg xmlns="http://www.w3.org/2000/svg" height="0%" viewBox="0 0 120 32">
          <rect width="120" height="32"/>
        </svg>
        """)

        XCTAssertNil(zeroWidthNode.intrinsicSize)
        XCTAssertNil(zeroHeightNode.intrinsicSize)
    }

    private func flatten(_ node: Node) -> [Node] {
        if let group = node as? Group {
            return [group] + group.contents.flatMap(flatten)
        }
        return [node]
    }

    private func captureStdout(_ body: () throws -> Void) throws -> String {
        let pipe = Pipe()
        fflush(stdout)
        let original = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        do {
            try body()
        } catch {
            fflush(stdout)
            dup2(original, STDOUT_FILENO)
            close(original)
            pipe.fileHandleForWriting.closeFile()
            throw error
        }

        fflush(stdout)
        dup2(original, STDOUT_FILENO)
        close(original)
        pipe.fileHandleForWriting.closeFile()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
@testable import Build

class MockSwiftCompilerOutputParserDelegate: SwiftCompilerOutputParserDelegate {
    private var messages: [SwiftCompilerMessage] = []
    private var error: Error?

    func swiftCompilerDidOutputMessage(_ message: SwiftCompilerMessage) {
        messages.append(message)
    }

    func swiftCompilerOutputParserDidFail(withError error: Error) {
        self.error = error
    }

    func assert(
        messages: [SwiftCompilerMessage],
        errorDescription: String?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(messages, self.messages, file: file, line: line)
        let errorReason = (self.error as? LocalizedError)?.errorDescription ?? error?.localizedDescription
        XCTAssertEqual(errorDescription, errorReason, file: file, line: line)
        self.messages = []
        self.error = nil
    }
}

class SwiftCompilerOutputParserTests: XCTestCase {
    func testParse() throws {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(delegate: delegate)

        parser.parse(bytes: "22".utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: "".utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: """
            9
            {
              "kind": "began",
              "name": "compile",
              "inputs": [
                "test.swift"
              ],

            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: "".utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: """
              "outputs": [
                {
                  "type": "object",
                  "path": "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o"
                }
              ],
              "pid": 22698
            }
            117

            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(
                name: "compile",
                kind: .began(.init(
                    inputs: ["test.swift"],
                    outputs: [.init(
                        type: "object",
                        path: "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o")])))
        ], errorDescription: nil)

        parser.parse(bytes: """
            {
              "kind": "finished",
              "name": "compile",
              "pid": 22698,
              "exit-status": 1,
              "output": "error: it failed :-("
            }
            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(
                name: "compile",
                kind: .finished(.init(output: "error: it failed :-(")))
        ], errorDescription: nil)

        parser.parse(bytes: """

            233
            {
              "kind": "skipped",
              "name": "compile",
              "inputs": [
                "test2.swift"
              ],
              "outputs": [
                {
                  "type": "object",
                  "path": "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test2-77d991.o"
                }
              ],
              "pid": 58776
            }
            219
            {
              "kind": "began",
              "name": "link",
              "inputs": [
                "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o"
              ],
              "outputs": [
                {
                  "type": "image",
                  "path": "test"
                }
              ],
              "pid": 22699
            }
            119
            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(
                name: "compile",
                kind: .skipped(.init(
                    inputs: ["test2.swift"],
                    outputs: [.init(
                        type: "object",
                        path: "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test2-77d991.o")]))),
            SwiftCompilerMessage(
                name: "link",
                kind: .began(.init(
                    inputs: ["/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o"],
                    outputs: [.init(
                        type: "image",
                        path: "test")])))
        ], errorDescription: nil)

        parser.parse(bytes: """

            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }

            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(
                name: "link",
                kind: .signalled(.init(output: nil)))
        ], errorDescription: nil)
    }

    func testInvalidMessageSizeBytes() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(delegate: delegate)

        parser.parse(bytes: [65, 66, 200, 67, UInt8(ascii: "\n")])
        delegate.assert(messages: [], errorDescription: "invalid UTF8 bytes")

        parser.parse(bytes: """
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
    }

    func testInvalidMessageSizeValue() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(delegate: delegate)

        parser.parse(bytes: """
            2A

            """.utf8)
        delegate.assert(messages: [], errorDescription: "invalid message size")

        parser.parse(bytes: """
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
    }

    func testInvalidMessageBytes() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(delegate: delegate)

        parser.parse(bytes: """
            4

            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
        parser.parse(bytes: [65, 66, 200, 67, UInt8(ascii: "\n")])
        delegate.assert(messages: [], errorDescription: "unexpected JSON message")

        parser.parse(bytes: """
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
    }

    func testInvalidMessageMissingField() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(delegate: delegate)

        parser.parse(bytes: """
            23
            {
              "invalid": "json"
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: "unexpected JSON message")

        parser.parse(bytes: """
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
    }

    func testInvalidMessageInvalidValue() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(delegate: delegate)

        parser.parse(bytes: """
            23
            {
              "kind": "invalid",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: "unexpected JSON message")

        parser.parse(bytes: """
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
    }
}
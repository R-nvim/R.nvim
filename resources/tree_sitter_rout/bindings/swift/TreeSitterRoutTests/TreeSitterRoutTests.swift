import XCTest
import SwiftTreeSitter
import TreeSitterRout

final class TreeSitterRoutTests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_rout())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading Rout grammar")
    }
}

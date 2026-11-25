import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
struct CheckSkip: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
func checkTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    if try !value() { throw CheckFailure("\(file):\(line): expected true") }
}
func checkFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    if try value() { throw CheckFailure("\(file):\(line): expected false") }
}
func checkEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) throws {
    let a = try lhs(), b = try rhs()
    if a != b { throw CheckFailure("\(file):\(line): \(a) != \(b)") }
}
func checkEqual(_ lhs: Float, _ rhs: Float, accuracy: Float, file: StaticString = #filePath, line: UInt = #line) throws {
    if abs(lhs-rhs) > accuracy { throw CheckFailure("\(file):\(line): float values differ") }
}
func checkNotEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) throws {
    if try lhs() == rhs() { throw CheckFailure("\(file):\(line): expected different values") }
}
func checkThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) throws {
    do { _ = try expression() } catch { return }
    throw CheckFailure("\(file):\(line): expected an error")
}
@main struct CheckMain {
    static func main() async {
        var failures = 0, passed = 0, skipped = 0
        let suite = CoreTests()
        let checks: [(String, () async throws -> Void)] = [
            ("testEPUB2NestedNavigationLabels", { try suite.testEPUB2NestedNavigationLabels() }),
            ("testDiscoveryCursorIsAtomicDeduplicatesAndSecuresURLs", { try suite.testDiscoveryCursorIsAtomicDeduplicatesAndSecuresURLs() }),
            ("testDiscoveryMaintenanceBackoffAndCatalogueRemainIndependent", { try await suite.testDiscoveryMaintenanceBackoffAndCatalogueRemainIndependent() }),
            ("testGutenbergDownloadFallsBackImportsAndNeverEmbeds", { try await suite.testGutenbergDownloadFallsBackImportsAndNeverEmbeds() }),
            ("testGutenbergRejectsMaintenanceHTMLWithoutImporting", { try await suite.testGutenbergRejectsMaintenanceHTMLWithoutImporting() }),
            ("testDictionaryFieldsRoundTripAndLegacyTextSurvives", { try suite.testDictionaryFieldsRoundTripAndLegacyTextSurvives() }),
            ("testReadingModesAndIndependentOffsetsPersist", { try suite.testReadingModesAndIndependentOffsetsPersist() }),
            ("testPaginationCoversAllTextFitsImagesAndPreservesAnchor", { try suite.testPaginationCoversAllTextFitsImagesAndPreservesAnchor() }),

            ("testModelPathsAreConfigurableAndRoundTripWithoutAllowlist", { try suite.testModelPathsAreConfigurableAndRoundTripWithoutAllowlist() }),
            ("testInvalidModelConfigurationDoesNotOverwriteExistingFile", { try suite.testInvalidModelConfigurationDoesNotOverwriteExistingFile() }),
            ("testPDFImportCopiesFileAndDoesNotEmbed", { try suite.testPDFImportCopiesFileAndDoesNotEmbed() }),
            ("testEPUBImportAndNativeLayout", { try suite.testEPUBImportAndNativeLayout() }),
            ("testEPUBWithoutCoverStillImports", { try suite.testEPUBWithoutCoverStillImports() }),
            ("testFailedImportRemovesCopiedFiles", { try suite.testFailedImportRemovesCopiedFiles() }),
            ("testEPUBPathsCannotEscapeLibrary", { try suite.testEPUBPathsCannotEscapeLibrary() }),
            ("testEPUBArchiveRejectsTraversalBeforeExtracting", { try suite.testEPUBArchiveRejectsTraversalBeforeExtracting() }),
            ("testNativeHTMLExcludesScriptsAndPreservesEmphasis", { try suite.testNativeHTMLExcludesScriptsAndPreservesEmphasis() }),
            ("testNotesVocabularyThreadsAndPositionPersist", { try suite.testNotesVocabularyThreadsAndPositionPersist() }),
            ("testDeleteCascadesStudyDataAndKeepsSourceFile", { try suite.testDeleteCascadesStudyDataAndKeepsSourceFile() }),
            ("testIndexReplacementIsAtomicAndSpoilersFilterBothSearches", { try suite.testIndexReplacementIsAtomicAndSpoilersFilterBothSearches() }),
            ("testTransactionRollsBackOnFailure", { try suite.testTransactionRollsBackOnFailure() }),
            ("testInterruptedIndexBecomesRetryableOnRelaunch", { try suite.testInterruptedIndexBecomesRetryableOnRelaunch() }),
            ("testChunkerHandlesUnicodeOverlapAndInvalidConfiguration", { try suite.testChunkerHandlesUnicodeOverlapAndInvalidConfiguration() }),
            ("testCosineHandlesZerosAndDimensionMismatch", { try suite.testCosineHandlesZerosAndDimensionMismatch() }),
            ("testEmbeddingAndSemanticSearchOnThisMac", { try await suite.testEmbeddingAndSemanticSearchOnThisMac() }),
            ("testCancellationDoesNotPublishReadyIndex", { try await suite.testCancellationDoesNotPublishReadyIndex() }),
            ("testSSEFramingWithoutEmptyLinesAndMultilineJSON", { try suite.testSSEFramingWithoutEmptyLinesAndMultilineJSON() }),
            ("testSSEContentToolFragmentsDoneAndProviderError", { try suite.testSSEContentToolFragmentsDoneAndProviderError() }),
            ("testAnnotationAnchorsDistinguishRepeatedQuotesAndRejectInvalidRanges", { try suite.testAnnotationAnchorsDistinguishRepeatedQuotesAndRejectInvalidRanges() }),
            ("testLegacyPositionAndMessageShapes", { try suite.testLegacyPositionAndMessageShapes() }),
            ("testReadOnlyLegacyImportPreservesSourceAndDoesNotIndex", { try suite.testReadOnlyLegacyImportPreservesSourceAndDoesNotIndex() })
        ]
        for (name, run) in checks {
            do {
                try suite.setUpWithError()
                defer { try? suite.tearDownWithError() }
                try await run(); passed += 1; print("PASS \(name)")
            } catch let skip as CheckSkip { skipped += 1; print("SKIP \(name): \(skip)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(passed) passed, \(failures) failed, \(skipped) skipped")
        if failures != 0 { exit(1) }
    }
}

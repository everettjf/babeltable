import XCTest
@testable import BabelTable

@MainActor
final class OfflineModelStatusTests: XCTestCase {
    func testServiceColdStartIsRetriedInsteadOfRequestingDownload() async {
        var samples: [OfflineModels.Status] = [.needsDownload, .unavailable, .ready]
        let status = await OfflineModels.settledStatus(probe: { samples.removeFirst() }, wait: {})
        XCTAssertEqual(status, .ready)
        XCTAssertTrue(samples.isEmpty)
    }

    func testInterruptedCatalogRecoversWithoutReportingUnsupported() async {
        var samples: [OfflineModels.Status] = [.unsupported, .ready]
        let status = await OfflineModels.settledStatus(probe: { samples.removeFirst() }, wait: {})
        XCTAssertEqual(status, .ready)
    }

    func testActuallyMissingModelsAreConfirmedBeforeDownloadPrompt() async {
        var checks = 0
        let status = await OfflineModels.settledStatus(probe: { checks += 1; return .needsDownload }, wait: {})
        XCTAssertEqual(status, .needsDownload)
        XCTAssertEqual(checks, 3)
    }

    func testChangingNegativeResultsAreNotTreatedAsMissingModels() async {
        var samples: [OfflineModels.Status] = [.needsDownload, .unsupported, .needsDownload]
        let status = await OfflineModels.settledStatus(probe: { samples.removeFirst() }, wait: {})
        XCTAssertEqual(status, .unavailable)
    }

    func testServiceFailureAndCancellationDoNotAskForDownloads() async {
        let failed = await OfflineModels.settledStatus(probe: { .unavailable }, wait: {})
        XCTAssertEqual(failed, .unavailable)
        let cancelled = await OfflineModels.settledStatus(probe: { .needsDownload }, wait: { throw CancellationError() })
        XCTAssertEqual(cancelled, .unavailable)
    }
}

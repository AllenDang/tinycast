import XCTest

@MainActor
final class LauncherUITests: XCTestCase {
    private var app: XCUIApplication!
    private var reportURL: URL!
    private var search: XCUIElement { app.textFields["launcher.search"] }

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchEnvironment["TINYCAST_UI_COUNT"] = name.contains("Large") ? "3000" : "300"
            reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("tinycast-ui-\(UUID()).json")
            XCTAssertTrue(FileManager.default.createFile(
                atPath: reportURL.appendingPathExtension("request").path, contents: Data()))
            app.launchEnvironment["TINYCAST_UI_METRICS_PATH"] = reportURL.path
            app.launch()
            app.activate()
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.click()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            app.terminate()
            app = nil
            try? FileManager.default.removeItem(at: reportURL)
            try? FileManager.default.removeItem(at: reportURL.appendingPathExtension("request"))
        }
    }

    private func replaceQuery(_ query: String) {
        if (search.value as? String)?.isEmpty == false {
            app.typeKey("a", modifierFlags: .command)
        }
        app.typeText(query)
        XCTAssertEqual(search.value as? String, query)
    }

    private func assertResult(_ name: String) {
        let result = app.staticTexts[name]
        if !result.exists && !result.waitForExistence(timeout: 5) {
            XCTFail("Missing result: \(name)\n\(app.debugDescription)")
        }
    }

    func testTypingBackspaceAndReplacement() {
        app.typeText("Fixture Safari")
        assertResult("Fixture Safari")
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(search.value as? String, "Fixture Safar")
        assertResult("Fixture Safari")
        replaceQuery("Fixture Terminal")
        assertResult("Fixture Terminal")
        XCTAssertFalse(app.staticTexts["Fixture Safari"].exists)
        replaceQuery("zzzz-no-result")
        assertResult("No apps found")
    }

    func testChineseTextInput() {
        replaceQuery("浏览器")
        assertResult("Fixture 浏览器")
    }

    func testAccentedTextInput() {
        replaceQuery("Café")
        assertResult("Fixture Café")
    }

    func testImmediateEnterTargetsCurrentResult() {
        app.typeText("Fixture Safari\n")
        assertResult("Are you sure you want to run this command?\n\n:")
        assertResult("Fixture Safari")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testCalculatorUpdatesWithoutChangingAppRows() {
        replaceQuery("=1+1")
        assertResult("2")
        app.typeKey(.delete, modifierFlags: [])
        app.typeText("2")
        assertResult("3")
        XCTAssertFalse(app.staticTexts["2"].exists)
    }

    func testTieOrdering() {
        replaceQuery("Fixture Application")
        assertResult("Fixture Application 0005")
        let labels = app.staticTexts.allElementsBoundByIndex
            .compactMap { $0.value as? String }
            .filter { $0.hasPrefix("Fixture Application ") }
        XCTAssertGreaterThanOrEqual(labels.count, 2)
        XCTAssertEqual(Array(labels.prefix(2)), ["Fixture Application 0005", "Fixture Application 0006"])
    }

    func testSelectionResetsAfterEditingQuery() {
        replaceQuery("Fixture Application")
        app.typeKey(.downArrow, modifierFlags: [])
        replaceQuery("Fixture Terminal")
        app.typeKey(.return, modifierFlags: [])
        assertResult("Are you sure you want to run this command?\n\n:")
        assertResult("Fixture Terminal")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testWarmTypingPerformance() throws { try measureTyping() }

    func testLargeIndexPerformance() throws { try measureTyping() }

    private func requestMetrics(reset: Bool) throws {
        try? FileManager.default.removeItem(at: reportURL)
        let file = try FileHandle(forWritingTo: reportURL.appendingPathExtension("request"))
        try file.truncate(atOffset: 0)
        try file.write(contentsOf: Data((reset ? "reset" : "export").utf8))
        try file.close()
        let url = reportURL!
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }

    private func measureTyping() throws {
        replaceQuery("Fixture Safari")
        assertResult("Fixture Safari")
        try requestMetrics(reset: true)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options) {
            for name in ["Fixture Terminal", "Fixture Chrome", "Fixture Safari"] {
                replaceQuery(name)
                assertResult(name)
            }
        }
        try requestMetrics(reset: false)
        let data = try Data(contentsOf: reportURL)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let samples = try XCTUnwrap(report["layoutMilliseconds"] as? [Double]).sorted()
        XCTAssertGreaterThan(samples.count, 20)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Launcher input-to-layout samples"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("LAYOUT samples=\(samples.count) p50=\(samples[samples.count / 2]) "
              + "p95=\(samples[Int(Double(samples.count - 1) * 0.95)]) "
              + "p99=\(samples[Int(Double(samples.count - 1) * 0.99)]) "
              + "superseded=\(report["superseded"] ?? 0)")
    }
}

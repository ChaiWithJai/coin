import XCTest

final class GuardFlowTests: XCTestCase {
    func testGuardAnalysisOnFirstRound() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-language", "fr", "-noAutoStart"]
        app.launch()
        let videos = app.tabBars.buttons["Vidéos"]
        if videos.exists { videos.tap() }
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sac 240'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let analyse = app.buttons["Analyser ma garde"]
        for _ in 0..<4 where !analyse.isHittable { app.swipeUp() }
        XCTAssertTrue(analyse.waitForExistence(timeout: 5))
        analyse.tap()
        let coverage = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Analysable'")).firstMatch
        XCTAssertTrue(coverage.waitForExistence(timeout: 180))
        app.swipeUp()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; shot.name = "guard-analysis"; add(shot)
        print("COVERAGE_LABEL:", coverage.label)
        let yes = app.buttons["Oui"]
        if yes.exists {
            yes.tap()
            XCTAssertTrue(app.staticTexts["Confirmé"].waitForExistence(timeout: 5))
            let after = XCTAttachment(screenshot: app.screenshot()); after.lifetime = .keepAlways; after.name = "guard-confirmed"; add(after)
        }
    }
}

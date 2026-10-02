import XCTest

final class WorkoutFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func application(language: String, directory: String = UUID().uuidString, shortFreestyle: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-noAutoStart", "-language", language]
        app.launchEnvironment["COIN_TRAINING_DIRECTORY"] = "workout-ui-" + directory
        app.launchEnvironment["COIN_SERVICE_URL"] = "http://127.0.0.1:1"
        app.launchEnvironment["COIN_SERVICE_TOKEN"] = "ui-fixture"
        if shortFreestyle {
            app.launchEnvironment["COIN_TEST_FREESTYLE"] = "1"
            app.launchEnvironment["COIN_TEST_ROUND_REVIEW"] = "1"
        }
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<15 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected control was not reachable: \(element)")
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testBothSourceProgramsReachDay35() throws {
        let app = application(language: "en")
        app.buttons["choose-program"].tap()
        XCTAssertTrue(app.buttons["lesson-basic-w1-d1"].waitForExistence(timeout: 5))
        reveal(app.buttons["lesson-basic-w5-d7"], in: app)
        attach("basic-last-source-day", app: app)
        for _ in 0..<15 where !app.buttons["Competitive"].isHittable { app.swipeDown() }
        app.buttons["Competitive"].tap()
        XCTAssertTrue(app.buttons["lesson-competitive-w1-d1"].waitForExistence(timeout: 5))
        reveal(app.buttons["lesson-competitive-w5-d7"], in: app)
        attach("competitive-last-source-day", app: app)
    }

    func testManualSourceStepAdvancesToExactTimedRoundAndResumes() throws {
        let directory = UUID().uuidString
        let app = application(language: "en", directory: directory)
        app.buttons["choose-program"].tap()
        app.buttons["lesson-basic-w1-d1"].tap()
        app.buttons["start-workout"].tap()
        XCTAssertTrue(app.buttons["complete-manual-step"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "DYNAMIC WARM-UP:")
        let toggle = app.buttons["workout-toggle"]
        if toggle.label.contains("Start") { toggle.tap() }
        let elapsed = NSPredicate(format: "label != %@", "00:00")
        expectation(for: elapsed, evaluatedWith: app.staticTexts["workout-clock"])
        waitForExpectations(timeout: 6)
        toggle.tap()
        attach("source-manual-step-paused", app: app)
        app.buttons["complete-manual-step"].tap()
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "FR0NTAL STANCE DRILL")
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "02:00")
        XCTAssertFalse(app.buttons["complete-manual-step"].exists)
        app.buttons["workout-source"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "4 ROUNDS OF 2 MINUTES WITH 30 SECONDS OF REST IN BETWEEN.")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        attach("source-two-minute-round", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Workout #1"].waitForExistence(timeout: 5))
        app.buttons["start-workout"].tap()
        XCTAssertTrue(app.staticTexts["workout-source-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "FR0NTAL STANCE DRILL")
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "02:00")
        attach("source-round-resumed", app: app)
    }

    func testFreestyleUsesLocalLanguageWithoutImposingProbeDrill() throws {
        for language in ["en", "fr"] {
            let app = application(language: language)
            let mode = app.buttons["choose-freestyle"]
            XCTAssertTrue(mode.waitForExistence(timeout: 5))
            XCTAssertTrue(mode.label.contains(language == "fr" ? "Libre" : "Freestyle"))
            mode.tap()
            app.buttons["start-workout"].tap()
            XCTAssertTrue(app.staticTexts["workout-clock"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
            XCTAssertTrue(app.staticTexts[language == "fr" ? "à ton rythme" : "your rhythm"].exists)
            XCTAssertFalse(app.buttons["complete-manual-step"].exists)
            XCTAssertFalse(app.staticTexts["JAB  →  2–3 PUNCHES  →  ANGLE"].exists)
            XCTAssertFalse(app.staticTexts["JAB  →  2–3 COUPS  →  ANGLE"].exists)
            XCTAssertFalse(app.buttons["workout-source"].exists)
            attach("freestyle-" + language, app: app)
            app.terminate()
        }
    }

    func testEntireManualStrengthWorkoutSavesReviewAndProgramProgress() throws {
        let app = application(language: "en")
        app.buttons["choose-program"].tap()
        let sourceDay = app.buttons["lesson-basic-w1-d6"]
        reveal(sourceDay, in: app)
        sourceDay.tap()
        app.buttons["start-workout"].tap()
        XCTAssertTrue(app.buttons["complete-manual-step"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "Squat")
        app.buttons["complete-manual-step"].tap()
        XCTAssertFalse(app.buttons["recap-done"].exists)
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "Pallof Press")
        app.terminate()
        app.launch()
        app.buttons["start-workout"].tap()
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "Pallof Press")
        for expected in ["Hip Airplanes", "Scap Push-Up", "Depth Drop", "Kettlebell Swing", "Stretch Series", "Plyo Push-Up", "Inverted Row", "Dumbbell Overhead Walk (20 Steps Each)"] {
            app.buttons["complete-manual-step"].tap()
            XCTAssertEqual(app.staticTexts["workout-source-title"].label, expected)
        }
        app.buttons["complete-manual-step"].tap()
        XCTAssertTrue(app.buttons["recap-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Squat"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "marked done by you")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["0 min"].exists)
        attach("manual-strength-complete-recap", app: app)
        let viewLog = app.buttons["recap-view-log"]
        reveal(viewLog, in: app)
        viewLog.tap()
        XCTAssertTrue(app.staticTexts["Squat"].waitForExistence(timeout: 3))
        app.buttons["Original instructions"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "3 SETS OF 10 REPS EACH EXERCISE")).firstMatch.waitForExistence(timeout: 3))
        attach("manual-strength-source-review", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["recap-done"].tap()
        XCTAssertTrue(app.buttons["choose-program"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.buttons["choose-program"].tap()
        let completed = app.buttons["lesson-basic-w1-d6"]
        reveal(completed, in: app)
        XCTAssertTrue(completed.label.contains("Workout completed"), completed.label)
        attach("manual-strength-program-progress", app: app)
        app.buttons["Close"].tap()
        let saved = app.buttons["saved-session-basic-w1-d6"]
        reveal(saved, in: app)
        saved.tap()
        XCTAssertTrue(app.staticTexts["Squat"].waitForExistence(timeout: 3))
    }

    func testFreestyleTimerFinishesSavesReflectionAndReopensReview() throws {
        let app = application(language: "en", shortFreestyle: true)
        app.buttons["start-workout"].tap()
        XCTAssertTrue(app.staticTexts["workout-clock"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "00:10")
        app.buttons["workout-toggle"].tap()
        XCTAssertTrue(app.buttons["recap-done"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["That's a wrap."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "00:10 timed · finished")).firstMatch.exists)
        let pendingReview = app.staticTexts["Review pending. Your round is saved on this phone."]
        reveal(pendingReview, in: app)
        XCTAssertTrue(pendingReview.exists)
        attach("freestyle-final-round-pending-recap", app: app)
        let note = app.descendants(matching: .any)["recap-reflection"]
        reveal(note, in: app)
        note.tap()
        note.typeText("Finished the timed round.")
        app.buttons["recap-done"].tap()
        XCTAssertTrue(app.buttons["choose-program"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        let saved = app.buttons["saved-session-freestyle-1-10-0-v1"]
        reveal(saved, in: app)
        saved.tap()
        reveal(pendingReview, in: app)
        XCTAssertTrue(pendingReview.exists)
        let reflection = app.staticTexts["Finished the timed round."]
        reveal(reflection, in: app)
        XCTAssertTrue(reflection.exists)
        attach("freestyle-finished-saved-review", app: app)
    }
}

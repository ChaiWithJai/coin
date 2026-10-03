import XCTest

final class WorkoutFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func application(language: String, directory: String = UUID().uuidString, shortFreestyle: Bool = false,
                             activityFixture: Bool = false, acceleratedSource: Bool = false,
                             zeroDetectionFreestyle: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-noAutoStart", "-language", language]
        app.launchEnvironment["COIN_TRAINING_DIRECTORY"] = "workout-ui-" + directory
        app.launchEnvironment["COIN_SERVICE_URL"] = "http://127.0.0.1:1"
        app.launchEnvironment["COIN_SERVICE_TOKEN"] = "ui-fixture"
        if shortFreestyle {
            app.launchEnvironment["COIN_TEST_FREESTYLE"] = "1"
            app.launchEnvironment["COIN_TEST_ROUND_REVIEW"] = "1"
        }
        if zeroDetectionFreestyle {
            app.launchEnvironment["COIN_TEST_FREESTYLE"] = "1"
            app.launchEnvironment["COIN_TEST_TIMER_STEP_SECONDS"] = "300"
        }
        if activityFixture { app.launchEnvironment["COIN_TEST_ACTIVITY_CHOOSER"] = "1" }
        if acceleratedSource { app.launchEnvironment["COIN_TEST_TIMER_STEP_SECONDS"] = "300" }
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

    private func chooseRequiredMovementIfShown(_ app: XCUIApplication, language: String = "en") {
        let chooser = app.navigationBars[language == "fr" ? "Choisir le mouvement" : "Choose movement"]
        guard chooser.waitForExistence(timeout: 5) else { return }
        let option = app.buttons["activity-choice-shoulder_circles"]
        XCTAssertTrue(option.waitForExistence(timeout: 2))
        option.tap()
    }

    private func waitForSourceTitle(_ title: String, in app: XCUIApplication,
                                    timeout: TimeInterval = 12) {
        let sourceTitle = app.staticTexts["workout-source-title"]
        let predicate = NSPredicate(format: "label == %@", title)
        expectation(for: predicate, evaluatedWith: sourceTitle)
        waitForExpectations(timeout: timeout)
        XCTAssertEqual(sourceTitle.label, title)
    }

    private func completeManualSourceStep(_ title: String, in app: XCUIApplication) {
        waitForSourceTitle(title, in: app)
        let done = app.buttons["complete-manual-step"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()
    }

    private func waitForTimedRest(in app: XCUIApplication, timeout: TimeInterval = 4) {
        XCTAssertTrue(app.staticTexts["REST"].waitForExistence(timeout: timeout),
                      "Expected the native timed rest segment")
        // The 300-second UI-test clock can take the one-minute rest to zero in
        // the same accessibility snapshot where REST first becomes visible.
        XCTAssertTrue(["01:00", "00:00"].contains(app.staticTexts["workout-clock"].label))
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
        attach("source-manual-step-paused", app: app)
        app.buttons["complete-manual-step"].tap()
        chooseRequiredMovementIfShown(app)
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

    func testMixedBagAndBandPrescriptionsShowSeparateClocks() throws {
        let app = application(language: "en")
        app.buttons["choose-program"].tap()
        let day = app.buttons["lesson-basic-w1-d5"]
        reveal(day, in: app)
        day.tap()
        app.buttons["start-workout"].tap()
        chooseRequiredMovementIfShown(app)
        let title = app.staticTexts["workout-source-title"]
        for _ in 0..<25 {
            if title.exists && title.label == "6 ROUNDS OF 3 MINUTES OF BAG WORK" { break }
            chooseRequiredMovementIfShown(app)
            app.buttons["Skip to next"].tap()
        }
        XCTAssertEqual(title.label, "6 ROUNDS OF 3 MINUTES OF BAG WORK")
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
        for _ in 0..<6 { app.buttons["Skip to next"].tap() }
        XCTAssertEqual(title.label, "Shadow ONLY boxing MOVEMENT with resistance bands. 6 rounds of 1 minute with 20")
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "01:00")
        XCTAssertFalse(app.staticTexts["EXCHANGES"].exists)
        attach("mixed-bag-band-separate-timers", app: app)
    }

    func testFrenchDayOneShowsWholeDayCopyAndKeepsOriginalAvailable() throws {
        let directory = UUID().uuidString
        let app = application(language: "fr", directory: directory)
        app.buttons["choose-program"].tap()
        app.buttons["lesson-basic-w1-d1"].tap()
        app.buttons["start-workout"].tap()
        XCTAssertTrue(app.staticTexts["workout-source-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "Échauffement dynamique :")
        app.buttons["workout-source"].tap()
        XCTAssertTrue(app.staticTexts["Échauffement dynamique :"].waitForExistence(timeout: 3))
        app.buttons["Texte source"].tap()
        XCTAssertTrue(app.staticTexts["DYNAMIC WARM-UP:"].waitForExistence(timeout: 3))
        app.buttons["Fermer"].tap()
        app.buttons["complete-manual-step"].tap()
        chooseRequiredMovementIfShown(app, language: "fr")
        app.buttons["complete-manual-step"].tap()
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "Exercice en garde frontale")
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "02:00")
        XCTAssertFalse(app.staticTexts["ÉCHANGES"].exists)
        attach("french-source-day-one", app: app)
        app.terminate()
        app.launch()
        app.buttons["start-workout"].tap()
        XCTAssertEqual(app.staticTexts["workout-source-title"].label, "Exercice en garde frontale")
    }

    func testVirtualPadRoundChangesSourceFocusWithoutChangingClock() throws {
        let app = application(language: "en")
        app.buttons["choose-program"].tap()
        app.buttons["Competitive"].tap()
        let day = app.buttons["lesson-competitive-w1-d4"]
        reveal(day, in: app)
        day.tap()
        app.buttons["start-workout"].tap()
        chooseRequiredMovementIfShown(app)
        let title = app.staticTexts["workout-source-title"]
        for _ in 0..<25 {
            if title.exists && title.label == "SINGLE PUNCHES" { break }
            chooseRequiredMovementIfShown(app)
            app.buttons["Skip to next"].tap()
        }
        XCTAssertEqual(title.label, "SINGLE PUNCHES")
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
        attach("virtual-pad-round-one", app: app)
        app.buttons["Skip to next"].tap()
        XCTAssertEqual(title.label, "DOUBLED-UP PUNCHES")
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
        attach("virtual-pad-round-two", app: app)
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

    func testCompletedFreestylePersistsReviewWhenNoExchangeIsDetected() throws {
        let directory = UUID().uuidString
        let app = application(language: "fr", directory: directory, zeroDetectionFreestyle: true)
        app.buttons["start-workout"].tap()
        XCTAssertTrue(app.staticTexts["workout-clock"].waitForExistence(timeout: 5))
        app.buttons["workout-toggle"].tap()
        XCTAssertTrue(app.buttons["recap-done"].waitForExistence(timeout: 8))
        let pending = app.staticTexts["Retour en attente. Ta reprise est enregistrée sur ce téléphone."]
        reveal(pending, in: app)
        XCTAssertTrue(pending.exists)
        app.buttons["recap-done"].tap()
        app.terminate()
        app.launch()
        let saved = app.buttons["saved-session-freestyle-1-10-0-v1"]
        reveal(saved, in: app)
        saved.tap()
        reveal(pending, in: app)
        XCTAssertTrue(pending.exists)
    }

    func testChangedConditioningChoicePersistsInRecapAndSavedReview() throws {
        for language in ["en", "fr"] {
            let directory = UUID().uuidString
            let app = application(language: language, directory: directory, activityFixture: true)
            app.buttons["start-workout"].tap()
            let chooser = app.buttons["workout-activity-choice"]
            XCTAssertTrue(chooser.waitForExistence(timeout: 5))
            let pickerTitle = app.navigationBars[language == "fr" ? "Choisir le mouvement" : "Choose movement"]
            if !pickerTitle.exists { chooser.tap() }
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Squats,")).firstMatch.tap()
            XCTAssertTrue(chooser.label.contains("Squats"))
            let toggle = app.buttons["workout-toggle"]
            if toggle.label.contains(language == "fr" ? "Commencer" : "Start") { toggle.tap() }
            let twoSeconds = NSPredicate(format: "label != %@ AND label != %@", "00:00", "00:01")
            expectation(for: twoSeconds, evaluatedWith: app.staticTexts["workout-clock"])
            waitForExpectations(timeout: 6)
            chooser.tap()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Burpees,")).firstMatch.tap()
            XCTAssertTrue(chooser.label.contains("Burpees"))
            Thread.sleep(forTimeInterval: 2.1)
            app.buttons["skip-segment"].tap()
            XCTAssertTrue(app.buttons["recap-done"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "candidate reps")).firstMatch.exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "répétitions candidates")).firstMatch.exists)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", language == "fr" ? "Squats · 0 répétitions candidates ·" : "Squats · 0 candidate reps ·")).firstMatch.exists)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", language == "fr" ? "Burpees · durée seulement" : "Burpees · time only")).firstMatch.exists)
            let viewLog = app.buttons["recap-view-log"]
            reveal(viewLog, in: app)
            viewLog.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", language == "fr" ? "Burpees · durée seulement" : "Burpees · time only")).firstMatch.waitForExistence(timeout: 3))
            app.terminate()
            let reopened = application(language: language, directory: directory, activityFixture: true)
            let saved = reopened.buttons["saved-session-activity-choice-ui-v1"]
            reveal(saved, in: reopened)
            saved.tap()
            XCTAssertTrue(reopened.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", language == "fr" ? "Burpees · durée seulement" : "Burpees · time only")).firstMatch.waitForExistence(timeout: 3))
            reopened.terminate()
        }
    }

    func testBasicDayOneCompletesEverySourceSegmentWithoutSkipping() throws {
        let directory = UUID().uuidString
        let app = application(language: "en", directory: directory, acceleratedSource: true)
        app.buttons["choose-program"].tap()
        app.buttons["lesson-basic-w1-d1"].tap()
        app.buttons["start-workout"].tap()

        // A required manual slot cannot be marked complete while it is still generic.
        XCTAssertTrue(app.buttons["complete-manual-step"].waitForExistence(timeout: 5))
        app.buttons["complete-manual-step"].tap()
        XCTAssertTrue(app.navigationBars["Choose movement"].waitForExistence(timeout: 3))

        var manualCompletions = 0
        let recapDone = app.buttons["recap-done"]
        let deadline = Date().addingTimeInterval(75)
        while !recapDone.exists && Date() < deadline {
            let picker = app.navigationBars["Choose movement"]
            if picker.exists {
                let choice = app.buttons["activity-choice-shoulder_circles"]
                XCTAssertTrue(choice.waitForExistence(timeout: 2))
                choice.tap()
                continue
            }
            let done = app.buttons["complete-manual-step"]
            if done.exists && done.isHittable {
                done.tap()
                manualCompletions += 1
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(recapDone.waitForExistence(timeout: 5))
        XCTAssertEqual(manualCompletions, 6)
        let summary = app.staticTexts["synthetic-receipt-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertEqual(summary.label,
            "origin=synthetic blocks=24 completed=24 segments=27 timer=2,610 skipped=0 contiguous=true receipt_blocks=24")
        XCTAssertTrue(app.staticTexts["That's a wrap."].exists)

        recapDone.tap()
        XCTAssertTrue(app.buttons["choose-program"].waitForExistence(timeout: 5))
        app.buttons["choose-program"].tap()
        let completed = app.buttons["lesson-basic-w1-d1"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("Workout completed"), completed.label)
        app.buttons["Close"].tap()
        app.terminate()
        app.launch()
        let saved = app.buttons["saved-session-basic-w1-d1"]
        reveal(saved, in: app)
        saved.tap()
        XCTAssertTrue(app.staticTexts["DYNAMIC WARM-UP:"].waitForExistence(timeout: 5))
    }

    func testSteadyStateLinkedWorkoutRunsItsExactNativeSequence() throws {
        let app = application(language: "en", acceleratedSource: true)
        app.buttons["choose-program"].tap()
        app.buttons["Competitive"].tap()
        let day = app.buttons["lesson-competitive-w1-d6"]
        reveal(day, in: app)
        day.tap()
        app.buttons["start-workout"].tap()

        completeManualSourceStep("Dynamic full-body warm-up", in: app)
        waitForSourceTitle("30-minute moderate run", in: app)
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "30:00")
        app.buttons["workout-toggle"].tap()

        waitForSourceTitle("Shadow box · Round 1 of 3", in: app)
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
        waitForTimedRest(in: app)
        waitForSourceTitle("Shadow box · Round 2 of 3", in: app)
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
        waitForTimedRest(in: app)
        waitForSourceTitle("Shadow box · Round 3 of 3", in: app)
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
        completeManualSourceStep("Static stretches", in: app)

        XCTAssertTrue(app.buttons["recap-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["That's a wrap."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "30-minute moderate run")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Shadow box · Round 3 of 3")).firstMatch.exists)
    }

    func testIntervalLinkedWorkoutRunsItsExactNativeSequence() throws {
        let app = application(language: "en", acceleratedSource: true)
        app.buttons["choose-program"].tap()
        app.buttons["Competitive"].tap()
        let day = app.buttons["lesson-competitive-w3-d6"]
        reveal(day, in: app)
        day.tap()
        app.buttons["start-workout"].tap()

        completeManualSourceStep("Dynamic full-body warm-up", in: app)
        waitForSourceTitle("Fast run · Round 1 of 6", in: app)
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
        app.buttons["workout-toggle"].tap()
        waitForTimedRest(in: app)
        for round in 2...3 {
            waitForSourceTitle("Fast run · Round \(round) of 6", in: app)
            XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
            waitForTimedRest(in: app)
        }
        for round in 4...5 {
            waitForSourceTitle("Optional fast run · Round \(round) of 6", in: app)
            XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")
            waitForTimedRest(in: app)
        }
        waitForSourceTitle("Optional fast run · Round 6 of 6", in: app)
        XCTAssertEqual(app.staticTexts["workout-clock"].label, "03:00")

        completeManualSourceStep("Walk 3-4 minutes", in: app)
        completeManualSourceStep("100-meter sprint · Round 1 of 3", in: app)
        completeManualSourceStep("Walk 1.5-2 minutes", in: app)
        completeManualSourceStep("100-meter sprint · Round 2 of 3", in: app)
        completeManualSourceStep("Walk 1.5-2 minutes", in: app)
        completeManualSourceStep("100-meter sprint · Round 3 of 3", in: app)
        completeManualSourceStep("Walk 3-4 minutes", in: app)
        completeManualSourceStep("8-15 meter shuttles · Round 1 of 3", in: app)
        waitForTimedRest(in: app)
        waitForSourceTitle("8-15 meter shuttles · Round 2 of 3", in: app)
        app.buttons["complete-manual-step"].tap()
        waitForTimedRest(in: app)
        waitForSourceTitle("8-15 meter shuttles · Round 3 of 3", in: app)
        app.buttons["complete-manual-step"].tap()
        completeManualSourceStep("Walk 3-4 minutes", in: app)
        completeManualSourceStep("Static stretches", in: app)

        XCTAssertTrue(app.buttons["recap-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["That's a wrap."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Optional fast run · Round 6 of 6")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "8-15 meter shuttles · Round 3 of 3")).firstMatch.exists)
    }
}

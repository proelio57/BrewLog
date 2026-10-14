import XCTest

/// End-to-end flows with the demo scale. The brew runs in real time (~2.5 min), so these live in their own scheme.
final class DemoBrewFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Launch arguments land in the UserDefaults argument domain:
        // demo scale, a short recipe, and always show the setup assistant.
        app.launchArguments += ["-demoScale", "YES", "-setup.recipeID", "everyday-3-pour", "-onboardingDone", "NO"]
        app.launch()
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapNext() {
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
    }

    private func dismissKeyboard() {
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    func testSetupAssistantThenDemoBrewAndReview() throws {
        // 1. Setup assistant
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        snapshot("0-welcome")
        start.tap()

        app.buttons["tile.Hario V60 02"].tap()
        snapshot("1-brewer")
        tapNext()

        let paper = app.buttons["tile.CAFEC T-90 (Medium-Dark Roast)"]
        XCTAssertTrue(paper.waitForExistence(timeout: 5))
        paper.tap()
        snapshot("2-filter")
        tapNext()

        let comandante = app.buttons["row.Comandante C40"]
        XCTAssertTrue(comandante.waitForExistence(timeout: 5))
        comandante.tap()
        let grind = app.textFields["onboarding.grind"]
        XCTAssertTrue(grind.waitForExistence(timeout: 5))
        grind.tap()
        grind.typeText("24")
        dismissKeyboard()
        snapshot("3-grinder")
        tapNext()

        let beanName = app.textFields["onboarding.beanName"]
        XCTAssertTrue(beanName.waitForExistence(timeout: 5))
        beanName.tap()
        beanName.typeText("Ethiopia Guji")
        dismissKeyboard()
        snapshot("4-beans")
        tapNext()

        snapshot("5-scale")
        tapNext()
        snapshot("6-done")
        tapNext() // Start brewing

        // 2. Choices are pre-selected on the Brew tab
        let grinderPicker = app.buttons["picker.Grinder"]
        XCTAssertTrue(grinderPicker.waitForExistence(timeout: 10))
        XCTAssertTrue(grinderPicker.label.contains("Comandante"), "got \(grinderPicker.label)")
        XCTAssertTrue(app.buttons["picker.Beans"].label.contains("Ethiopia Guji"))
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertEqual(app.textFields["grind.value"].value as? String, "24")
        snapshot("7-setup")

        // 3. Brew
        button(containing: "Start brew").tap()
        XCTAssertTrue(button(containing: "Ready").waitForExistence(timeout: 5))
        button(containing: "Ready").tap()

        // Demo scale starts pouring ~2.5 s after Ready; the timer must start automatically.
        let finish = button(containing: "Finish")
        XCTAssertTrue(finish.waitForExistence(timeout: 15), "timer should auto-start on the first pour")
        sleep(36)
        snapshot("8-brewing")
        sleep(32)
        snapshot("9-final-pour")
        sleep(45) // simulated drawdown
        finish.tap()

        // 4. Review
        let sour = button(containing: "Too sour")
        XCTAssertTrue(sour.waitForExistence(timeout: 10))
        snapshot("10a-review-chart")
        sour.tap()
        app.swipeUp()
        snapshot("10-suggestions")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'clicks'")).firstMatch.exists,
                      "grind suggestion should name a concrete setting")
        app.navigationBars.buttons["Save"].tap()

        // 5. Journal
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["Everyday 3-Pour"].firstMatch.waitForExistence(timeout: 5))
        snapshot("11-journal")
    }

    func testSkipSetupToQuickWeigh() throws {
        let justWeigh = app.buttons["onboarding.justWeigh"]
        XCTAssertTrue(justWeigh.waitForExistence(timeout: 10))
        justWeigh.tap()

        XCTAssertTrue(app.staticTexts["Quick weigh"].waitForExistence(timeout: 5))
        app.buttons["quickweigh.tare"].tap()
        XCTAssertTrue(app.staticTexts["Start pouring, the timer starts automatically"].waitForExistence(timeout: 5))
        snapshot("w-quick-weigh")
        app.buttons["quickweigh.close"].tap()

        // Setup can be done later: from the Gear tab.
        XCTAssertTrue(app.tabBars.buttons["Gear"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Gear"].tap()
        app.buttons["gear.setupAssistant"].tap()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 5))
        snapshot("w-assistant-again")
    }
}

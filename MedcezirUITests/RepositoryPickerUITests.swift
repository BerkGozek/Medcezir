import XCTest

/// Live: adds a real GitHub account, picks a repository from the list in the clone sheet, checks
/// that the URL and folder name were filled in, then removes the account again.
///
/// Opt-in only. Pass the token through the environment, never in source:
/// `TEST_RUNNER_MEDCEZIR_TEST_TOKEN=$(gh auth token) xcodebuild … test -only-testing:MedcezirUITests/RepositoryPickerUITests`
/// Screenshots go to `TEST_RUNNER_SCREENSHOT_DIR` when set (none shows the token).
@MainActor
final class RepositoryPickerUITests: XCTestCase {
    func testPickRepositoryFillsCloneForm() throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["MEDCEZIR_TEST_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_MEDCEZIR_TEST_TOKEN to run the live repository picker test")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // Always remove the account again, even when an assertion fails, so the token doesn't
        // stay in the simulator's Keychain.
        addTeardownBlock { [weak self] in self?.removeGitHubAccount(app) }
        removeGitHubAccount(app) // leftovers from an earlier failed run

        // Add the account.
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Add Account…"].firstMatch.tap()
        let tokenField = app.secureTextFields["Personal access token"]
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5))
        tokenField.tap()
        tokenField.typeText(token)
        app.navigationBars["Add Account"].buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Add Account"].waitForNonExistence(timeout: 20), "Account wasn't added")
        XCTAssertTrue(app.staticTexts["GitHub · github.com"].waitForExistence(timeout: 5))
        closeSettings(app)

        // Pick a repository from the list.
        app.buttons["Clone"].firstMatch.tap()
        let choose = app.buttons["Choose from GitHub"].firstMatch
        if !choose.waitForExistence(timeout: 5) {
            print("UI-DUMP-BEGIN\n\(app.debugDescription)\nUI-DUMP-END")
            XCTFail("No 'Choose from GitHub' row in the clone sheet")
        }
        choose.tap()
        let sandbox = app.buttons.containing(.staticText, identifier: "gitpad-test-sandbox").firstMatch
        XCTAssertTrue(sandbox.waitForExistence(timeout: 20), "Repository list didn't load")
        save(app, "picker-list", env)
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("sandbox")
            save(app, "picker-search", env)
        }
        sandbox.tap()

        let url = app.textFields.matching(NSPredicate(format: "value CONTAINS 'github.com'")).firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        XCTAssertEqual(url.value as? String, "https://github.com/BerkGozek/gitpad-test-sandbox.git")
        XCTAssertEqual(app.textFields["clone-name"].value as? String, "gitpad-test-sandbox")
        save(app, "picker-filled", env)
        app.navigationBars["Clone Repository"].buttons["Cancel"].tap()
    }

    /// Settings → swipe the GitHub account → Remove. Does nothing if there's no such account.
    private func removeGitHubAccount(_ app: XCUIApplication) {
        // Close any sheet left open by a failed step.
        for title in ["Clone Repository", "Add Account"] where app.navigationBars[title].exists {
            app.navigationBars[title].buttons["Cancel"].tap()
        }
        if !app.navigationBars["Settings"].exists {
            let settings = app.buttons["Settings"].firstMatch
            guard settings.waitForExistence(timeout: 5) else { return }
            settings.tap()
        }
        let row = app.staticTexts["GitHub · github.com"].firstMatch
        if row.waitForExistence(timeout: 3) {
            row.swipeLeft()
            app.buttons["Remove"].firstMatch.tap()
            app.buttons["Remove Account"].firstMatch.tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 5), "Account wasn't removed")
        }
        closeSettings(app)
    }

    /// Taps Done until Settings is gone (a tap during a sheet's dismiss animation is dropped).
    private func closeSettings(_ app: XCUIApplication) {
        let settings = app.navigationBars["Settings"]
        for _ in 0..<3 where settings.exists {
            settings.buttons["Done"].tap()
            if settings.waitForNonExistence(timeout: 3) { return }
        }
        XCTAssertFalse(settings.exists, "Settings didn't close")
    }

    private func save(_ app: XCUIApplication, _ name: String, _ env: [String: String]) {
        guard let directory = env["SCREENSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}

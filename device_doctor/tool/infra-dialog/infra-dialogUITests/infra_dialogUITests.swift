// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import XCTest

// An XCUITest to dismiss System Dialogs.
class infra_dialogUITests: XCTestCase {

    override func setUp() {
        // Stop immediately when a failure occurs.
        continueAfterFailure = false
        super.setUp()
    }

    func testDismissDialogs() {
        // Dismiss system dialogs, e.g. No SIM Card Installed
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // If the device has low battery or bad cable, report as infra failure.
        let failureTexts = ["Low Battery", "This accessory may not be supported"]
        let buttonTexts = ["OK", "Later", "Allow", "Remind Me Later", "Close"]

        // Sometimes a second dialog pops up when one is closed, so let's run 3 times.
        for _ in 0..<3 {
            for failureText in failureTexts {
                let predicate = NSPredicate(format: "label CONTAINS[c] %@", failureText)
                let elementQuery = springboard.staticTexts.containing(predicate)
                XCTAssertEqual(elementQuery.count, 0);
            }
            for buttonText in buttonTexts {
                let button = springboard.buttons[buttonText]
                if button.exists {
                    button.tap()
                }
            }
        }
    }
}

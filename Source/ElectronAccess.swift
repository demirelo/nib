// How Nib asks an Electron app to show its text to Accessibility.
// Electron apps build their accessibility tree only when a client asks. Most accept the switch
// AXManualAccessibility. Some, such as Signal Desktop, show nothing until they also get
// AXEnhancedUserInterface, the switch that VoiceOver uses. That second switch can make window
// animations slower in some apps, so Nib sends it only to an Electron app that the first switch did not open.

import Foundation

enum ElectronAccess {
    /// Seconds that an app gets to build its tree after the first switch, before Nib sends the second one.
    static let grace: TimeInterval = 1.0

    static func isElectron(_ bundle: URL?) -> Bool {
        guard let bundle else { return false }
        return FileManager.default.fileExists(
            atPath: bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
    }

    /// True when Nib should send AXEnhancedUserInterface now: the app is Electron, it shows no focused
    /// element, the first switch went out long enough ago, and the second switch was not sent yet.
    static func needsSecondSwitch(electron: Bool, focusFound: Bool, firstSwitchAge: TimeInterval?,
                                  secondSent: Bool) -> Bool {
        guard electron, !focusFound, !secondSent, let firstSwitchAge else { return false }
        return firstSwitchAge >= grace
    }
}

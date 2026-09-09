import Foundation
import Testing
@testable import EchnoKit

/// WCAG 2.1 AA thresholds.
private let textMinimum = 4.5
private let graphicMinimum = 3.0

@Suite("Palette contrast")
struct PaletteContrastTests {

    @Test("The contrast formula matches known WCAG values")
    func formulaIsCorrect() {
        // Black on white is 21:1 and a colour on itself is 1:1. Without these
        // the rest of this suite could pass against a formula that is wrong.
        #expect(abs(Palette.contrastRatio(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(Palette.contrastRatio(0x777777, 0x777777) - 1) < 0.01)
        // Published reference: #767676 is the lightest grey that clears 4.5:1
        // on white, and is the canonical WCAG boundary example.
        #expect(Palette.contrastRatio(0x767676, 0xFFFFFF) >= 4.5)
        #expect(Palette.contrastRatio(0x777777, 0xFFFFFF) < 4.6)
    }

    @Test("Every text colour is legible in light appearance", arguments: [
        ("brandText", Palette.brandTextLight),
        ("successText", Palette.successTextLight),
        ("warningText", Palette.warningTextLight),
        ("infoText", Palette.infoTextLight),
        ("destructive", Palette.destructiveLight)
    ])
    func textOnLightBackground(name: String, colour: UInt32) {
        // The strength meter's label and Home's role label are caption-sized, so
        // the 3:1 large-text allowance does not apply — 4.5:1 or it is a defect.
        let ratio = Palette.contrastRatio(colour, Palette.white)
        #expect(ratio >= textMinimum, "\(name) is \(String(format: "%.2f", ratio)):1 on white")
    }

    @Test("Every text colour is legible in dark appearance", arguments: [
        ("brandText", Palette.brandTextDark),
        ("successText", Palette.successTextDark),
        ("warningText", Palette.warningTextDark),
        ("infoText", Palette.infoTextDark),
        ("destructive", Palette.destructiveDark)
    ])
    func textOnDarkBackground(name: String, colour: UInt32) {
        let ratio = Palette.contrastRatio(colour, Palette.near_black)
        #expect(ratio >= textMinimum, "\(name) is \(String(format: "%.2f", ratio)):1 on near-black")
    }

    @Test("Text on the brand panel is legible", arguments: [
        ("primary", Palette.onPanelPrimary),
        ("secondary", Palette.onPanelSecondary),
        ("tertiary", Palette.onPanelTertiary),
        ("faint", Palette.onPanelFaint)
    ])
    func textOnPanel(name: String, colour: UInt32) {
        // The panel is always dark, so one ratio covers both appearances. faint
        // is the trust line — quiet, but still text somebody may need to read.
        let ratio = Palette.contrastRatio(colour, Palette.near_black)
        #expect(ratio >= textMinimum, "OnPanel.\(name) is \(String(format: "%.2f", ratio)):1 on the panel")
    }

    @Test("Fill colours clear the graphical-object threshold", arguments: [
        ("success", Palette.successLight),
        ("warning", Palette.warningLight),
        ("info", Palette.infoLight)
    ])
    func fillsOnLightBackground(name: String, colour: UInt32) {
        // Bars, icons and tinted backgrounds are graphical objects: 3:1. These
        // are deliberately more vivid than their text counterparts, which is
        // why the two are separate tokens rather than one compromise.
        let ratio = Palette.contrastRatio(colour, Palette.white)
        #expect(ratio >= graphicMinimum, "\(name) fill is \(String(format: "%.2f", ratio)):1 on white")
    }

    @Test("Text variants are darker than their fills in light appearance")
    func textVariantsAreDarker() {
        // Guards the pairing itself: if someone later sets a text token to its
        // fill value the contrast test above would catch it, but this says why.
        for (fill, text) in [(Palette.successLight, Palette.successTextLight),
                             (Palette.warningLight, Palette.warningTextLight),
                             (Palette.infoLight, Palette.infoTextLight),
                             (Palette.brandLight, Palette.brandTextLight)] {
            #expect(Palette.relativeLuminance(text) < Palette.relativeLuminance(fill))
        }
    }
}

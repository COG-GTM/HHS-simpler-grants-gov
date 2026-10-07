import SGDesign
import SGForms
import SnapshotTesting
import SwiftUI
import XCTest

/// SF-424 "Applicant information" step rendered by SGForms, for comparison with
/// `ios/Design/reference/10.png`. The content area is 390x844.
@MainActor
final class FormsSnapshotTests: XCTestCase {
    private static let layout = SwiftUISnapshotLayout.fixed(width: 390, height: 844)

    override func setUp() {
        super.setUp()
        SGFonts.registerAll()
    }

    func testSF424ApplicantInformationReferenceFields() throws {
        let sample = try FormPreviewSamples.sf424ApplicantInformation(.referenceFields)
        XCTAssertTrue(sample.errors.isEmpty)
        assertSnapshot(of: Screen(sample: sample), as: .image(layout: Self.layout))
    }

    func testSF424ApplicantInformationInvalidEmail() throws {
        let sample = try FormPreviewSamples.sf424ApplicantInformation(.invalidEmail)
        XCTAssertEqual(sample.errors.map(\.message), ["Enter a valid email address, like name@organization.org"])
        assertSnapshot(of: Screen(sample: sample), as: .image(layout: Self.layout))
    }

    func testSF424ApplicantInformationFullStepWithErrors() throws {
        let sample = try FormPreviewSamples.sf424ApplicantInformation(.fullStepEmpty)
        assertSnapshot(of: Screen(sample: sample, scrolls: false), as: .image(layout: .fixed(width: 390, height: 3000)))
    }

    func testSF424ApplicantInformationAccessibilityXXXL() throws {
        let sample = try FormPreviewSamples.sf424ApplicantInformation(.invalidEmail)
        assertSnapshot(
            of: Screen(sample: sample, scrolls: false),
            as: .image(
                layout: .fixed(width: 390, height: 2300),
                traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            )
        )
    }
}

/// Minimal stand-in for the Apply stream's form screen chrome (nav, progress,
/// header, bottom bar) so the snapshot can be compared with reference 10.
private struct Screen: View {
    let sample: FormPreviewSample
    var scrolls = true

    private var title: String { sample.stepTitle }
    private var stepIndex: Int { sample.stepIndex }
    private var stepCount: Int { sample.stepCount }

    var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            HStack {
                Text("‹ Forms").font(.custom("PublicSans-Regular", size: 17, relativeTo: .body)).foregroundStyle(navy)
                Spacer()
                Text("SF-424").font(.custom("PublicSans-SemiBold", size: 16, relativeTo: .body))
                Spacer()
                Text("\(stepIndex + 1) of \(stepCount)").font(.custom("PublicSans-Regular", size: 14, relativeTo: .body)).foregroundStyle(muted)
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            HStack(spacing: 4) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule().fill(index <= stepIndex ? navy : line).frame(height: 4)
                }
            }
            .padding(.horizontal, 20)
            ScrollView(scrolls ? .vertical : []) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Application for Federal Assistance")
                            .font(.custom("PublicSans-Regular", size: 13, relativeTo: .caption)).foregroundStyle(muted)
                        Text(title).font(.custom("SourceSerif4-SemiBold", size: 26, relativeTo: .title))
                        Text("Pre-filled from your SAM.gov registration. Check each field.")
                            .font(.custom("PublicSans-Regular", size: 14, relativeTo: .body)).foregroundStyle(muted)
                    }
                    sample.content
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            HStack(spacing: 12) {
                Text("Save draft")
                    .font(.custom("PublicSans-SemiBold", size: 17, relativeTo: .body))
                    .frame(width: 118, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.84), lineWidth: 1))
                Text("Save and continue")
                    .font(.custom("PublicSans-SemiBold", size: 17, relativeTo: .body))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(navy, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .background(Color(red: 0.965, green: 0.965, blue: 0.953))
    }

    private var navy: Color { Color(red: 0x1F / 255, green: 0x3D / 255, blue: 0x6E / 255) }
    private var muted: Color { Color(red: 0x5A / 255, green: 0x60 / 255, blue: 0x70 / 255) }
    private var line: Color { Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xDF / 255) }
}

import SGCore
import SGDesign
import SGModels
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct SubmittedView: View {
    private let applicationId: String
    private let trackingNumber: String?
    @Environment(\.grantsDataSource) private var dataSource
    @Environment(\.applyNow) private var now
    @Environment(\.timeZone) private var timeZone
    @Environment(AppRouter.self) private var router
    @State private var viewModel: SubmittedViewModel?
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var trackingFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .largeTitle) private var titleFontSize: CGFloat = 32

    public init(applicationId: String, trackingNumber: String?) {
        self.applicationId = applicationId
        self.trackingNumber = trackingNumber
    }

    public init(viewModel: SubmittedViewModel) {
        applicationId = viewModel.applicationId
        trackingNumber = viewModel.trackingNumber
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(ApplyTheme.C.green, in: Circle())
                        .accessibilityHidden(true)

                    Text("apply.submitted.title".localized(bundle: .module))
                        .font(ApplyTheme.F.serif(titleFontSize))
                        .foregroundStyle(ApplyTheme.C.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 22)
                    Text("apply.submitted.body".localized(bundle: .module))
                        .font(ApplyTheme.F.sans(16))
                        .foregroundStyle(ApplyTheme.C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    trackingCard
                        .padding(.top, 20)

                    Text("apply.submitted.status".localized(bundle: .module))
                        .font(ApplyTheme.F.sans(20, .semibold))
                        .foregroundStyle(ApplyTheme.C.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 28)
                        .padding(.bottom, 14)
                    timeline

                    Text("apply.submitted.what_happens_next".localized(bundle: .module))
                        .font(ApplyTheme.F.sans(20, .semibold))
                        .foregroundStyle(ApplyTheme.C.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 12)
                    Text("apply.submitted.next_steps".localized(bundle: .module))
                        .font(ApplyTheme.F.sans(14))
                        .foregroundStyle(ApplyTheme.C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }
            Button {
                router.popToRoot(router.tab)
                router.popToRoot(.apply)
                router.tab = .apply
            } label: {
                Text("apply.submitted.done".localized(bundle: .module))
            }
            .buttonStyle(ApplyPrimaryButtonStyle())
            .accessibilityIdentifier("apply.submitted.done")
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(ApplyTheme.C.canvas)
        }
        .background(ApplyTheme.C.canvas)
        .applyDataSourceEnvironment(dataSource)
        .toolbarHiddenForApply(hideTabBar: true)
        .task {
            guard viewModel == nil else { return }
            let vm = SubmittedViewModel(
                applicationId: applicationId,
                trackingNumber: trackingNumber,
                dataSource: ApplyDebugContext.dataSource(default: dataSource),
                now: now
            )
            viewModel = vm
            await vm.load()
        }
    }

    private var trackingCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("apply.submitted.tracking_label".localized(bundle: .module))
                    .font(ApplyTheme.F.sans(12))
                    .foregroundStyle(ApplyTheme.C.subtle)
                Text(trackingNumber ?? "apply.submitted.tracking_pending".localized(bundle: .module))
                    .font(.system(size: trackingFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ApplyTheme.C.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            if trackingNumber != nil {
                Button(action: copyTrackingNumber) {
                    Text(copied
                         ? "apply.submitted.copied".localized(bundle: .module)
                         : "apply.submitted.copy".localized(bundle: .module))
                        .font(ApplyTheme.F.sans(14, .semibold))
                        .foregroundStyle(ApplyTheme.C.navy)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("apply.submitted.copy_accessibility".localized(bundle: .module))
                .accessibilityIdentifier("apply.submitted.copy")
            }
        }
        .padding(16)
        .applyCard()
    }

    private var timeline: some View {
        let values = timelineValues
        return VStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        timelineDot(item.status)
                            .padding(.top, 3)
                        if index < values.count - 1 {
                            Rectangle()
                                .fill(ApplyTheme.C.line)
                                .frame(width: 2, height: 26)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(ApplyTheme.F.sans(15, .semibold))
                            .foregroundStyle(item.status == .upcoming ? ApplyTheme.C.subtle : ApplyTheme.C.ink)
                        Text(item.detail)
                            .font(ApplyTheme.F.sans(13))
                            .foregroundStyle(ApplyTheme.C.subtle)
                    }
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityValue(item.accessibilityStatus)
                .accessibilityIdentifier("apply.submitted.timeline.\(index)")
            }
        }
    }

    private var timelineValues: [(title: String, detail: String, status: TimelineStatus, accessibilityStatus: String)] {
        let date = viewModel?.submittedAt ?? now()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "h:mm a"
        let submittedTime = String(
            format: "apply.submitted.today_time".localized(bundle: .module),
            timeFormatter.string(from: date)
        )
        let deadline = viewModel?.closingDate
            ?? "apply.submitted.application_deadline".localized(bundle: .module)
        return [
            (
                "apply.submitted.timeline_submitted".localized(bundle: .module),
                submittedTime,
                .complete,
                "apply.submitted.timeline_completed".localized(bundle: .module)
            ),
            (
                "apply.submitted.timeline_received".localized(bundle: .module),
                "apply.submitted.timeline_received_when".localized(bundle: .module),
                .current,
                "apply.submitted.timeline_current".localized(bundle: .module)
            ),
            (
                "apply.submitted.timeline_validated".localized(bundle: .module),
                "apply.submitted.timeline_validated_when".localized(bundle: .module),
                .upcoming,
                "apply.submitted.timeline_upcoming".localized(bundle: .module)
            ),
            (
                "apply.submitted.timeline_agency_review".localized(bundle: .module),
                String(format: "apply.submitted.after_deadline".localized(bundle: .module), deadline),
                .upcoming,
                "apply.submitted.timeline_upcoming".localized(bundle: .module)
            )
        ]
    }

    private func timelineDot(_ status: TimelineStatus) -> some View {
        Circle()
            .fill(status == .complete ? ApplyTheme.C.green : .white)
            .frame(width: 14, height: 14)
            .overlay {
                Circle().stroke(
                    status == .complete ? ApplyTheme.C.green
                        : (status == .current ? ApplyTheme.C.navy : ApplyTheme.C.control),
                    lineWidth: 2
                )
            }
            .accessibilityHidden(true)
    }

    private func copyTrackingNumber() {
        guard let trackingNumber else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = trackingNumber
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

private enum TimelineStatus {
    case complete
    case current
    case upcoming
}

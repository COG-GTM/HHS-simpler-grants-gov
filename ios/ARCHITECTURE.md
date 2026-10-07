# Simpler Grants iOS (DEMO) — architecture contract

> **Demo only.** This is a demonstration app, not an official U.S. government app. It must never
> say "An official app of the United States government". Every screen shows the `DemoBanner`
> ("Demo · sample data"). No real API keys, no production endpoints, no real submissions.

This file is the contract every contributor (and every parallel work stream) codes against.
If you need to change a public interface listed here, keep it source-compatible (add, don't rename)
and note it in your PR description.

## Targets and ownership

```
ios/
  project.yml                 XcodeGen spec (app + UI test + unit test targets). Owner: shell.
  App/                        @main app, RootView, tab shell, RouteView, Info.plist,
                              Assets.xcassets, PrivacyInfo.xcprivacy, Localization. Owner: shell.
  AppUITests/                 XCUITest end-to-end + accessibility audits. Owner: tests.
  Packages/
    SGDesign/                 Theme.swift (verbatim from design handoff) + bundled fonts +
                              shared components. Owner: shell.
    SGModels/                 Codable API models, JSONValue, GrantsDataSource protocol,
                              PreviewDataSource. Owner: scaffold (then shared, additive only).
    SGCore/                   AppRouter, AppRoute, SessionStore, AppEnvironment (data mode),
                              DraftStore. Owner: shell.
    SGNetworking/             LiveDataSource (URLSession), APIClient, Keychain, Login.gov
                              (ASWebAuthenticationSession). Owner: shell.
    SGSampleData/             SampleDataSource + curated realistic JSON fixtures. Owner: sample-data.
    SGAsk/                    IntentParser + AskEngine (cited, extractive, NO LLM). Owner: ask-engine.
    SGForms/                  JSON Schema + UI schema form engine, validator, SwiftUI renderer.
                              Owner: forms.
    SGFeatureOnboarding/      Screens 01 Welcome, 02 Sign in. Owner: profile-onboarding.
    SGFeatureAsk/             Screens 03 Ask, 04 Cited answer. Owner: ask-ui.
    SGFeatureSearch/          Screens 05 Search, 06 Results, 07 Filters, 08 Opportunity detail.
                              Owner: search-ui.
    SGFeatureApply/           Screens 09 Workspace, 10 Form screen chrome, 11 Review & submit,
                              12 Submitted. Owner: apply-ui.
    SGFeatureProfile/         Screens 13 Profile & organization, 14 Roadmap & feedback.
                              Owner: profile-onboarding.
  scripts/                    start-local-api.sh / stop-local-api.sh (native, no Docker).
```

Each package is its own local Swift package (`ios/Packages/<Name>/Package.swift`), all already
registered in `project.yml`, so work streams never need to touch `project.yml` or each other's
`Package.swift`. Platforms: `.iOS(.v17)` and `.macOS(.v14)` (macOS only so pure-logic packages
run `swift test` fast). Swift tools 5.10, Swift 5 language mode.

Dependency graph (no cycles):

```
SGModels            <- everything
SGDesign            <- feature packages, SGForms
SGCore              -> SGModels, SGAsk
SGNetworking        -> SGModels, SGCore
SGSampleData        -> SGModels
SGAsk               -> SGModels
SGForms             -> SGModels, SGDesign
SGFeature*          -> SGModels, SGDesign, SGCore (+ SGAsk for Ask, SGForms for Apply)
App                 -> all
```

Feature packages must NOT import SGNetworking or SGSampleData: they get data only through
`GrantsDataSource` from the SwiftUI environment.

## Design system (SGDesign)

- `Theme.swift` is copied verbatim from the handoff: `SG.C` colors, `SG.F` fonts, `SG.R` radii,
  `SG.S` spacing, `PrimaryButton`, `Chip`, `Card`. Do not fork tokens; add new shared components in
  separate files.
- Fonts bundled (OFL): Source Serif 4 (titles, answers), Public Sans (UI). SF Mono for opportunity
  numbers, UEIs, tracking numbers. `SGFonts.registerAll()` is called once at app launch.
- Shared components (SGDesign/Components): `DemoBanner`, `GovStyleHeader` (wordmark row
  "SIMPLER.GRANTS.GOV" + avatar), `SGNavBar` (back label / title / trailing action, as in screens
  04, 10), `StatusChip(status:)` (text + color, never color-only), `InlineErrorBanner(message:retry:)`,
  `EmptyStateView(title:message:action:)`, `SGTextFieldStyle`, `SecondaryButton`.
- Accessibility: Dynamic Type via `relativeTo:` fonts, 44pt minimum targets, every icon-only
  control has an `accessibilityLabel`, status is never conveyed by color alone.
- Strings: follow the localization standard. `App/Resources/Localization/en.lproj/Localizable.strings`
  is the app's base table; packages with UI keep their own
  `Sources/<Target>/Resources/en.lproj/Localizable.strings` and use `"key".localized(bundle: .module)`
  helpers from SGDesign (`String.localized(bundle:)` → `LocalizedStringKey`/`String`). Keys are
  `snake_case`, namespaced by feature, e.g. `ask.home.title`. No user-facing literals in views
  (previews exempt).

## Data contract (SGModels)

All models are `Codable, Sendable, Hashable` and decode the real API with
`JSONDecoder.sg` (`.convertFromSnakeCase`). Dates from the API are `yyyy-MM-dd` strings for
summary dates and ISO-8601 for timestamps; keep raw `String?` fields and expose computed `Date?`.

```swift
public enum OpportunityStatus: String, Codable, Sendable, CaseIterable { case forecasted, posted, closed, archived }
public struct Opportunity            // OpportunityV1Schema: opportunityId, opportunityNumber, opportunityTitle,
                                     // agencyCode, agencyName, topLevelAgencyName, category, opportunityStatus,
                                     // summary: OpportunitySummary, opportunityAssistanceListings
public struct OpportunitySummary     // summaryDescription, isCostSharing, closeDate, postDate, archiveDate,
                                     // forecastedCloseDate, awardFloor, awardCeiling, estimatedTotalProgramFunding,
                                     // expectedNumberOfAwards, applicantTypes, fundingCategories, fundingInstruments,
                                     // applicantEligibilityDescription, agencyContactDescription,
                                     // agencyEmailAddress, additionalInfoUrl
public struct OpportunityDetail      // Opportunity fields + attachments: [OpportunityAttachment] + competitions: [Competition]
public struct Competition            // competitionId, competitionTitle, openingDate, closingDate, isOpen,
                                     // isSimplerGrantsEnabled, openToApplicants, competitionForms: [CompetitionForm]
public struct CompetitionForm        // isRequired, form: FormDefinition
public struct FormDefinition         // formId, formName, shortFormName, formVersion, formType,
                                     // formJsonSchema: JSONValue, formUiSchema: JSONValue, formRuleSchema: JSONValue?
public indirect enum JSONValue       // null, bool, number(Double), string, array, object([String: JSONValue])

public struct SearchRequest          // query, queryOperator ("AND"/"OR"), filters: SearchFilters, pagination
public struct SearchFilters          // opportunityStatus, applicantType, fundingCategory, fundingInstrument, agency
                                     // each encoded as {"one_of": [...]} and omitted when empty
public struct SearchPagination       // pageOffset (1-based), pageSize, sortOrder: [SortOrder(orderBy, sortDirection)]
public struct SearchResponse         // data: [Opportunity], paginationInfo, facetCounts: [String: [String: Int]]

public struct UserProfile            // userId, email, firstName, lastName
public struct Organization           // organizationId, samGovEntity: SamGovEntity? (uei, legalBusinessName,
                                     // expirationDate, ebizPocEmail, ebizPocFirstName, ebizPocLastName)
public struct ApplicationSummary     // UserApplicationListItemSchema
public struct Application            // applicationId, applicationName, applicationStatus, competition,
                                     // organization, applicationForms: [ApplicationForm], formValidationWarnings: JSONValue
public struct ApplicationForm        // applicationFormId, formId, form: FormDefinition, applicationResponse: JSONValue,
                                     // applicationFormStatus ("in_progress"/"complete"), isRequired, isIncludedInSubmission
public struct FormSaveResult         // warnings: [ValidationWarning] (field, message, type), form: ApplicationForm
public struct SubmissionResult       // applicationId, trackingNumber: String? (legacy_tracking_number when available)
```

```swift
public protocol GrantsDataSource: Sendable {
    func searchOpportunities(_ request: SearchRequest) async throws -> SearchResponse
    func opportunity(id: String) async throws -> OpportunityDetail
    func currentUser() async throws -> UserProfile
    func organizations() async throws -> [Organization]
    func applications() async throws -> [ApplicationSummary]
    func startApplication(competitionId: String, name: String, organizationId: String?) async throws -> String
    func application(id: String) async throws -> Application
    func form(id: String) async throws -> FormDefinition
    func saveForm(applicationId: String, formId: String, response: JSONValue) async throws -> FormSaveResult
    func submit(applicationId: String) async throws -> SubmissionResult
    func savedOpportunityIds() async throws -> Set<String>
    func setSaved(_ saved: Bool, opportunityId: String) async throws
}
public enum GrantsError: Error, Sendable, Equatable { case unauthorized, notFound, offline, server(status: Int, message: String?), decoding(String) }
public protocol Authenticating: Sendable {
    func signIn(pivRequired: Bool) async throws -> UserProfile
    func restore() async -> UserProfile?
    func signOut() async
}
```

`PreviewDataSource` (in SGModels) is a tiny in-memory implementation with 3 opportunities and one
application so every package can build previews and tests before the real data sources land.
`PreviewAuthenticator` implements `Authenticating`, waits about 0.3 seconds on sign-in, then returns
the demo user Dana Reyes (`dana.reyes@example.org`); restore returns no user and sign-out is a no-op.

Implementations:
- `SampleDataSource` (SGSampleData) — **default for the demo.** Curated, realistic but clearly
  fictional listings ("Sample data"), in-memory application state, deterministic.
- `LiveDataSource` (SGNetworking) — talks to the local API from `ios/scripts/start-local-api.sh`
  (`http://127.0.0.1:8080`). Auth: `X-SGG-Token` (JWT from mock Login.gov) or the local dummy key
  `X-API-Key: local-dev-api-key`. Never a real key.

Selected by `AppEnvironment.dataMode` (`.sample` default, `.live(baseURL:)`), overridable with launch
arguments `-SGDataMode live -SGAPIBaseURL http://127.0.0.1:8080` and `-SGUITestToken <jwt>`.
The app uses `SampleAuthenticator` in sample mode and `LoginGovAuthenticator` in live mode.
`-SGUITestToken` is passed to the live data source and authenticator; when present,
`LoginGovAuthenticator.restore()` restores the user through the live data source without starting
interactive sign-in.

## Ask (SGAsk) — no LLM

```swift
public struct ParsedIntent: Sendable, Hashable { public var searchQuery: String; public var inferredFilters: [InferredFilter] }
public struct InferredFilter: Sendable, Hashable, Identifiable { kind: Kind (.applicantType/.fundingCategory/.status), value: String, label: String, matchedTerm: String }
public struct AskAnswer: Sendable, Hashable { question, intent: ParsedIntent, paragraphs: [AnswerParagraph], citations: [Citation], totalMatches: Int }
public struct AnswerParagraph: Sendable, Hashable { public var segments: [AnswerSegment] }   // segment: text + citationIndex?
public struct Citation: Sendable, Hashable, Identifiable { index: Int (1-based), opportunity: Opportunity }
public protocol AskAnswering: Sendable { func answer(_ question: String, removing: Set<InferredFilter>) async throws -> AskAnswer }
public struct AskEngine: AskAnswering { public init(dataSource: any GrantsDataSource) }
```

Invariants: every sentence that states a fact about a listing carries that listing's citation; no
answer is rendered with zero citations (empty result → `paragraphs == []`, UI shows the empty
state); answer text uses only fields present in the listing.

## Forms (SGForms)

```swift
public struct FormModel: Sendable { public init(definition: FormDefinition) throws; public var sections: [FormSection] }
public struct FormSection: Sendable, Identifiable { id, title, fields: [FormField] }
public struct FieldError: Sendable, Hashable { path: String, message: String }
public enum FormValidator { public static func validate(_ values: JSONValue, section: FormSection, model: FormModel) -> [FieldError] }
public struct FormSectionView: View { public init(section: FormSection, values: Binding<JSONValue>, errors: [FieldError], prefill: [String: String]) }
```

Validation runs on "Save and continue", never per keystroke. Unsupported widgets render a
"Finish this part on Simpler.Grants.gov" row instead of crashing.

## Navigation (SGCore)

```swift
public enum AppTab: Hashable, Sendable { case ask, search, apply, profile }
public enum AppRoute: Hashable, Sendable {
    case answer(question: String)
    case results(SearchRequest)
    case opportunity(id: String)
    case application(id: String)
    case form(applicationId: String, formId: String)
    case review(applicationId: String)
    case submitted(applicationId: String, trackingNumber: String?)
    case roadmap
}
@Observable public final class AppRouter { public var tab: AppTab; public func push(_: AppRoute, in: AppTab?); public func popToRoot(_: AppTab) }
```

`SessionStore` is `@Observable`, initialized with `any Authenticating`, and exposes `state`,
`lastError: GrantsError?`, `signIn(pivRequired:) async`, `continueAsGuest()`, `signOut() async`,
and `restore() async`. Its `SessionState` is signed out, guest, or signed in with a `UserProfile`.
Inject it with `.environment(sessionStore)`.

`App/RouteView.swift` maps each `AppRoute` to the feature package view. Feature packages expose
the public views named in `RouteView` from day one (scaffold stubs), so later work only replaces bodies.

## Testing

- Pure packages: `swift test` (SGModels, SGAsk, SGForms, SGSampleData) — fast, run on macOS.
- App: `xcodebuild test -scheme SimplerGrants -destination 'platform=iOS Simulator,name=iPhone 17'`.
- Snapshot tests (swift-snapshot-testing) for all 14 screens at 390x844, light mode, plus XXXL type.
- XCUITest: sample-mode full flow, live-mode flow against the local API, `performAccessibilityAudit()`.
- Design references (rendered from the HTML handoff at 390x844): `ios/Design/reference/01.png` … `14.png`.

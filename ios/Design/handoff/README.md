# Handoff: Simpler.Grants.gov iOS app (SwiftUI)

## Overview
A native iPhone app for Simpler.Grants.gov. Users ask a plain-language question to find federal funding (the pattern follows america.gov), browse and filter opportunities, read a listing, and complete and submit an application for their organization. Backend: the forked repo `COG-GTM/HHS-simpler-grants-gov` (its API lives in `/api`).

## About the design files
The files in `design/` are **design references built in HTML**. They are working prototypes that show the intended look and behavior. They are not production code. Rebuild them natively in **SwiftUI** (iOS 17+, Swift 5.9+, `@Observable`, `NavigationStack`). Don't embed or wrap the HTML.

To view them, open `design/Simpler Grants iOS.dc.html` in a browser (keep `support.js` next to it). It shows one clickable prototype and all 14 screens, numbered 01–14. `design/GrantsApp.dc.html` holds the whole app: the markup for each screen sits in an `<sc-if value="{{ is.<screen> }}">` block, and sample data and state logic are in the `<script>` class at the bottom.

## Fidelity
**High fidelity.** Colors, type, spacing, radii and copy are final. Match them using `Theme.swift`. Use native iOS controls where they behave the same: `NavigationStack` back buttons, `.sheet` with detents, `TabView`, `TextField`, `Toggle`. The status bar, home indicator and device bezel in the HTML are mock-ups only; don't draw them.

## App structure
- **Root.** If the user isn't signed in and hasn't skipped, show onboarding (01). Otherwise show a `TabView` with four tabs:
  - **Ask** (icon: speech bubble, `bubble.left`)
  - **Search** (`magnifyingglass`)
  - **Apply** (`doc.text`)
  - **Profile** (`person.circle`)
- **Tab bar.** Background `#FAFAF8` at 94% opacity with a 1pt top border in `#E4E4DF`. Labels are 10pt Medium. The active tab is `#1F3D6E`; inactive tabs are `#8A8F99`.
- **Hidden tab bar.** These screens are pushed on top and hide the tab bar (`.toolbar(.hidden, for: .tabBar)`): Answer, Opportunity detail, SF-424 form, Review, Submitted, Roadmap.
- **Screen frame.** Background `#F6F6F3`, 20pt horizontal margins. Tab root screens use a custom serif large title (34pt Source Serif 4 SemiBold), not the system large title.

## Screens

### 01 Welcome (onboarding)
- **Gov banner, top.** A 16×11 flag glyph (use an asset) plus "An official app of the United States government", 12pt, `#5A6070`.
- **Hero image.** 290pt tall, corner radius 24. Placeholder for now; supply a real photo.
- **Overline.** "SIMPLER.GRANTS.GOV", 12pt SemiBold, tracking 0.08em, `#1F3D6E`. 28pt above it.
- **Heading.** "Find federal funding by asking a question.", serif 34 / 1.1.
- **Body.** "Search every opportunity on Grants.gov, see if you're eligible, and apply for your organization in one place.", 16 / 1.5, `#5A6070`.
- **Page dots.** Active dot is 18×6 in navy; the others are 6×6 in `#D5D5D0`. This is a single page for now; a paged `TabView` is optional.
- **Buttons.**
  - Primary: "Sign in with Login.gov". 54pt tall, radius 16, navy fill, white 17pt SemiBold text. Opens 02.
  - Text button: "Continue without an account". 50pt tall, navy 16pt SemiBold. Goes to the Ask tab as a guest.

### 02 Sign in sheet
- **Presentation.** `.sheet`, `.presentationDetents([.large])`, white background.
- **Header row.** "Sign in" (17 SemiBold) on the left, "Cancel" (navy, 17 Medium) on the right.
- **Logo tile.** 60×60, radius 16, `#E8EDF5`. Use the Login.gov logo.
- **Title.** "Sign in to Simpler.Grants.gov", serif 28.
- **Body.** Two paragraphs, 16 / 1.5, muted. Copy is verbatim from simpler.grants.gov:
  - "Simpler.Grants.gov uses Login.gov to verify your identity and manage your account securely. You don't need a separate username or password for this site."
  - "You'll be redirected to Login.gov to sign in or create an account. Then, you'll return to Simpler.Grants.gov as a signed-in user."
- **Buttons, pinned to the bottom.**
  - Primary: "Continue to Login.gov". Starts `ASWebAuthenticationSession` against the API's login route (`/api/auth/login` on the web app). Check the callback scheme against the repo.
  - Text button: "Agency staff: sign in with PIV/CAC". Uses the same flow with `?piv_required=true`.

### 03 Ask (home, Ask tab root)
- **Top row.**
  - Left: overline "SIMPLER.GRANTS.GOV".
  - Right: 36pt avatar circle in `#E8EDF5` with navy initials (13 SemiBold). Tapping it opens the Profile tab.
- **Heading.** 40pt below the top row. "What do you need funding for?", serif 34.
- **Subhead.** "Describe your project or organization. Answers come only from official Grants.gov listings.", 15 / 1.5, muted.
- **Question card.**
  - Container: 24pt top margin, white, 1pt `#E4E4DF` border, radius 22, padding 16/16/12, shadow `0 8 24 -16 rgba(20,23,31,.25)`.
  - Field: multiline `TextField(axis: .vertical)`, 3 lines, 17 / 1.4.
  - Placeholder: "e.g. We run a rural clinic and want to expand addiction treatment".
  - Bottom row, left: a context chip ("Eligibility: Nonprofit"), 32pt tall, `#F6F6F3` fill, 13pt muted. It's filled from the user's organization type.
  - Bottom row, right: 40pt navy circular send button with a white up-arrow. Return also submits.
- **"Try asking" list.** Heading is 13 SemiBold, muted. Each row: 16pt text, a "›" chevron in `#8A8F99`, 15pt vertical padding, hairline dividers in `#E4E4DF`. Tapping a row submits it as the question.
  - "Grants for a rural health clinic"
  - "Arts funding for a small nonprofit"
  - "Climate resilience projects for my city"
  - "Research funding for early-career scientists"
- **Application-in-progress card.** Shown only if a draft exists. Navy fill, white text, radius 18, padding 18.
  - Overline "APPLICATION IN PROGRESS" at 80% opacity.
  - Opportunity title, serif 18.
  - Bottom row: "{n} of 6 forms · Due Dec 12" (14pt, 85% opacity) and a white capsule button "Continue" (34pt, navy text) that opens Apply.

### 04 Answer (pushed from Ask)
- **Nav bar.** Back "‹ Ask", center title "Answer", right action "New" (pops to Ask and clears the field).
- **Question bubble.** Right-aligned, max width 80%, navy fill, white 16 / 1.4 text, corner radii 20/20/6/20 (the tail is bottom-right).
- **Answer block.**
  - Overline "FROM 3 GRANTS.GOV LISTINGS", muted.
  - Paragraphs in serif 17 / 1.55. Opportunity names are SemiBold.
  - Citations are superscript numbers, 11pt SemiBold navy. Use `AttributedString` with `baselineOffset`.
- **Citation cards.** White, 1pt border, radius 16, padding 14.
  - Left: 22pt circle in `#E8EDF5` with the navy citation number.
  - Title: 15 SemiBold.
  - Meta line: "{AGENCY} · {Closes Mon D}", 13pt muted.
  - Tapping a card opens 08.
- **Disclaimer.** 12pt, `#8A8F99`: "Answers are generated from Grants.gov listings and may be incomplete. Read the full opportunity before you apply."
- **Follow-up chips.** 36pt capsules, white fill, `#D5D5D0` border, 14 Medium, single line:
  - "See all 214 results" opens 06.
  - "Am I eligible?" sends a follow-up question.
  - "Only open now" sends a follow-up question.
- **Composer.** Pinned to the bottom. 46pt capsule field "Ask a follow-up" with a send button; 1pt top border.
- **Loading state** (not in the mock). Show the question bubble immediately, then a 3-dot typing indicator until the answer streams in.

### 05 Search (Search tab root)
- **Title.** "Search", serif 34.
- **Search field.** 44pt tall, radius 12, fill `#EAEAE5`, magnifier icon, placeholder "Keyword, agency, or opportunity number". Use `.searchable` or a custom field.
- **Recent.** Section title (20 SemiBold) with a "Clear" action (navy 15).
  - Rows: clock icon, query (16pt), result count on the right (13pt, `#8A8F99`), hairline dividers.
- **Browse by category.** 2-column grid, 10pt gaps.
  - Tiles: 76pt tall, white, 1pt border, radius 16, padding 12/14.
  - Category name: 15 SemiBold, top-left. "{n} open": 13pt muted, bottom-left.
  - Categories: Health, Education, Environment, Community development, Agriculture, Science & technology, Arts & humanities, Public safety.

### 06 Results
- **Header row.** Back chevron plus a 40pt search field showing the current query.
- **Filter row.** Horizontally scrolling, scroll indicator hidden, 8pt gaps.
  - First: a dark "Filters · {n}" capsule (`#14171F` fill, white 14 SemiBold) that opens 07.
  - Then toggle chips: "Open", "Closing soon", "Forecasted". Use the `Chip` view: selected is navy fill with white text; unselected is white with a `#D5D5D0` border. Labels are always one line.
- **Meta row.** "{n} opportunities" on the left, "Sort: Close date" (navy) on the right, 13pt.
- **Result card.** White, 1pt border, radius 18, padding 16, 8pt vertical gaps, 10pt between cards.
  - Row 1: status pill (24pt tall, radius 12, 12 SemiBold; colors under Design Tokens → Status) and the opportunity number on the right (13 mono, `#8A8F99`).
  - Title: serif 18 / 1.25.
  - Agency: 14pt muted.
  - Footer: 1pt `#EFEFEA` top divider, then two stacked facts, "Closes" and "Award". Labels are 13 `#8A8F99`, values 13 SemiBold.
  - Tapping the card opens 08.

### 07 Filters sheet (over Results)
- **Presentation.** `.sheet`, `.presentationDetents([.fraction(0.76), .large])`, drag indicator visible.
- **Header.** "Reset" (navy, left), "Filters" (17 SemiBold, center), "Done" (navy SemiBold, right).
- **Groups.** Each group has an uppercase 13 SemiBold muted label, then wrapping chips (36pt, 8pt gaps; use a flow `Layout`).
  - **Eligibility:** Nonprofits, Local governments, State governments, Tribal governments, Universities, Individuals, Small businesses.
  - **Category:** Health, Education, Environment, Arts, Agriculture, Science.
  - **Funding instrument:** Grant, Cooperative agreement, Loan.
  - **Agency:** HHS, USDA, NSF, EPA, NEA, DOJ. In production, load the agency list from the API.
- **Footer button.** "Show {n} results" (primary). Update the count live via a debounced count query.

### 08 Opportunity detail
- **Nav bar.** "‹ Back" on the left. On the right, a bookmark toggle (filled navy when saved) and a Share button (`ShareLink` to the simpler.grants.gov URL).
- **Status row.** Status pill plus "{n} days left to apply" (13pt muted).
- **Title.** Serif 28 / 1.15.
- **Agency.** 15pt muted. Opportunity number in 13pt mono, `#8A8F99`.
- **Facts grid.** White card, radius 18, 2 columns. Each cell: padding 14/16, label 12pt `#8A8F99`, value 15 SemiBold, `#EFEFEA` row dividers.
  - Facts: Award ceiling, Award floor, Expected awards, Total program funding, Close date, Cost sharing.
- **Ask button.** "Ask a question about this listing": 48pt outline button (radius 14, `#D5D5D0` border, navy 15 Medium). Opens 04 with a question scoped to this listing.
- **Eligibility.** Section title (20 SemiBold) plus wrapping tags (32pt, `#E8EDF5` fill, navy 14 Medium).
- **Summary.** Section title plus serif 17 / 1.55 text in `#2A2E38`.
- **Documents.** A card with one row per attachment: 34×40 file tile with a red "PDF" label, file name (15 SemiBold), "{pages} · {size}" (13pt). Open in QuickLook.
- **Agency contact.** 15 / 1.6 text.
- **Bottom bar.** Sticky, 1pt top border, canvas at 96% opacity. Primary button "Start application" opens 09. If the opportunity can't be applied for in Simpler (check the API), show "Apply on Grants.gov" instead, opening Safari.

### 09 Apply (Apply tab root): application workspace
- **Title.** "Apply", serif 34.
- **Summary card.**
  - Opportunity number (mono 12).
  - Title (serif 19).
  - "Applying as {Organization}" (14 muted).
  - Progress bar: 6pt tall, track `#EFEFEA`, fill `#1E7A4C`.
  - Bottom row: "{done} of 6 forms complete" (13 SemiBold) on the left; "Due Dec 12 · 67 days" (13 SemiBold, red) on the right.
- **"Required forms" heading.** Plus "Saved automatically" (13 muted) on the right.
- **Forms list card.** Each row has a 24pt status circle, the form name (15 SemiBold), a state line (13pt) and a chevron.
  - Done: green fill, white ✓, state "Complete" in green.
  - In progress: 2pt navy ring, state "In progress · 2 of 5 sections" in navy.
  - Not started: 2pt `#D5D5D0` ring, state "Not started" in `#8A8F99`.
  - Forms: SF-424 Application for Federal Assistance; SF-424A Budget Information; Project Narrative; Budget Justification; Project/Performance Site Location; SF-LLL Disclosure of Lobbying Activities. In production, the form list comes from the competition's required forms in the API.
- **"Review and submit" button.** Primary.
- **Footnote.** "Only your organization's Authorized Representative can submit." (13 muted, centered).

### 10 Form (SF-424 example; one template for every form)
- **Nav bar.** "‹ Forms" on the left, form code in the center, "2 of 5" on the right.
- **Section progress.** A segmented bar below the nav: 4pt tall, 4pt gaps. Done segments are navy; remaining segments are `#E4E4DF`.
- **Header.** Eyebrow "Application for Federal Assistance" (13 muted), title "Applicant information" (serif 26), helper "Pre-filled from your SAM.gov registration. Check each field." (14 muted).
- **Fields.** 16pt apart. Each has a label (14 SemiBold) and a 48pt control (radius 12, 1pt `#D5D5D0` border, 16pt text, white).
  - Focused field: navy border plus a 3pt `#E8EDF5` outer ring.
  - Read-only field (UEI): `#F6F6F3` fill, mono value, green "Verified" tag on the right.
  - Picker field: "Type of applicant", using `Menu` or `Picker`.
  - Fields in the mock: Legal name; UEI; Type of applicant; Point of contact email; Phone.
- **Validation.** Validate on "Save and continue", not on every keystroke.
  - Invalid email: border turns red `#B42318`, and the message "Enter a valid email address, like name@organization.org" appears below in 13pt red.
- **Bottom bar.**
  - "Save draft": outline, fixed width, single line. Saves and pops.
  - "Save and continue": primary, fills the remaining width. Validates, marks the section or form complete, then advances.

### 11 Review and submit
- **Title.** "Review and submit", serif 30.
- **Context line.** "You're submitting to {Agency} on behalf of {Organization}." (15 muted).
- **Compact form list.** 20pt status circles and short states.
- **Incomplete banner.** If anything is unfinished: `#FBEDEB` fill, `#8A1C13` text, radius 14: "{n} forms still need to be completed before you can submit."
- **Certification.** A full-width tappable card with a 22pt checkbox (radius 6, 2pt border; checked is a navy fill with white ✓) and the text "I certify that the statements in this application are true, complete, and accurate to the best of my knowledge." (14 / 1.45).
- **Submit button.** "Submit application" (primary). It's disabled (`#A9B3C4`) until every form is complete and the box is checked. Confirm with Face ID or a confirmation dialog before calling the API.

### 12 Submitted
- **Success icon.** 64pt green circle with a white ✓.
- **Title.** "Application submitted", serif 32.
- **Body.** "We'll notify you as it moves through review. Keep your tracking number for your records."
- **Tracking card.** Label "Tracking number", value `GRANT14102837` in mono 17 SemiBold, and a "Copy" action (navy) that copies to the clipboard.
- **Status timeline.** 14pt dots joined by a 2pt `#E4E4DF` line. Steps:
  - Submitted: filled green.
  - Received by Grants.gov: navy ring (the current step).
  - Validated: grey ring, grey label.
  - Agency review: grey ring, grey label.
- **Done button.** Primary. Returns to Ask.

### 13 Profile (Profile tab root)
- **Title.** "Profile", serif 34.
- **Identity.** 56pt avatar, name (18 SemiBold), email (14 muted), "Verified with Login.gov" (12 SemiBold, green).
- **"ORGANIZATION" card.**
  - Organization name (serif 17) with a "Switch" action on the right.
  - 2×2 facts grid: UEI (mono), SAM.gov status ("Active to Mar 2027" in green; red if expired), Your role, Members.
- **Settings list card.** Rows: Notifications, Text size, Roadmap & feedback (opens 14), Help & support, Privacy policy. Each row has its value and "›" on the right.
- **Sign out.** Outline button with red text.
- **Footer.** 12pt `#8A8F99`, centered: "Grants.gov Support Center · 1-800-518-4726 / An official website of the U.S. Department of Health and Human Services".

### 14 Roadmap and feedback
- **Title.** "Roadmap & feedback", serif 30.
- **Intro.** "Let's build a simpler Grants.gov together. Vote on what we build next and tell us what's working."
- **Roadmap cards.**
  - Stage pill: In progress = navy tint; Planned = amber; Released = green.
  - Title: 15 SemiBold.
  - Vote button on the right: 52×56, radius 12, ▲ plus the count. Voting fills it navy with white text. Released items can't be voted on and show "—".
- **Feedback.** Multiline field (4 lines, radius 14) with placeholder "Tell us what's working (and what's not)" and a "Send feedback" button (disabled until there's text).
  - On send, replace them with a green confirmation box: "Thanks. Your feedback goes straight to the Simpler.Grants.gov team."
- **Link rows.**
  - "Email the team / simpler@grants.gov" opens a `mailto:` link.
  - "Participate in user research" opens https://ethn.io/91822.
  - "Subscribe to the newsletter" opens https://simpler.grants.gov/newsletter.

## Interactions and behavior
- **Navigation.** Use push transitions (default `NavigationStack`). Sheets 02 and 07 use the system sheet animation. No custom animations are required. Optionally, use a 0.2s ease-out for chip selection and a spring for bookmark fill.
- **Back stack.** Switching tabs keeps each tab's own stack. Tapping the active tab pops it to its root.
- **Haptics.** `.sensoryFeedback(.success)` on submit and `.selection` on chip toggles.
- **Accessibility.**
  - Support Dynamic Type: all custom fonts use `relativeTo:`. Don't fix the heights of cards that contain text.
  - Minimum tap target is 44pt.
  - Status pills need text labels, not just color.
  - VoiceOver reads citation numbers as "source 1".
  - All text-on-background pairs in the tokens meet 4.5:1 contrast.
- **Empty states** (not in the mock):
  - No results: "No opportunities match these filters" with a "Reset filters" button.
  - No applications: Apply tab shows "Start an application from any open opportunity" with a "Search opportunities" button.
- **Errors.** Show network failures as an inline banner with "Try again". Never lose a draft: save form fields locally (SwiftData) and sync them.

## State and data
Suggested `@Observable` stores:
- `SessionStore`: `user?`, `organization?`, `isGuest`, and the auth token in the Keychain.
- `AskStore`: `messages: [Message]`, `isLoading`.
  - `Message` = question, answer `AttributedString`, `citations: [OpportunitySummary]`.
  - The AI answer endpoint isn't in the upstream repo. Build it as a server-side retrieval step over the opportunity search API, return citations as opportunity IDs, and never let the client generate answers without sources.
- `SearchStore`: `query`, `statusChips: Set<Status>`, `filters: [Facet: Set<String>]`, `results`, `totalCount`, `sort`, `recentQueries` (stored locally).
- `SavedStore`: saved opportunity IDs (bookmark on 08).
- `ApplicationStore`:
  - `application`
  - `forms: [FormStatus]` (`.notStarted`, `.inProgress(section:of:)`, `.complete`)
  - `fieldValues`
  - `certified: Bool`
  - `canSubmit` = all forms complete && certified
- `RoadmapStore`: items, `votedIDs`, `feedbackSent`.

API endpoints to check against `/api` in the repo. These are the upstream simpler-grants-gov v1 routes; confirm exact paths and auth headers in the fork:
- `POST /v1/opportunities/search`: query, filters (`opportunity_status`, `applicant_type`, `funding_category`, `funding_instrument`, `agency`), pagination, sort. Returns facet counts, which drive the chip and sheet counts.
- `GET /v1/opportunities/{id}`: detail, summary, attachments.
- `/v1/users/{user_id}/saved-opportunities` and `/saved-searches`.
- Application and competition endpoints: competitions, required forms, form responses, submit. Map these to screens 09–12.

## Design tokens
Use these exactly; they're also in `Theme.swift`.

Colors:
- Ink `#14171F` · Body text `#2A2E38` · Muted `#5A6070` · Subtle `#8A8F99`
- Canvas `#F6F6F3` · Surface `#FFFFFF` · Field fill `#EAEAE5`
- Line `#E4E4DF` · Line soft `#EFEFEA` · Control border `#D5D5D0`
- Navy (primary) `#1F3D6E` · Navy pressed `#16305A` · Navy tint `#E8EDF5` · Disabled `#A9B3C4`
- Success `#1E7A4C` · Error/deadline `#B42318`
- Status (background / text):
  - Open: `#E7F3EC` / `#14583A`
  - Closing soon: `#FBEDEB` / `#8A1C13`
  - Forecasted: `#FFF3DD` / `#7A4A00`

Typography (two families, both free under the OFL from Google Fonts):
- **Source Serif 4** SemiBold for titles: 34 / 1.1 (tab roots), 30 (Review, Roadmap), 28 / 1.15 (detail, sheet), 26 (form), 18–19 / 1.25 (cards).
- **Source Serif 4** Regular, 17 / 1.55, for AI answers and summaries.
- **Public Sans**:
  - 20 SemiBold: section titles
  - 17 SemiBold: buttons
  - 16: body and rows
  - 15: secondary
  - 14: chips and helpers
  - 13: captions
  - 12 SemiBold uppercase, tracking 0.08em: overlines
  - 10 Medium: tab labels
- Monospace (SF Mono) for opportunity numbers, UEI and tracking numbers.

Spacing: 4pt grid. Screen margin 20. Gaps used: 4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 40. Section titles sit 28pt below the previous block.

Radii (use `.continuous` corners): question card 22, card 18, row/list card 16, button 16, small card/banner 14, input/search 12, pills full.

Shadows: only the Ask question card, `y 8, blur 24, spread -16, rgba(20,23,31,.25)`. Everything else uses 1pt borders.

Control heights:
- Primary button 52–54
- Text button 48–50
- Input 48
- Search field 44 (40 on Results)
- Chip 34–36
- Status pill 24
- Tab bar 49 plus the safe area

## Assets
- **Needed.** Login.gov logo, U.S. flag glyph, the Simpler.Grants.gov / Grants.gov logo (from the repo's `frontend/public` or `frontend/src` static media), and a welcome hero photo (a placeholder in the mock).
- **Icons.** Use SF Symbols: `bubble.left`, `magnifyingglass`, `doc.text`, `person.circle`, `bookmark` / `bookmark.fill`, `square.and.arrow.up`, `clock`, `chevron.right`, `arrow.up`, `checkmark`, `doc.richtext`.
- **Fonts.** Bundle Source Serif 4 and Public Sans and register them under `UIAppFonts`.
- **Sample data.** All opportunity data in the mock is sample data. Replace it with API data.

## Files
- `design/Simpler Grants iOS.dc.html`: overview canvas, clickable prototype, all 14 screens, tokens.
- `design/GrantsApp.dc.html`: the full app prototype (markup, sample data, state logic).
- `design/support.js`: runtime needed to open the HTML files locally.
- `Theme.swift`: SwiftUI color and font tokens plus the `PrimaryButton`, `Chip` and `Card` building blocks.

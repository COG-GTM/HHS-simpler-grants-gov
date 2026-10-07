# iOS demo release readiness

## Status today

The app is a demo using fictional sample data. Its bundle identifier is
`ai.cognition.demo.simplergrants`. There is no Apple Developer team yet, and
the `beta` lane intentionally stops until the required account details exist.

## Apple Developer account

Enroll the agency's legal organization in the Apple Developer Program. Apple
requires a D-U-N-S Number and verification of the legal entity. Government
entities may be eligible for a fee waiver; check eligibility with Apple.

Change the demo bundle identifier to a reverse-DNS identifier controlled by
the agency before provisioning or App Store submission.

## Signing and TestFlight

Use automatic signing with the agency's Apple Developer team. Keep the
App Store Connect API key in CI secrets, not in the repository or app. The
`beta` lane requires:

- `FASTLANE_TEAM_ID`
- `APP_STORE_CONNECT_API_KEY_KEY_ID`
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- One of `APP_STORE_CONNECT_API_KEY_KEY` or
  `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH`

Use TestFlight internal testing first, then external testing with beta app
review as required.

## App Review preparation

Verify each item against the current App Review Guidelines before submission:

- **4.2 Minimum Functionality:** the app has native SwiftUI search, filters,
  ask, and apply flows; document that it is not a web wrapper.
- **4.8 Login Services:** Login.gov is a government citizen identity system.
  Confirm whether the current guideline exemption applies.
- **5.1.1(v) Account Deletion:** accounts originate at Login.gov; explain the
  account deletion path and any responsibility of the identity provider.
- Provide reviewers with a Login.gov sandbox test account and review steps.

## Privacy, encryption and accessibility

In sample mode, the app does not collect data; the privacy nutrition label
should say **Data Not Collected**. Live mode would collect name, email address
and user ID linked to identity for app functionality. The app owner must
reassess the label before any live release.

The app accesses UserDefaults and currently needs the required-reason API
declaration `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`.
If file timestamp APIs are introduced, reassess the declaration for
`NSPrivacyAccessedAPICategoryFileTimestamp`, reason `C617.1`.

Suggested export-compliance property list value:
`ITSAppUsesNonExemptEncryption = NO` because this app uses HTTPS and standard
operating-system cryptography only. Confirm the answer against the final app.

Publish an accessibility statement and complete Apple's App Store Accessibility
Nutrition Labels. Section 508 release checklist:

- [ ] VoiceOver labels and reading order
- [ ] Dynamic Type through AX5 / XXXL
- [ ] Interactive targets at least 44 pt
- [ ] Text contrast at least 4.5:1
- [ ] Status communicated by more than colour alone
- [ ] Reduce Motion behaviour
- [ ] Keyboard and Switch Control operation
- [ ] Captions (not applicable to the current app)
- [ ] Accessibility audit in UI tests
- [ ] VPAT / Accessibility Conformance Report (ACR)

## Changes required before go-live

- Implement a production Login.gov client. The current API redirects login to
  one environment-configured `LOGIN_FINAL_DESTINATION?token=…`; the backend
  needs a native callback or universal link.
- Plan guest search access: every `/v1/opportunities` route requires
  `X-SGG-Token` or `X-API-Key`. Never embed an API key in the app. Provide a
  rate-limited backend proxy/BFF or an anonymous token strategy.
- Remove sample data, `DemoBanner` and the `(Demo)` display name.
- Configure the approved production endpoint.
- Review the real submission flow end to end.
- Complete the agency security review and Authority to Operate (ATO).
- Decide on crash reporting and its privacy disclosures.

## Running the lanes

From the repository root:

```bash
cd ios
xcodegen generate
bundle exec fastlane brand_assets
bundle exec fastlane test
bundle exec fastlane ui_test
bundle exec fastlane build_sim
bundle exec fastlane archive_unsigned
bundle exec fastlane beta
```

Use Ruby 3.4 for Bundler and Fastlane. The `beta` lane needs the App Store
Connect variables above and does not run without an Apple team.

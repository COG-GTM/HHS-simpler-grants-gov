# Simpler Grants iOS demo

This is a demonstration app, not an official U.S. government app. It uses fictional bundled sample
data by default and does not collect data or connect to production services. Live mode is limited to
the local development API; do not add real API keys, credentials, or production endpoints.

## Prerequisites

- Xcode 26 with the iOS 17+ Simulator runtime
- XcodeGen 2.46 or newer (`brew install xcodegen`)

## Generate, build, and test

From the repository root:

```bash
cd ios
xcodegen generate
xcodebuild build -scheme SimplerGrants -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -scheme SimplerGrants -destination 'platform=iOS Simulator,name=iPhone 17'
```

Generated `SimplerGrants.xcodeproj` files are ignored. The Swift packages can also be built and
tested independently from `ios/Packages/<PackageName>`.

## Data modes

The default is sample mode, backed by `SampleDataSource` and `SampleAuthenticator`. To use the local
API, pass launch arguments:

```text
-SGDataMode live -SGAPIBaseURL http://127.0.0.1:8080
```

Live mode only accepts the local loopback API. It uses the local development API key
`local-dev-api-key` unless a mock Login.gov token is supplied. `-SGUITestToken <jwt>` enables
token-based restore in live mode; use only tokens from the local mock OAuth service. To start or
stop the native local API dependencies, run `./ios/scripts/start-local-api.sh` or
`./ios/scripts/stop-local-api.sh` from the repository root. Do not use Docker or Colima for this
development setup.

For simulator UI tests or a direct launch that bypasses onboarding, pass:

```text
-SGSkipOnboarding YES
```

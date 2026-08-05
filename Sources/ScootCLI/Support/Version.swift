/// Single source of truth for the CLI's reported version. Keep in sync with
/// `CFBundleShortVersionString` in scripts/build-app.sh — both are bumped together.
enum ScootCLIVersion {
    static let string = "0.6.1"
}

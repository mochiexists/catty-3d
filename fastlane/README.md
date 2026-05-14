fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### generate_project

```sh
[bundle exec] fastlane generate_project
```

Regenerate the Xcode project from project.yml

----


## Mac

### mac screenshots

```sh
[bundle exec] fastlane mac screenshots
```

Capture macOS screenshots via UI tests (Mochi Records-style)

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Upload macOS build to TestFlight

### mac release

```sh
[bundle exec] fastlane mac release
```

Upload macOS build to App Store Connect

### mac upload_metadata

```sh
[bundle exec] fastlane mac upload_metadata
```

Push fastlane/metadata/* to App Store Connect (no binary)

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Push fastlane/screenshots/* to App Store Connect (no binary)

### mac direct_release

```sh
[bundle exec] fastlane mac direct_release
```

Build, sign, and notarize the Direct Download DMG

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

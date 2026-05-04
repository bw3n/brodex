# Brodex V1

This package is the UI-only start for Brodex V1.

It keeps the frontend source in `Sources/BrodexFrontend`.

## Build

```bash
cd /Users/jerng5/Desktop/BRODEX/V3
swift build
```

## Package as a local app

```bash
cd /Users/jerng5/Desktop/BRODEX/V3
./Scripts/package_app.sh
```

The packaging script looks for an optional repo icon at:

```text
/Users/jerng5/Desktop/BRODEX/V3/Packaging/BRODEX.png
```

If that file is missing, it generates a fallback icon automatically.

This creates:

```text
/Users/jerng5/Desktop/BRODEX/V3/dist/Brodex.app
/Users/jerng5/Desktop/BRODEX/V3/dist/Brodex.app.zip
```

The packaged app is configured as a utility app:
- no Dock icon
- menu bar icon
- notch terminal behavior preserved

## Share with friends

Upload `dist/Brodex.app.zip` to a GitHub Release. Friends can download the zip,
extract `Brodex.app`, and open it on macOS. Because this build uses ad-hoc
signing instead of a paid Apple Developer ID, macOS may ask them to use
right-click > `Open` the first time they launch it.

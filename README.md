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

The packaging script currently uses this logo source for the app icon:

```text
/Users/jerng5/Desktop/PNG/BRODEX.png
```

This creates:

```text
/Users/jerng5/Desktop/BRODEX/V3/dist/Brodex.app
```

The packaged app is configured as a utility app:
- no Dock icon
- menu bar icon
- notch terminal behavior preserved

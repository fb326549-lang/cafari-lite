# MyCar Browser

A personal-use CarPlay browser and iPhone remote touchpad, based on the MIT-licensed Cafari Lite project.

## Included in this build

- CarPlay browser using the existing separate `WKWebView` scene.
- iPhone remote pad: relative pointer movement, tap, two-finger scroll, and text entry.
- iPhone URL field: opens HTTP(S) links or searches YouTube.
- Back, forward, home, and reload controls.
- A separate phone browser remains available for YouTube sign-in and manual handoff.
- Screen mirroring and IPTV are intentionally excluded.

## Important compatibility notes

The upstream project uses the raw scene role `UIWindowSceneSessionRoleCarPlay` rather than the public CarPlay template APIs. It is an experimental implementation detail and may change in future iOS versions.

Apple's current documentation states that the CarPlay Video entitlement cannot be combined with other CarPlay entitlements on iOS 26.3 and later. The upstream example includes both audio and video keys, so that entitlement file must not be assumed to be valid for every iOS version. Apple grants entitlements per developer account; a paid developer membership alone does not grant them. Request the exact entitlement configuration from Apple before signing a CarPlay-capable build.

The remote pad sends JavaScript-generated DOM pointer/click events into the page. Websites can reject synthetic events for protected actions such as media playback or fullscreen because they are not trusted physical gestures. YouTube search/navigation and page scrolling are implemented, but tap-to-play/fullscreen must be tested on the target vehicle. The car's own touchscreen remains the fallback.

## Build verification

The `.github/workflows/ios-build.yml` workflow builds an unsigned iOS device app on a GitHub-hosted macOS runner and uploads it as an artifact. This verifies Swift compilation only. The unsigned artifact cannot be installed directly.

A usable iPhone installation requires signing with an appropriate Apple certificate and provisioning profile. A CarPlay-capable installation additionally requires the correct Apple-granted CarPlay entitlement. Signing credentials and provisioning profiles must never be committed to this repository.

Configure the bundle identifier and Apple Team ID in your own untracked `Local.xcconfig` file. Do not publish certificates, private keys, or provisioning profiles.

## Safety

Use video and remote browser controls only while parked. Location-based movement detection is best-effort and is not a substitute for vehicle safety interlocks.

## License

The upstream Cafari Lite code is MIT licensed. See LICENSE. MyCar Browser modifications are provided under the same license.

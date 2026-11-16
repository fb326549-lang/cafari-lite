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

For the iOS 26.3 target, this fork now keeps only the CarPlay Audio entitlement key as a candidate. Apple's current documentation says that CarPlay Audio allows audio-only content or video content with an audio component, and that Audio and Video entitlements cannot be combined on iOS 26.3 and later. This is a compatibility hypothesis for the all-CarPlay-screen route, not proof that Apple will grant a browser-first app the entitlement. Apple grants entitlements per developer account; paid developer membership alone does not grant them. Request approval for the exact app purpose before signing. The app's CarPlay window scene role is an undocumented implementation detail and may change in future iOS versions.

The remote pad sends JavaScript-generated DOM pointer/click events into the page. Websites can reject synthetic events for protected actions such as media playback or fullscreen because they are not trusted physical gestures. YouTube search/navigation and page scrolling are implemented, but tap-to-play/fullscreen must be tested on the target vehicle. The car's own touchscreen remains the fallback.

## Build verification

The `.github/workflows/ios-build.yml` workflow builds an unsigned iOS device app on a GitHub-hosted macOS runner and uploads it as an artifact. This verifies Swift compilation only. The unsigned artifact cannot be installed directly.

A usable iPhone installation requires signing with an appropriate Apple certificate and provisioning profile. A CarPlay-capable installation additionally requires the correct Apple-granted CarPlay entitlement. Signing credentials and provisioning profiles must never be committed to this repository.

Configure the bundle identifier and Apple Team ID in your own untracked `Local.xcconfig` file. Do not publish certificates, private keys, or provisioning profiles.

## Safety

Use video and remote browser controls only while parked. Location-based movement detection is best-effort and is not a substitute for vehicle safety interlocks.

## License

The upstream Cafari Lite code is MIT licensed. See LICENSE. MyCar Browser modifications are provided under the same license.

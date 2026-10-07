# Lekhak — two fixes before the Mac app can be checked

| | |
|---|---|
| For | The Lekhak team |
| From | TechieFlow, 2026-10-07 |
| About | Lekhak TF-003 (no Mac Catalyst driver). The driver now ships and is deployed to Lekhak; it cannot be proven on `BlogAdmin` until these two things are fixed in Lekhak. |

## In short

On the owner's Mac (macOS 27, Xcode 27), `BlogAdmin`'s Mac Catalyst build does not start, for two separate reasons. Both are in Lekhak's own project, not in the framework. Neither changes the Windows build: every file named here is used only when building for Mac Catalyst.

You can make both edits from Windows. You cannot build or test them there, because a Mac Catalyst build needs a Mac. Testing happens on the Mac afterwards; the steps are at the end. One check does run on Windows (WSL or Git Bash), because it only reads files: `bash .tfcore/utils/tf-maccatalyst-check.sh`. Today it prints a FAIL for Fix 1 and a WARN for Fix 2; when both are fixed it prints `OK`.

## Fix 1 — the app quits as soon as it opens its window

**What happens.** macOS 27 stops any UIKit app that has not adopted "scenes" at the moment it creates its first window. The crash report reads `_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` (EXC_BREAKPOINT). `source/BlogAdmin/Platforms/MacCatalyst/Info.plist` has no scene manifest. The stock `dotnet new maui` template has none either, so every MAUI app made from it has this problem on macOS 27.

**The fix.** Two small edits, both in `source/BlogAdmin/Platforms/MacCatalyst/`.

In `Info.plist`, inside the top-level `<dict>`:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
  <key>UIApplicationSupportsMultipleScenes</key><true/>
  <key>UISceneConfigurations</key>
  <dict>
    <key>UIWindowSceneSessionRoleApplication</key>
    <array>
      <dict>
        <key>UISceneConfigurationName</key><string>__MAUI_DEFAULT_SCENE_CONFIGURATION__</string>
        <key>UISceneDelegateClassName</key><string>SceneDelegate</string>
      </dict>
    </array>
  </dict>
</dict>
```

In `AppDelegate.cs`, beside the existing `AppDelegate` class:

```csharp
[Register("SceneDelegate")]
public class SceneDelegate : MauiUISceneDelegate { }
```

This is how .NET MAUI documents multi-window support; `MauiUISceneDelegate` is part of MAUI. It was checked on a small MAUI app on the owner's Mac: without it the app crashed at its first window, with it the app ran and was driven by the verifier.

## Fix 2 — macOS refuses to start the build at all

**What happens.** `open` answers "Launch failed", POSIX error 163. The build is signed locally ("ad hoc", because there is no Apple certificate on this Mac), and `Entitlements.plist` asks for `keychain-access-groups`. macOS will not start a locally signed app that asks for that permission. Removing only that permission from a copy of the app let it start (checked 2026-10-07).

**Why it is not a one-line fix.** `MacCatalystCredentialStore` (REQ-FN-141) keeps credentials through MAUI `SecureStorage`, which on Mac Catalyst needs exactly that permission. The comment in `Entitlements.plist` already says it expects the app to be signed with the owner's Apple development certificate. So this is your decision. The options:

| Option | What it means | Cost |
|---|---|---|
| **A — Sign with the owner's certificate** | The owner signs in to Xcode with the Apple account once, and the Mac Catalyst build uses a development certificate and provisioning profile (`CodesignKey`, `CodesignProvisioningProfile`). The app runs exactly as designed. | The owner has to sign in with an Apple account on that Mac. Nothing else changes. |
| **B — A Debug build without the keychain** | Debug builds use a second file, `Entitlements.Debug.plist`, identical except that it leaves out `keychain-access-groups`. In Debug, `ICredentialStore` uses a stand-in that keeps values in the app's own container instead of the keychain. Release keeps the keychain. | A small csproj condition and a Debug-only store. Credentials in Debug builds are not in the keychain, which is acceptable only for a development build. |
| **C — Leave it** | The Mac app is never checked on this Mac. | Lekhak's rule REQ-NFR-042 ("Verified means verified on both heads") cannot be met for Mac rows. |

**Our recommendation: A** if the owner is willing to sign in to Xcode on the Mac once, since it tests the app as it ships. B is the choice if the Mac must stay without an Apple account.

The csproj line for B, for reference:

```xml
<PropertyGroup Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)')) == 'maccatalyst' and '$(Configuration)' == 'Debug'">
  <CodesignEntitlements>Platforms\MacCatalyst\Entitlements.Debug.plist</CodesignEntitlements>
</PropertyGroup>
```

## One more thing seen on the Mac

After the .NET MAUI workload was updated on the Mac (2026-10-07), the old Mac build crashed while loading its precompiled code (`load_aot_module`). A clean rebuild cured it. After any workload or SDK update, rebuild the Mac head from clean (`--no-incremental`, or delete `source/BlogAdmin/bin` and `obj`).

## How to check, on the Mac, once both fixes are in

```bash
bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst
bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --appium http://localhost:4723
bash .tfcore/utils/tf-verify-boot.sh stop
```

The boot should print `BOOTED head=maccatalyst mode=appium … webview=yes`. If either problem is still there, the boot says which one, in words, and how to fix it. Because `BlogAdmin` is Blazor Hybrid, the Mac check runs without control names (the Mac never shows `data-testid` to the driver): it checks for a blank window, the error bar, overlapping controls, and keeps a picture of each screen. Each row's Remark says "names not measured on a Mac"; the control-by-control check stays with the Windows head.

When that run is clean, reply on TF-003 and the TechieFlow team will close it.

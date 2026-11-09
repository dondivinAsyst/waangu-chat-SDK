# waangu-chat

**Waangu chat (`FeatureChat`) and the kits it depends on, as one Swift package.**

![version](https://img.shields.io/badge/version-0.1.1-blue) ![platform](https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey) ![swift](https://img.shields.io/badge/swift--tools-5.9-orange) ![repo](https://img.shields.io/badge/repo-private-red)

> [!NOTE]
> **This README is an integration runbook for AI coding agents.** It tells an agent how to add waangu-chat to an **existing** iOS app: which command to run, how to read the result, what it may do alone, and when it **must stop and ask a human**. People can follow it too.

---

## Quick start: add chat to a new app

This is the path for an app that has **no chat code yet**. Follow the steps in order; each one says how to check it. Everything after this section (the two ways, the merge tool, the manual wiring) is for apps that already carry their own copy of these modules, or that need more control.

### What you get

Adding the `WaanguChatSDK` product gives the app Waangu's whole chat, not a toolkit:

| Part | What the user gets | Switch in `modules:` |
|---|---|---|
| **Messaging** | Conversations, messages, groups, channels, media, voice notes, search, contacts | always on |
| **Calls** | Voice and video calls, CallKit, screen sharing | `.calls` |
| **Status** | Stories and channels (the Updates tab) | `.status` |
| **Communities** | The Communities tab | `.communities` |
| **Payments** | Send and request money, bills, top-up, QR, split bills, cash in and out, receipts, disputes, merchant invoices, and the finance assistant | `.payments` (**off** unless you ask) |

Leave `modules:` out and you get calls, status and communities (everything except payments). A part that is off shows no entry point.

**Not included:** the other Waangu app features (wallet, ride, insurance, marketplace, consultations), location and observability (no Firebase, no Sentry). Cards, mandates, remittance, FX, credit, savings, investment and PFM have no live backend yet and stay closed: nothing is simulated.

### Step 1: Requirements

| Need | Detail |
|---|---|
| **Xcode / iOS** | Xcode 15 or newer, deployment target **iOS 17+**, `swift-tools-version: 5.9` |
| **Repo access** | The package repo is private. The machine (and any CI) needs GitHub access to it: an account with access, or a read-only deploy key. See [Package facts](#package-facts) for the URLs. |
| **Backend** | Your app id registered in Identity, with a `verify-user` webhook, **per environment** (Step 4), and the **server addresses** for each environment: chat API, chat upload, main API and MQTT broker (Step 5) |
| **Disk / time** | The first resolve downloads Mediasoup/WebRTC, GRDB, MQTT and Opus binaries: several hundred MB and a few minutes |

### Step 2: Add the package

**Xcode project:** File → Add Package Dependencies → paste the package URL (SSH, see [Package facts](#package-facts)) → rule *Up to Next Major* from `0.1.1` → add the product **`WaanguChatSDK`** to the **app target** (only that product; the other `Waangu…` products come with it).

**`Package.swift` project:**

```swift
dependencies: [
    .package(url: "ssh://git@ssh.github.com:443/dondivinAsyst/waangu-chat-SDK.git", from: "0.1.1"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "WaanguChatSDK", package: "waangu-chat-sdk"),
    ]),
]
```

**Check:** the project resolves and builds with `import WaanguChatSDK` in any file. If resolution fails, see [Troubleshooting](#troubleshooting).

> [!NOTE]
> `WaanguChatSDK` brings `WaanguFeatureChat` and every kit chat needs. `import WaanguChatSDK` alone exposes `WaanguChat`, `WaanguChatConfiguration`, `WaanguChatView` and `WaanguChatVersion`. You do not import the other modules; `modules:` takes values written as `.calls`, `.status`, `.communities`, `.payments` without naming their type.

### Step 3: Project settings (the package cannot set these for you)

**Info.plist usage texts.** iOS terminates the app the first time chat asks for a permission whose text is missing. Add the ones for the features you turn on:

| Key | Needed for | Example text |
|---|---|---|
| `NSCameraUsageDescription` | taking photos and video, video calls, scanning QR | "Chat uses the camera to take photos and make video calls." |
| `NSMicrophoneUsageDescription` | voice notes, calls | "Chat uses the microphone for voice notes and calls." |
| `NSPhotoLibraryUsageDescription` | choosing media to send | "Chat sends photos and videos you choose." |
| `NSContactsUsageDescription` | finding people you know, sharing contacts | "Chat finds your contacts who use the app." |
| `NSLocationWhenInUseUsageDescription` | sending a location | "Chat sends the location you choose." |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | live location | "Chat shares your live location while you choose to." |
| `NSFaceIDUsageDescription` | approving a payment with Face ID (when `.payments` is on) | "Face ID confirms payments." |

Write the texts in your app's own words and languages. Leave out the keys for features you turned off.

**Background modes** (Signing & Capabilities → Background Modes): `Audio` and `Voice over IP` if `.calls` is on, so a call keeps running in the background and CallKit can answer from the lock screen.

**Server addresses.** The package holds **no** server address: your app passes them in the configuration (Step 5) and gets them from your backend team. If a chat or upload address is plain `http://` and uses a host **name**, iOS App Transport Security blocks it: add an ATS exception for that host. App Transport Security does not apply to connections made to a raw IP address. The device must be able to reach the servers (for an internal network, the network or VPN).

### Step 4: Register your app in the backend

Chat does not know your users; it asks your backend.

1. Choose your **app id** (the identifier of your app in Identity).
2. Register it with `POST /api/v1/identity/chat/register-app`, once **per environment** (development, staging, production), together with a **`verify-user` webhook** on your backend. Identity calls that webhook to learn who the signed-in user is.
3. Chat then logs the user in with **your** access token sent as `Authorization: Bearer`, and the `X-App-Id` header carries your app id.

**Check:** with the app id registered, opening chat reaches the inbox. Without it, chat cannot log the user in.

### Step 5: Show the chat

```swift
import SwiftUI
import WaanguChatSDK

struct ChatScreen: View {
    var body: some View {
        WaanguChatView(
            configuration: WaanguChatConfiguration(
                appId: "<your app id>",
                chatBaseURL: "<chat API address>",
                chatUploadBaseURL: "<chat upload address>",
                mainAPIBaseURL: "<your main API address>",
                realtime: .init(host: "<mqtt host>", port: 8883, useTLS: true),
                modules: [.calls, .status, .communities]         // messaging is always on; add .payments for payments
            ),
            accessToken: { await yourApp.currentAccessToken() } // nil when nobody is signed in
        )
    }
}
```

Present it as a tab, a sheet or a full-screen cover. On first appearance it shows a progress indicator, prepares chat, connects, and then shows the chat screens. If that fails it shows a retry button (an icon: the package has no user-visible wording of its own).

**What the view does for you:** it builds one chat per process with its own database; connects realtime and sync; follows the app going to the background and back while the view is on screen.

**Configuration** (`WaanguChatConfiguration(appId:userId:chatBaseURL:chatUploadBaseURL:mainAPIBaseURL:realtime:basicAuthToken:keychainService:modules:)`):

| Parameter | Meaning | Default |
|---|---|---|
| `appId` | Your app id in Identity | required |
| `userId` | Who the user is, sent as `user_identifier` in the chat login body. Optional: with `nil` nothing is sent and Identity relies on your `verify-user` webhook alone | `nil` |
| `chatBaseURL` | The chat API address | required |
| `chatUploadBaseURL` | The chat upload address | required |
| `mainAPIBaseURL` | Your app's main API address (chat uses it for its legacy upload path and to tell which backend a local database belongs to) | required |
| `realtime` | The MQTT broker: `.init(host:port:useTLS:)` | required |
| `basicAuthToken` | Sent as `Authorization` before the user has a token; `nil` sends nothing | `nil` |
| `keychainService` | Keychain service holding chat's own session and keys | your bundle identifier |
| `modules` | Which parts of chat are on, from `.calls`, `.status`, `.communities`, `.payments` | calls, status and communities (no payments) |

**The token closure.** Chat calls `accessToken` every time it needs your token and never stores it. It returns `nil` when nobody is signed in. Chat cannot renew an expired token: your closure must return a current one, using your own login and refresh.

**Payments.** Turn them on with `modules: [.calls, .status, .communities, .payments]`. When on, the services Chat Core already serves are live and unfinished operations are saved per account on the device. The balance shown in chat comes from a wallet; an app without a wallet shows it as unavailable. Your backend still decides what each user may do.

### Step 6: Sign out

When the user **chooses** to sign out of your app:

```swift
await WaanguChat.signOutSelfManaged()
```

This disconnects chat and clears the conversations kept on the device. Remove the chat view first. **Only this call clears local data**: a session that expires or is revoked keeps the conversations, so do not call it for those. A different account or server signing in on the same device never sees the earlier person's conversations: chat detects the change and clears them.

### Step 7: Verify

- [ ] The app builds and launches; the first chat screen shows a progress indicator, then the inbox.
- [ ] The console shows `WaanguChatSDK <version>` once (the version of the package you added).
- [ ] You can send a message between two accounts, and it arrives live.
- [ ] If `.calls` is on, a call rings and the permission prompts show your texts.
- [ ] If `.payments` is on, the money entries appear in a chat.
- [ ] Signing out with `signOutSelfManaged()` and in again as another account shows only that account's chats.

### What the app still has to cover

- **Push notifications** for new messages and **incoming-call pushes (VoIP/PushKit)** are not set up by the package. Without them, messages arrive live while the app is open and recently backgrounded, not after it is closed.
- **Share to chat** (a Share extension) and **screen sharing** (a Broadcast Upload extension) are separate app targets, not part of the package.
- **Deep links** into a conversation are your app's job: the package does not register URL schemes or associated domains.
- **Login and token renewal** stay in your app.

### Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Package resolution fails: a repository access error | No GitHub access to the private repo on this machine or CI. Fix access (account or deploy key). |
| Resolution fails: version conflict on `GRDB`, `mediasoup-client-swift`, `CocoaMQTT`, Opus or Ogg | Your app pins another version of a package listed in [Package facts](#package-facts). Align the pin; do not change ours. |
| "unable to override package" | A local package in your app has the same name as this one. Rename it; the package identity is `waangu-chat-sdk`. |
| Crash the first time a screen opens | A missing Info.plist usage text (Step 3). |
| Progress indicator that never ends, or the retry icon | The token closure returned `nil`, your app id is not registered (Step 4), or the device cannot reach the servers. Check those first. |
| Crash about duplicate table registration | Chat's tables were registered twice. Use only `WaanguChatView(configuration:accessToken:)`, or, on the full form, create exactly one database. |
| Calls never ring after the app is closed | Incoming-call pushes are not covered (see above). |
| Payments entries do not show | `.payments` is not in `modules`, or the backend does not allow it for that account. |

### More control

If you need to own the database, token store, metrics or overrides, use the full form below ([the facade](#shortcut-the-waanguchat-facade-messaging-calls-optional-payments)). If you want to wire every part yourself, see [After either way: make chat run](#after-either-way-make-chat-run).

---

## Table of contents

- [Quick start: add chat to a new app](#quick-start-add-chat-to-a-new-app)
- [The two ways](#the-two-ways)
- [Agent contract](#agent-contract)
- [Package facts](#package-facts)
- [Before either way: preflight](#before-either-way-preflight)
- [Choosing the way](#choosing-the-way)
- [Way 1: Add the package](#way-1-add-the-package)
  - [1.1 Project with a `Package.swift`](#11-project-with-a-packageswift)
  - [1.2 Xcode project (no `Package.swift`)](#12-xcode-project-no-packageswift)
  - [1.3 Verify Way 1](#13-verify-way-1)
  - [1.4 When Way 1 fails](#14-when-way-1-fails)
- [Way 2: Clone + merge tool](#way-2-clone--merge-tool)
  - [2.1 Get the tool](#21-get-the-tool)
  - [2.2 Plan](#22-plan)
  - [2.3 Preview the merge](#23-preview-the-merge)
  - [2.4 Apply](#24-apply)
  - [2.5 Finish the merge](#25-finish-the-merge)
  - [2.6 Verify Way 2](#26-verify-way-2)
  - [2.7 Same-name modules that are Xcode targets](#27-same-name-modules-that-are-xcode-targets)
- [After either way: make chat run](#after-either-way-make-chat-run)
  - [R1 Configuration](#step-r1-configuration-values-e7) · [R2 Services](#step-r2-shared-services) · [R3 Database](#step-r3-database-chats-tables) · [R4 API clients](#step-r4-api-clients) · [R5 Realtime](#step-r5-realtime-mqtt) · [R6 Outbox & sync](#step-r6-outbox-and-sync)
  - [R7 makeChatDependencies](#step-r7-makechatdependencies) · [R8 Bootstrap](#step-r8-register-chat-bootstrap-order) · [R9 Session](#step-r9-session-lifecycle) · [R10 Present](#step-r10-open-and-present-chat) · [R11 Copy vs import](#step-r11-what-to-copy-what-to-import)
- [Updating later](#updating-later)
- [Hand-over to the human](#hand-over-to-the-human)
- [Escalation rules](#escalation-rules)
- [Reference](#reference)
  - [Commands](#commands)
  - [Exit codes](#exit-codes)
  - [`plan.json`](#planjson)
  - [`merge.json`](#mergejson)
  - [Classifications and decisions](#classifications-and-decisions)
  - [Error messages](#error-messages)

---

## The two ways

| | **Way 1: Add the package** | **Way 2: Clone + merge tool** |
|---|---|---|
| **What** | Declare `waangu-chat` in `Package.swift` (or Xcode → Add Package Dependencies); SwiftPM downloads chat and every kit it needs | Clone `waangu-chat`, run `Tools/module_tool.py`; it merges the app's same-name kits with ours **in place**, in the app's own `Sources/`, keeping the app's changes, and adds the chat modules next to them |
| **Use when** | **Always, for a new app.** Our modules carry the `Waangu` prefix (`WaanguCoreKit`, `WaanguSharedUI`, `WaanguNetworkKit`…), so they cannot clash with an app's own `CoreKit`, `SharedUI`… | Only an app that **already merged an older copy** (from before the prefix) and wants the tool to carry that copy forward |
| **Result** | Normal remote dependency | Merged copy inside the app's repo, on a new branch |
| **Updates** | Xcode "Update to Latest Package Versions" | Run the tool again from the new version (3-way merge) |
| **Human needed** | Only for app-specific setup | For conflicts and the items the tool lists |

> [!IMPORTANT]
> An app can contain only **one** module per name. Until version 1.0 our modules had generic names, and an app with its own `CoreKit` (etc.) could not add the package: that is why Way 2 exists. From 1.0 every module we publish is named `Waangu…`, so that clash no longer happens and **Way 1 works for every app**. Way 2 stays for apps that merged an older copy. The `WaanguChat` facade is available on Way 1 only.

---

## Agent contract

### You MUST

- **Run the preflight and `plan`** before changing anything, and base decisions on `plan.json` / `merge.json`, never on guesses.
- **Change only what the chosen way says**: in Way 2, only on the branch that `apply` creates (`waangu-chat/<version>`, in its own worktree folder).
- **Stop and ask a human** for every item in [Escalation rules](#escalation-rules).
- **Report** at the end, as described in [Hand-over to the human](#hand-over-to-the-human).

### You MUST NOT

- **Never** use Way 1 when `plan` shows any `COPY_…` or `STRANGER_LOCAL` module.
- **Never** commit, stash, reset or discard the user's uncommitted work to make a command pass. Ask the human.
- **Never** edit the merged modules (listed in `.waangu-chat/MERGE_STATE.json` → `modulePaths`) except to resolve `<<<<<<<` conflict markers.
- **Never** change a version pin (ours or the app's) to make resolution pass. That is a human decision ([E3](#escalation-rules)).
- **Never** delete or rename app modules that the report does not name.
- **Never** push to `github.com/dondivinAsyst/waangu-chat-SDK`, force-push, or merge the integration branch yourself.

---

## Package facts

| Item | Value |
|---|---|
| **Package URL (SSH)** | `git@github.com:dondivinAsyst/waangu-chat-SDK.git` |
| **Package URL (SSH over 443)** | `ssh://git@ssh.github.com:443/dondivinAsyst/waangu-chat-SDK.git` (use when port 22 times out) |
| **Package identity** | `waangu-chat-sdk` (SwiftPM takes it from the repository name; use as `package:` in `.product(...)`) |
| **Current version** | `0.1.1` |
| **Platforms** | iOS 17+ · `swift-tools-version: 5.9` (Xcode 15+) |
| **Tool** | `Tools/module_tool.py` (Python 3.9+, standard library only) |
| **Repo access** | Private: the machine needs a GitHub account with access, or a read-only deploy key |

**Products**

| Role | Products |
|---|---|
| **The chat, ready to use** | `WaanguChatSDK` (the facade: `WaanguChat`, `WaanguChatView`; brings `WaanguFeatureChat` and every kit below) |
| **The chat feature itself** | `WaanguFeatureChat` |
| **Kits** (resolved automatically) | `WaanguCoreKit`, `WaanguNetworkKit`, `WaanguDeviceKit`, `WaanguStorageKit`, `WaanguAuthKit`, `WaanguSecurityKit`, `WaanguRealtimeTransportKit`, `WaanguOpusKit`, `WaanguCallMediaKit`, `WaanguScreenShareTransport`, `WaanguPermissionKit`, `WaanguTranslationKit`, `WaanguDomainKit`, `WaanguNavigationKit`, `WaanguSharedUI` |

**External dependencies** (downloaded by SwiftPM; an app pinning other versions clashes)

| Package | Rule |
|---|---|
| `SDWebImageSwiftUI` | `from: "3.0.0"` |
| `Disk` | `from: "0.6.4"` |
| `lottie-ios` | `from: "4.4.0"` |
| `CocoaMQTT` | `from: "2.1.0"` |
| `GRDB.swift` | **`exact: "7.0.0"`** |
| `mediasoup-client-swift` | **`exact: "0.13.2"`** |
| `ogg-binary-xcframework` | `exact: "0.1.3"` |
| `opus-binary-xcframework` | `exact: "0.3.0"` |

---

## Before either way: preflight

Run every check. **Stop at the first failure.**

```bash
cd /path/to/app                                           # the app's repository root
git rev-parse --show-toplevel                             # 1. must print a path
git status --porcelain --untracked-files=no               # 2. must print NOTHING
python3 --version                                         # 3. must be 3.9 or newer
git ls-remote git@github.com:dondivinAsyst/waangu-chat-SDK.git | grep -c 'refs/tags/'   # 4. must print a number > 0
```

| Check fails | Action |
|---|---|
| 1. Not a Git repository | **Escalate (E1)** |
| 2. Uncommitted changes | **Escalate (E1)**: ask the human to commit or stash. Do not do it yourself. |
| 3. Python too old or missing | **Escalate (E1)** |
| 4. `Repository not found` | **Escalate (E1)**: no access to the private repo |
| 4. `Operation timed out` (port 22) | Use the 443 URL from [Package facts](#package-facts) everywhere |

---

## Choosing the way

**Always run `plan` first.** It is read-only and decides for you. It needs the tool, so do [2.1 Get the tool](#21-get-the-tool) even if you end up on Way 1:

```bash
git clone --branch 0.1.1 git@github.com:dondivinAsyst/waangu-chat-SDK.git ~/tools/waangu-chat
T=~/tools/waangu-chat/Tools/module_tool.py
python3 $T plan /path/to/app --out /tmp/waangu-plan
```

Read `/tmp/waangu-plan/plan.json`. Look at `modules[]` where `requiredByFeatureChat == true`, and at `externalPackages[]`. Use the **first row that matches**:

| `plan.json` shows | Go to |
|---|---|
| Any `externalPackages[].status` starts with `CONFLICT` | **Escalate (E3)** first, then re-run `plan` |
| Any `classification == "DIRTY"` (exit code 2) | **Escalate (E1)** |
| Any `evidence.kind == "xcode-framework"` | [2.7 Same-name modules that are Xcode targets](#27-same-name-modules-that-are-xcode-targets) |
| Any `classification == "STRANGER_LOCAL"` | **Escalate (E4)** |
| Any `classification` in `COPY_UNCHANGED`, `COPY_MODIFIED`, `COPY_SAME_LINEAGE` | [**Way 2**](#way-2-clone--merge-tool) |
| Every module `MISSING` (or `CANONICAL` = already installed) | [**Way 1**](#way-1-add-the-package) |

Without the tool, there is nothing to check by hand for name clashes: our modules are prefixed, so the app cannot already contain a module with the same name. A merged copy from an older version is the only reason for Way 2; `plan` reports it.

> [!NOTE]
> **The `WaanguChat` facade is a Way 1 feature, by decision (2026-11-06).** It sits on top of the package's `WaanguFeatureChat`; an app on Way 2 has merged copies of the modules as its own source, and adding the facade product would bring a second copy of the same modules. The merge tool therefore does not merge `WaanguChatSDK`. An app that wants the facade must be on Way 1: with the prefixed names, that is possible for every app. An app that stays on Way 2 wires chat by hand, with the steps in [After either way: make chat run](#after-either-way-make-chat-run).

---

## Way 1: Add the package

> [!TIP]
> Use Way 1 **only** when [Choosing the way](#choosing-the-way) sends you here: no same-name modules, no version clash.

### 1.1 Project with a `Package.swift`

**Option A (recommended): let the tool make the edit**, on a new branch and folder, with nothing committed:

```bash
python3 $T apply /path/to/app --target <Target> --out /tmp/waangu-apply
```

- `<Target>` is the app target that will show the chat.
- Add `--url ssh://git@ssh.github.com:443/dondivinAsyst/waangu-chat-SDK.git` if port 22 is blocked.
- The branch is `waangu-chat/0.1.1`; the folder is `../<repo>-waangu-chat-0.1.1` (`merge.json` → `applied.worktree`).

**Option B: make the edit yourself.** Add exactly these two lines and change nothing else:

```swift
let package = Package(
    name: "MyApp",
    platforms: [.iOS(.v17)],
    dependencies: [
        // … existing dependencies, unchanged …
        .package(url: "git@github.com:dondivinAsyst/waangu-chat-SDK.git", from: "0.1.1"),   // ← ADD
    ],
    targets: [
        .target(
            name: "<Target>",
            dependencies: [
                // … existing dependencies, unchanged …
                .product(name: "WaanguFeatureChat", package: "waangu-chat-sdk"),                  // ← ADD
            ]
        ),
        // … other targets, unchanged …
    ]
)
```

Rules for the edit:
- The `.package(...)` line goes in the **top-level** `dependencies:` of `Package(`, not inside a target.
- If `Package(` has no `dependencies:`, add one before `targets:`: `dependencies: [ .package(url: …, from: "0.1.1"), ],`
- The `.product(...)` line goes in the `dependencies:` of the target that shows chat.
- To use a kit directly too, add e.g. `.product(name: "WaanguStorageKit", package: "waangu-chat-sdk")` to that target.

Then download everything:

```bash
swift package resolve
```

### 1.2 Xcode project (no `Package.swift`)

`.pbxproj` must not be edited by an agent. **Escalate (E5)** with these exact steps for the human:

1. Xcode → **File → Add Package Dependencies…**
2. Paste `git@github.com:dondivinAsyst/waangu-chat-SDK.git`
3. Dependency Rule: **Up to Next Minor Version**, `0.1.1`
4. Tick **`WaanguChatSDK`** (the ready-to-use chat) or **`WaanguFeatureChat`** (the chat feature only), choose the app target, then **Add Package**

### 1.3 Verify Way 1

```bash
swift package resolve                                   # must exit 0
swift package show-dependencies | grep -E 'waangu-chat|grdb|mediasoup|ogg|opus'
```

Expected:
- `waangu-chat-sdk<…@0.1.1>`
- under it: `sdwebimageswiftui`, `cocoamqtt`, `ogg-binary-xcframework@0.1.3`, `opus-binary-xcframework@0.1.1`, `disk`, `mediasoup-client-swift@0.13.2`, `grdb.swift@7.0.0`, `lottie-ios`

Then go to [After either way: make chat run](#after-either-way-make-chat-run).

### 1.4 When Way 1 fails

| Error | Meaning | Action |
|---|---|---|
| Duplicate module / `multiple targets named 'WaanguCoreKit'` (or another `Waangu…` name) | The app already contains a merged copy of our modules from before the prefix (or two copies of the package) | Remove the older merged copy, or keep Way 2 and update it with the tool. An app's own `CoreKit` is **not** the cause: our module is `WaanguCoreKit` |
| `Dependencies could not be resolved` naming GRDB, mediasoup… | Version clash | **Escalate (E3)** |
| `Repository not found` / authentication | No access | **Escalate (E1)** |
| `Operation timed out` | Port 22 blocked | Use the 443 URL |

---

## Way 2: Clone + merge tool

> [!TIP]
> Use Way 2 when the app has its own modules named like ours. The tool turns "two `CoreKit`s" into **one** that contains our code **and** the app's changes. Only real conflicts need a person.

### 2.1 Get the tool

Use a **full** clone (no `--depth`), because later updates need older tags:

```bash
git clone --branch 0.1.1 git@github.com:dondivinAsyst/waangu-chat-SDK.git ~/tools/waangu-chat
T=~/tools/waangu-chat/Tools/module_tool.py
```

If `~/tools/waangu-chat` already exists:

```bash
git -C ~/tools/waangu-chat fetch --tags && git -C ~/tools/waangu-chat checkout 0.1.1
```

### 2.2 Plan

Read-only:

```bash
python3 $T plan /path/to/app --out /tmp/waangu-plan
echo "exit=$?"
```

In `plan.json`, for each required module:

| `classification` | What Way 2 will do |
|---|---|
| `MISSING` | Comes from the package |
| `COPY_UNCHANGED` | The app's copy is ours (current or older), never edited → replaced by ours |
| `COPY_MODIFIED` / `COPY_SAME_LINEAGE` | Merged: the app's changes kept, conflicts marked. A copy is recognised by **at least one non-trivial file (≥ 200 bytes) identical to a version of ours**, however much the rest changed |
| `STRANGER_LOCAL` | No non-trivial file in common with any version of ours: really unrelated code. Not merged → **E4** |
| `DIRTY` | Refused → **E1** |

Also note `hostContract` (used in [make chat run](#after-either-way-make-chat-run)) and `requiredApprovals`.

### 2.3 Preview the merge

Read-only:

```bash
python3 $T merge /path/to/app --out /tmp/waangu-merge
echo "exit=$?"
```

Read `/tmp/waangu-merge/merge.json` ([schema](#mergejson)):
- **`blockers`** non-empty → **stop**: each maps to an escalation. Do not apply.
- **`warnings`** (e.g. version clashes) → **E3**.
- **`needsPerson`**: the files that will get conflict markers, or other items for a person.
- **`decisions`**: everything that merges automatically.

### 2.4 Apply

```bash
python3 $T apply /path/to/app --target <Target> --out /tmp/waangu-apply
echo "exit=$?"
```

Add `--history /path/to/waangu-user-ios` **only if** that repository is on the machine. It gives 3-way merges with the real common ancestor, so fewer conflicts.

What happens, on branch `waangu-chat/0.1.1`, in folder `../<repo>-waangu-chat-0.1.1`, with **nothing committed** and the app's own working copy untouched:

| # | Action |
|---|---|
| 1 | Merges each same-name module **in place**, in the app's own folder (e.g. `Packages/Sources/CoreKit`): one copy, ours + the app's changes |
| 2 | Copies the chat modules the app doesn't have (`FeatureChat`, `ScreenShareTransport`, `SecurityKit`…) next to them, in the same `Sources/` |
| 3 | Edits the app's `Package.swift` with **additions only**: those modules as targets, the external packages they need (CocoaMQTT, Disk, Lottie, mediasoup, ogg, opus), dependencies our kits need on the merged targets, and `"WaanguFeatureChat"` in `<Target>`. Nothing is removed, so product names don't change and **Xcode needs no re-linking** |
| 4 | Checks the edited `Package.swift` loads (`swift package dump-package`) |
| 5 | Writes `.waangu-chat/MERGE_STATE.json` next to that `Package.swift` (version + where each module lives) for future updates |

`--layout vendor` keeps the older layout instead: a separate copy in `Vendor/waangu-chat/` used through `.package(path:)`. That layout needs Xcode re-linking.

**File merge rules**

| Situation | Result |
|---|---|
| Identical, or an older version of ours | Ours |
| Changed only by the app | App's version |
| Added by the app | Kept |
| Changed on both sides, different lines | Merged automatically |
| Changed on both sides, same lines | **Conflict markers** `<<<<<<<` |

If `apply` fails, it removes its branch and folder; the repository is unchanged. With `blockers`, it exits `2` and creates nothing.

### 2.5 Finish the merge

Work **inside the worktree** (`merge.json` → `applied.worktree`).

**Conflicts.** `needsPerson[]` items whose `outcome` starts with `CONFLICT`; paths are relative to the folder of the app's `Package.swift`.

```bash
cd <worktree>
grep -rln '^<<<<<<< ' .
```

| Conflict | Agent may |
|---|---|
| Both sides add **independent** code (different functions, cases, properties) | Keep both, remove markers |
| One side is a strict superset of the other | Keep the superset |
| Both sides change the **same logic** differently (signatures, behaviour, API, DTO fields) | **Escalate (E2)**: do not choose |

**Other `needsPerson` items:**

| `outcome` contains | Escalation |
|---|---|
| `deleted by them` / `removed by us` | **E2** |
| `binary or project file changed on both sides` | **E2** |
| `also depended on <Module>` / `imports <Module>` | **E6** |
| `declared resources` | **E6** |

**Files to re-check after each conflict.** `merge.json` → `reviewAfterConflicts[]` lists files the merge updated to **our** version that use a type from a conflicting file (`conflictFiles`). When you keep **their** side of that conflicting file, open each listed file and check it still matches that type's API (initializer labels, parameter types, members). If it doesn't, restore the app's own version of that file: `git show HEAD:<their original path> > <file>`. Real case: `RemoteImage.swift` resolved to theirs → `WalletBalanceHeroView.swift` (updated to ours) called `RemoteImage` our way and had to be restored to theirs.

**Xcode links.** If `applied.xcode` is non-empty, **escalate (E5)**: those Xcode targets must re-link the merged modules from package `waangu-chat`.

### 2.6 Verify Way 2

```bash
cd <worktree>
grep -rln '^<<<<<<< ' . && echo "CONFLICTS LEFT"      # must print nothing
cd <folder of the app's Package.swift>
swift package resolve                                   # must exit 0; a version error → E3
git -C <worktree> status --short                        # review: merged kits modified in place, chat modules added, Package.swift edited
```

Then build the app and run its tests (Xcode, or `xcodebuild` with the app's scheme). **Do not commit** unless the human asked; never merge the branch yourself. Then go to [make chat run](#after-either-way-make-chat-run).

### 2.7 Same-name modules that are Xcode targets

If the app's same-name modules are **Xcode framework targets** (not in a `Package.swift`), the tool cannot rewrite them. **Escalate (E5)** with the `plan` report. For each such target, the human:
1. Moves its app-specific changes to another module (or asks the waangu-chat maintainers to add them).
2. Deletes the target.
3. Adds the package as in [1.2](#12-xcode-project-no-packageswift).

Converting those targets into a local Swift package first makes Way 2 fully applicable.

---

## Shortcut: the `WaanguChat` facade (messaging, calls, optional payments)

> [!NOTE]
> **Way 1 (package) only, by decision.** The merge tool does not merge the `WaanguChatSDK` target and will not: see [Choosing the way](#choosing-the-way).
>
> **Modules.** Messaging is always on. `modules:` picks the rest from `ChatModule`: `.calls` (Calls tab, call buttons and call engine), `.status` (the Updates tab: statuses and channels), `.communities` (Communities tab) and `.payments`. The default is `ChatModule.standard`, which is everything except payments. A module that is off shows no entry point. Limits: turning `.calls` off does not stop an incoming call from ringing (the VoIP and CallKit managers own that); groups are not a module; the server's capability answer only applies on top of `.payments`. Example: `modules: [.calls]` is messaging and calls only.
>
> **Payments** are off unless `modules` contains `.payments`. When on, the services Chat Core already serves are live (send and request money, bills, top-up, QR reading, split bills, cash in/out, receipts, disputes, merchant invoices), and unfinished operations are saved per account in your database. Services with no live version yet (cards, mandates, remittance, FX, credit, savings, investment, PFM) stay closed: nothing is simulated. The balance shown in chat comes from the wallet, which a host without a wallet does not have, so it reads as unavailable. Your backend still decides what each user may do.

Add the `WaanguChatSDK` product. **Short form (plug and play)** — this is the whole host code:

```swift
import WaanguChatSDK

WaanguChatView(
    configuration: WaanguChatConfiguration(
        appId: "<your app id in Identity>",
        chatBaseURL: "<chat API>", chatUploadBaseURL: "<chat upload API>",
        mainAPIBaseURL: "<your main API>",
        realtime: .init(host: "<mqtt host>", port: 8883, useTLS: true)),
    accessToken: { await yourApp.currentAccessToken() }    // nil when nobody is signed in
)

// When the user chooses to sign out of your app (never on an expired session):
await WaanguChat.signOutSelfManaged()                       // clears the device's conversations
```

The view builds its own database, connects, and follows the app going to the background and back while it is on screen. `environment` (`.development`, `.staging`, `.production`) fills in the Waangu servers; the Keychain service defaults to your bundle identifier (`keychainService:` overrides it); `modules:` works as below. Your app id must be registered in Identity with a `verify-user` webhook (E7). Chat reads your token each time it needs one and never stores it; it cannot renew an expired token, so your closure must return a current one.

**Full form** — when you need to own the database, token store, metrics or overrides:

```swift
import WaanguChatSDK
import WaanguFeatureChat

let configuration = WaanguChatConfiguration(
    appId: "<your app id in Identity>",                    // (E7) registered with a verify-user webhook
    userId: nil,                                            // optional: sent as `user_identifier` on chat login
    chatBaseURL: "<chat API>", chatUploadBaseURL: "<chat upload API>",   // (E7)
    mainAPIBaseURL: "<your main API>",                      // (E7)
    realtime: .init(host: "<mqtt host>", port: 8883, useTLS: true),      // (E7)
    basicAuthToken: nil,                                    // only if your backend needs one
    keychainService: "<your keychain service>",
    modules: ChatModule.standard                            // add .payments to turn payments on
)

// Migrations are fixed when a database is created, so build it with chat's tables in it
// (add your own tables with `hostRegistrations:`), or add chat's migrations to yours.
let database = await WaanguChat.makeDatabase(hostRegistrations: [])
let chat = WaanguChat(configuration: configuration, database: database, tokenManager: authTokenManager)

await chat.prepare()                  // once, at launch
await chat.startSession()             // at launch if signed in, and after each sign-in
let coordinator = try await chat.makeCoordinator()   // then present ChatCoordinatorView(coordinator:)
await chat.appDidEnterForeground()    // from your scene-phase handling
await chat.appDidEnterBackground()
await chat.signOut()                  // the user chose to sign out: clears the device's conversations, then endSession()
await chat.endSession()               // session ended without a user choice (expired, revoked): conversations stay
```

The SDK version is `WaanguChatVersion.current` (`x.y.z` in a published release, `0.0.0-dev` in a development checkout); `prepare()` also logs it once.

Chat signs the user in with your access token (`Authorization: Bearer`) when its start screen first appears; `startSession()` does not log in, it connects what is already signed in. Call `startSession()` after `prepare()` and never before the database exists.

## After either way: make chat run

Either way makes chat **compile**. To **run**, the app's composition root (its dependency container) builds chat's services, registers chat's database and realtime topics, starts the session, and presents chat.

The reference is the Waangu app. Every snippet below is taken from it:

| Waangu app file | Role |
|---|---|
| `Waangu/App/DependencyInjection/DependencyContainer.swift` | Builds every service; `makeChatDependencies()`; `bootstrap()` |
| `Waangu/App/DependencyInjection/DependencyContainer+ChatSync.swift` | How this app builds its chat API client for sync and the flush (the adapter itself moved to `WaanguChatSDK`) |
| `Waangu/App/Realtime/Realtimeregistration.swift` | Registers chat's MQTT topics (`RealtimeAuthBridge`, which gives MQTT chat's token, moved to `WaanguChatSDK`) |
| `Waangu/App/Session/SessionManager.swift` | Login / logout / foreground / background |
| `Waangu/App/Navigation/AppCoordinator.swift` | Registers `ChatFeature`, opens and closes chat |
| `Waangu/ContentView.swift`, `Waangu/WaanguApp.swift` | Presents `ChatCoordinatorView`; publishes app lifecycle events |

> [!WARNING]
> Values marked **(E7)** are app-specific: URLs, hosts, service names, the signed-in user. **Escalate (E7)** for them. Never invent URLs, user identifiers or credentials.

### Step R1: Configuration values (E7)

Chat needs these values from the host. Waangu reads them from its `AppConfiguration`:

| Value | Used for | Waangu source |
|---|---|---|
| Chat API base URL | `ChatDependencies.apiClient`, outbox flush | `appConfiguration.chatUrl` |
| Chat upload base URL | `ChatDependencies.uploadApiClient` | `appConfiguration.chatUploadUrl` |
| Main API base URL | `ChatDependencies.mainAPIBaseURL`, `sharedFeatureUsecases` | `appConfiguration.baseURL` |
| App ID in Identity | `ChatDependencies.appId`, sent as `X-App-Id` on chat login. **Your own app's, registered in Identity with a `verify-user` webhook (E7).** Registration is done once per environment by the Platform/ops team (they hold the admin key): you give them `app_id`, `app_name` and the `verify_user_endpoint` (optionally the method, headers, allowed origins and a webhook secret). Chat login fails until this is done. Never reuse another app's | `AppConfiguration.chatAppId` |
| Realtime host, port, TLS | MQTT connection | `appConfiguration.realtimeHost / realtimePort / realtimeUsesTLS` |
| Basic auth token (if the backend needs one) | API clients | `appConfiguration.basicAuthToken` |
| Keychain service name | Tokens, signature keys | `KeychainStore(serviceName: "com.waangu.driver")` |

### Step R2: Shared services

Create each once, in the container. Everything comes from the package; nothing to copy.

```swift
import WaanguCoreKit; import WaanguDeviceKit; import WaanguNetworkKit; import WaanguStorageKit; import WaanguAuthKit
import WaanguSecurityKit; import WaanguPermissionKit; import WaanguTranslationKit; import WaanguDomainKit

let logger: AppLogger = .shared
let networkMonitor: any NetworkMonitoringProtocol = NetworkMonitor.shared
let performanceMonitor: any PerformanceMonitorProtocol = PerformanceMonitor.shared
let eventBus: any EventBusProtocol = EventBus.shared
let deviceInfoProvider: any DeviceInfoProvidingProtocol = DeviceInfoProviding()
let apiErrorMapper: any ErrorMapperProtocol = APIErrorMapper()

let keychainStore: any KeychainStoreProtocol = KeychainStore(serviceName: "<your.keychain.service>")   // (E7)
let preferenceStore: any PreferenceStoreProtocol = PreferenceStore()
lazy var appSettings: AppSettingsProtocol = AppSettings(store: preferenceStore)

// Two token stores: the app's session, and chat's own session.
lazy var tokenManager: any TokenManagerProtocol = TokenManager(keychain: keychainStore, keys: .auth)
lazy var chatTokenManager: any ChatTokenManagerProtocol = TokenManager(keychain: keychainStore, keys: .chat)
```

### Step R3: Database (chat's tables)

Chat stores conversations in SQLite (GRDB, via `StorageKit`). The host creates the store **and registers chat's tables** before chat starts.

```swift
let sqliteRegistrations: [any DatabaseRegistrable.Type] = [ChatDatabaseRegistration.self]   // + the app's own
let migrations: [any MigrationStep] = sqliteRegistrations.flatMap { $0.migrationSteps }

lazy var databaseStore: any SearchableDatabaseProtocol = DatabaseAssembly.makeSearchable(
    config: DatabaseAssembly.Config(
        engine: .sqlite,
        slowQueryThresholdMs: 16,
        metricsDelegate: DatabaseMetricsCollector.shared,
        migrationSteps: migrations
    )
)

// At bootstrap, before anything uses chat:
for registration in sqliteRegistrations {
    await DatabaseAssembly.register(registration, in: databaseStore)
}
```

### Step R4: API clients

Chat uses a **dedicated** client for its own backend and one for uploads, plus the app's main client.

```swift
func makeDedicatedAPIClient(baseURL: String) async throws -> any APIClientProtocol {
    try await APIClientFactoryProvider.makeClient(
        baseURL: baseURL,
        doctorBaseURL: nil,
        appConfiguration: appConfiguration,
        logger: logger,
        performanceMonitor: performanceMonitor,
        networkMonitor: networkMonitor,
        deviceInfoProvider: deviceInfoProvider,
        tokenManager: tokenManager,
        basicAuthToken: basicAuthToken,                  // (E7) or nil
        certificatePins: WaanguPinProvider()             // optional; inert until pins are filled
    )
}
let chatAPI   = try await makeDedicatedAPIClient(baseURL: chatURL)        // (E7)
let uploadAPI = try await makeDedicatedAPIClient(baseURL: chatUploadURL)  // (E7)
let mainAPI   = try await makeDedicatedAPIClient(baseURL: mainBaseURL)    // or the app's existing client
```

### Step R5: Realtime (MQTT)

`RealtimeAuthBridge` gives the MQTT client chat's token.

> [!IMPORTANT]
> **Way 1 (package):** `RealtimeAuthBridge` is now in the `WaanguChatSDK` product. Add that product to your target, `import WaanguChatSDK`, and use it as `RealtimeAuthBridge(tokenManager: chatTokenManager, eventBus: eventBus)`. Do not copy the code below.
> **Way 2 (merge tool):** the tool does not merge the `WaanguChatSDK` target, by decision (see Choosing the way). Copy the code below.

The code, for Way 2 (it is the same logic as the package version, without its extra error cases):

```swift
import WaanguCoreKit

/// Supplies chat's access token to the realtime client.
final class RealtimeAuthBridge: RealtimeAuthDelegate, Sendable {
    private let tokenManager: any ChatTokenManagerProtocol
    private let eventBus: any EventBusProtocol
    let tokenRefreshThreshold: TimeInterval = 90

    init(tokenManager: any ChatTokenManagerProtocol, eventBus: any EventBusProtocol) {
        self.tokenManager = tokenManager
        self.eventBus = eventBus
    }

    func realtimeClientNeedsToken() async throws -> RealtimeCredentials {
        if await tokenManager.hasValidAccessToken() || (await tokenManager.hasValidRefreshToken()),
           let token = try await tokenManager.getAccessToken() {
            return RealtimeCredentials(token: token, userId: nil, expiresAt: Self.jwtExpirationDate(from: token))
        }
        throw RealtimeError.authenticationFailed(reason: "No valid token available — session expired")
    }

    func realtimeClientDidFailAuthentication(error: RealtimeError) async {}

    /// `exp` claim of a JWT, if any.
    private static func jwtExpirationDate(from token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = 4 - b64.count % 4
        if pad < 4 { b64.append(String(repeating: "=", count: pad)) }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (json["exp"] as? TimeInterval) ?? (json["exp"] as? Int).map(TimeInterval.init)
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
```

```swift
import WaanguRealtimeTransportKit

lazy var realtimeAuthBridge = RealtimeAuthBridge(tokenManager: chatTokenManager, eventBus: eventBus)

lazy var realtimeClient: any RealtimeClientProtocol = RealtimeAssembly.make(config: RealtimeConfiguration(
    transport: .mqtt,
    host: realtimeHost, port: realtimePort, useTLS: realtimeUsesTLS,               // (E7)
    authDelegate: realtimeAuthBridge,
    deviceInfo: RealtimeDeviceInfo(
        deviceId:    deviceInfoProvider.captureDeviceContext().deviceId,
        platform:    deviceInfoProvider.captureDeviceContext().platformOS,
        appVersion:  deviceInfoProvider.captureDeviceContext().appVersion,
        deviceModel: deviceInfoProvider.captureDeviceContext().deviceModel
    ),
    networkMonitor: networkMonitor,
    deviceTier: DeviceTier(deviceInfoSnapshot: deviceInfoProvider.captureSnapshot(), logger: logger),
    performanceMonitor: performanceMonitor,
    userId: nil,
    reconnectionPolicy: .standard,
    heartbeatInterval: 15,
    maxSubscriptions: 50,
    maxPayloadSize: 256 * 1024,
    defaultMessageTTL: 3600,
    offlineQueueConfig: .default,
    metricsDelegate: RealtimeMetricsCollector.shared,
    mqttSessionExpiryInterval: 3600,
    mqttTopicAliasMaximum: 0          // REQUIRED: CocoaMQTT can't resolve inbound aliases; >0 drops messages
))

// At bootstrap: register chat's topics (Waangu: RealtimeRegistration.bootstrap).
await realtimeClient.register(ChatRealtimeRegistration.topicRegistrations)
```

> [!CAUTION]
> Keep `mqttTopicAliasMaximum: 0`. With aliases on, the broker sends empty topic names for aliased messages and they are dropped as "unsubscribed topic".

### Step R6: Outbox and sync

Chat writes outgoing actions to a local outbox, and a sync engine flushes it and pulls missed events. `DatabaseOutbox`, `FeatureSyncEngine`, `ChatSyncDelegate` and `ChatSyncRunner` are in the package.

> [!IMPORTANT]
> **Way 1 (package):** `ChatOutboxAdapter`, the flush handler and a lazy API client are now in the `WaanguChatSDK` product (`import WaanguChatSDK`):
> - `ChatOutboxAdapter(outbox: chatDatabaseOutbox)`
> - `ChatOutboxFlush.makeHandler { try await makeDedicatedAPIClient(baseURL: chatURL) }` replaces `makeChatOutboxFlushHandler()` below
> - `LazyAPIClient { try await makeDedicatedAPIClient(baseURL: chatURL) }` replaces the `ChatAPIClientProxy` mentioned in the engine below
>
> **Way 2 (merge tool):** the tool does not merge the `WaanguChatSDK` target, by decision (see Choosing the way). Copy the code below. **`ChatOutboxAdapter` and the flush handler are in the `WaanguChatSDK` target, which Way 2 does not take, so copy them** (their source is `Sources/WaanguChatSDK/Sync/ChatOutboxAdapter.swift` and `ChatOutboxFlush.swift` in this repository; the version below is the same logic):

```swift
/// Bridges `DatabaseOutbox<ChatOutboxItem>` to FeatureChat's outbox protocols.
public final class ChatOutboxAdapter: ChatOutboxEnqueuing, ChatOutboxMaintaining, @unchecked Sendable {
    private let outbox: DatabaseOutbox<ChatOutboxItem>
    public init(outbox: DatabaseOutbox<ChatOutboxItem>) { self.outbox = outbox }

    public func enqueue(_ item: ChatOutboxItem) async throws { try await outbox.enqueue(item) }

    @discardableResult
    public func settle(_ actionType: ChatOutboxItemActionType, reference: String,
                       as settlement: ChatOutboxSettlement) async -> Int {
        let key = "\(actionType.rawValue):\(reference)"
        switch settlement {
        case .acknowledged:          return await outbox.settle(key: key, success: true)
        case .rejected(let reason):  return await outbox.settle(key: key, success: false, error: reason)
        }
    }
    public func pending(olderThan age: TimeInterval) async -> [ChatOutboxItem] { await outbox.pending(olderThan: age) }
    public func noteAttempt(id: String, error: String) async { await outbox.noteAttempt(id: id, error: error) }
}

func makeChatOutboxFlushHandler() -> @Sendable ([ChatOutboxItem]) async throws -> [OutboxFlushResult] {
    { batch in
        do {
            let api = try await makeDedicatedAPIClient(baseURL: chatURL)                       // (E7)
            let response: ChatOutboxBatchResponseDTO = try await api.request(
                endpoint: HTTPChatSyncEndpoints.flushOutbox(ChatOutboxBatchRequestDTO(items: batch)))
            return response.results.map { $0.toFlushResult() }
        } catch {
            return batch.map { OutboxFlushResult(localId: $0.id, success: false, error: error.localizedDescription) }
        }
    }
}

lazy var chatDatabaseOutbox = DatabaseOutbox<ChatOutboxItem>(
    database: databaseStore, config: .default, flush: makeChatOutboxFlushHandler())
lazy var chatOutboxAdapter = ChatOutboxAdapter(outbox: chatDatabaseOutbox)

lazy var chatSyncEngine = FeatureSyncEngine(
    delegate: ChatSyncDelegate(
        fieldCrypto: FieldEncryptionService.shared,
        realtime: realtimeClient,
        outbox: chatOutboxAdapter,
        outboxMaintenance: chatOutboxAdapter
    ),
    outbox: chatDatabaseOutbox,
    apiClient: chatAPI,                         // Waangu passes a lazy proxy (ChatAPIClientProxy) because its container is not async
    database: databaseStore,
    realtime: realtimeClient,
    syncPriority: .high,
    pullConfig: .default,
    currentOwner: { CurrentSessionInfo.shared.currentUid },
    liveUpdates: false                          // REQUIRED: ChatFeature keeps its own live subscription; true applies events twice
)
lazy var chatSyncRunner = ChatSyncRunner(sync: chatSyncEngine)
```

### Step R7: `makeChatDependencies()`

`ChatDependencies` has **27 required** parameters (`appId` was added in SDK plan step 1.9; it used to be a literal inside the package). The other 53 (finance, security extras) have safe defaults: `Closed…` (feature off) and `Unavailable…`. Start with finance **off**:

```swift
import WaanguFeatureChat; import WaanguOpusKit; import WaanguCallMediaKit

func makeChatDependencies() async throws -> ChatDependencies {
    // Call video rendering is main-actor work; it can't travel inside ChatDependencies.
    await MainActor.run { CallVideoRendering.factory = MediasoupVideoRendererFactory() }

    return ChatDependencies(
        apiClient: chatAPI,                                    // Step R4
        uploadApiClient: uploadAPI,                            // Step R4
        logger: logger,
        networkMonitor: networkMonitor,
        eventBus: EventBus.shared,
        realtime: realtimeClient,                              // Step R5
        chatOutbox: chatOutboxAdapter,                         // Step R6
        chatOutboxMaintenance: chatOutboxAdapter,              // Step R6
        opusAudioService: try await OpusAudioService(logger: logger),       // create once, reuse
        opusPlaybackService: try await OpusPlaybackService(logger: logger), // create once, reuse
        permissionService: PermissionCenter.shared,
        messageConfirmationGuard: MessageConfirmationGuard(logger: logger),
        paymentConfirmationGuard: PaymentConfirmationGuard(
            logger: logger,
            verifier: HMACFinancialSignatureVerifier(keychain: keychainStore, logger: logger)),
        promptInjectionFilter: PromptInjectionFilter.shared,
        signedPushVerifier: SignedPushVerifier.shared,
        fieldEncryptionService: FieldEncryptionService.shared,
        pendingE2EEQueue: PendingE2EEQueue(),
        sharedFeatureUsecases: SharedFeatureUseCaseFactory.make(apiClient: mainAPI, errorMapper: apiErrorMapper),
        tokenManager: tokenManager,
        database: databaseStore,                               // Step R3
        searchableDatabase: databaseStore,
        deviceInfoProvider: deviceInfoProvider,
        mainAPIBaseURL: mainBaseURL,                           // (E7)
        appId: chatAppId,                                      // (E7) your app's id in Identity
        userId: nil,                                           // optional: sent as `user_identifier` on chat login
        appSettings: appSettings,
        translationService: TranslationService(locale: appSettings.languageCode.rawValue),
        chatTokenManager: chatTokenManager,
        callMediaEngine: MediasoupCallEngine()                 // optional: omit = no calls; create ONE per app
    )
}
```

> [!IMPORTANT]
> Who the chat user is: chat logs in with the host app's access token (`Authorization: Bearer`), and the chat backend (Identity) asks the app's registered `verify-user` webhook, for the app's `X-App-Id`, which user that token belongs to. The app must therefore have its `X-App-Id` registered in Identity with a working `verify-user` webhook. If chat shows another user's data or fails to log in, check that webhook first (**E7**: Identity team). The webhook must return a stable user id (`id` / `appUserId`) and the context chat needs (at least `tenantId` and `organisationId`). That id is the **global** Identity user: two apps share one inbox only if they return the same id **and** the same tenant, organisation and memberships. Conversations are not split by app id. `sharedFeatureUsecases` is still a required parameter of `ChatDependencies`, but only for the finance balance, not for identity.

**Turning finance on (optional).** On Way 1 with the facade, add `.payments` to `modules` and the facade builds all of this for you (see the facade section). On Way 2, or without the facade, Waangu does it by hand: its `DependencyContainer.makeChatOverrides()` and the facade's own code (`Facade/WaanguChat.swift`, `makeLiveFinance`) show it. It passes:
- the finance services (`financeAPIClient`, `financeCatalog`, `cashIn`, `bills`…), from `FinanceCoreLiveServices` (package) when `FinanceBackend.mode == .live`, otherwise from `FinanceDebugKit` (Waangu app target)
- `financeCapabilities: FinanceCapabilityProvider(...)`, `idempotencyPreserver: SecurityKitIdempotencyPreserver(...)`, `stepUpAuthenticator: StepUpAuthenticator(...)` (all in `SecurityKit`)
- `financialObjectPersistence: AccountScopedFinancialObjectPersistence(...)` (in the `WaanguChatSDK` target; Way 2 copies it from `Sources/WaanguChatSDK/Finance/`)

`FinanceBackend`, `FinanceLiveServicesRegistry`, `FinanceDebugKit` and `SecurityDebugKit` are **not in the package** (Waangu app only; the facade does not need the registry). Finance needs backend contracts and keys: **escalate (E7)** before enabling it.

### Step R8: Register chat, bootstrap order

```swift
// AppCoordinator (once): tell the registry how to build chat
await FeatureRegistry.shared.registerDependencies(for: ChatFeature.self, priority: ChatFeature.loadPriority) {
    try await container.makeChatDependencies()
}

// Container bootstrap: this order matters
func bootstrap() async {
    await registerSQLiteEntities()      // Step R3: chat's tables first
    await registerRealtimeTopics()      // Step R5: chat's MQTT topics
    await sessionManager.start()        // Step R9: connects realtime + sync if already logged in
}
```

### Step R9: Session lifecycle

`SessionManager` reacts to `EventBus` events. Publish the app lifecycle events from the SwiftUI scene phase (Waangu: `WaanguApp.swift`):

```swift
.onChange(of: scenePhase) { old, new in
    Task {
        if new == .active && old != .active { await eventBus.publish(AppDidEnterForegroundEvent()) }
        if new == .background              { await eventBus.publish(AppDidEnterBackgroundEvent()) }
    }
}
```

Chat's reactions live in the package, in `ChatSessionLifecycle` (build it with `realtimeClient`, a `ChatSyncRunner` and `chatTokenManager`). Your session code calls one method per event and keeps its own work (analytics, crash reporting, other features' sync):

| Event | Call |
|---|---|
| Start, if a session token is valid; `UserDidLoginEvent` / `UserChatDidLoginEvent` | `await chatSession.userDidSignIn()`: connects `realtimeClient` if a chat token is valid, then requests a sync |
| `AppDidEnterForegroundEvent` | `await chatSession.appDidEnterForeground()` |
| `AppDidEnterBackgroundEvent` | `await chatSession.appDidEnterBackground()`: disconnects realtime **unless** a call is ringing or running (CallKit can answer from the lock screen) |
| `UserDidLogoutEvent` | `await chatSession.userDidSignOut()`: stops the sync, then disconnects. Then, in your code: drop the chat coordinator and `await FeatureRegistry.shared.unload(ChatFeature.self)` (in that order) |

> [!IMPORTANT]
> On logout, drop the coordinator **before** unloading `ChatFeature`. Otherwise a live coordinator points at a torn-down dependency graph and the next account inherits the previous account's chat state.

### Step R10: Open and present chat

```swift
@Observable final class AppCoordinator {
    var chatCoordinator: ChatCoordinator?
    var isChatPresented = false

    func startChatFlow(_ launch: ChatLaunchContext = ChatLaunchContext(route: .chats, source: .tab)) async {
        do {
            let feature = try await FeatureRegistry.shared.feature(ChatFeature.self)
            if chatCoordinator == nil {
                let coordinator = ChatCoordinator(feature: feature)
                coordinator.onCrossFeature = { [weak self] intent in
                    // chat asks the app to go elsewhere (a NavigationIntent): close chat, then route it
                }
                coordinator.start()
                chatCoordinator = coordinator
            }
            chatCoordinator?.apply(launch)
            isChatPresented = true
        } catch {
            // show an error with a "retry" that calls startChatFlow(launch) again
        }
    }
}

// Root view
.fullScreenCover(isPresented: Bindable(appCoordinator).isChatPresented) {
    if let chatCoordinator = appCoordinator.chatCoordinator {
        ChatCoordinatorView(coordinator: chatCoordinator)
    }
}
```

`ChatLaunchContext(route:source:)`: `source` is one of `.tab`, `.deepLink`, `.push`, `.wallet`, `.share`, `.notificationCenter`. Use `.tab` with route `.chats` to open the chat list.

### Step R11: What to copy, what to import

| Piece | Where it is | Host action |
|---|---|---|
| `RealtimeAuthBridge` | `WaanguChatSDK` product (was the Waangu app target) | Way 1: **import**. Way 2: copy (Step R5) |
| `ChatOutboxAdapter`, outbox flush handler, lazy API client | `WaanguChatSDK` product (were in the Waangu app target) | Way 1: **import**. Way 2: copy (Step R6) |
| Realtime topic registration | Waangu app target (`RealtimeRegistration`) | One line: `realtimeClient.register(ChatRealtimeRegistration.topicRegistrations)` |
| `FinanceDebugKit`, `SecurityDebugKit`, `FinanceBackend` | Waangu app target | **Not needed** with finance off (defaults apply) |
| `AccountScopedFinancialObjectPersistence` | `WaanguChatSDK` product (was the Waangu app target) | Way 1: import. Way 2: copy, only if finance is on |
| Everything else in the snippets | Package (`CoreKit`, `StorageKit`, `NetworkKit`, `RealtimeTransportKit`, `SecurityKit`, `OpusKit`, `CallMediaKit`, `TranslationKit`, `DomainKit`, `FeatureChat`) | Import |

### Host checklist

Missing items are listed in `plan.json` → `hostContract`:

| `hostContract` key | What | Agent may add? |
|---|---|---|
| `missingColors` | Color sets `AppPrimary`, `AppAccent`, `AppSecondary`, `bubbleSent`, `bubbleReceived` in the asset catalog | Yes, with placeholder values; **tell the human** to set real colors |
| `missingImages` | Image sets `chatBackground`, `callkit-icon` | **E7**: needs real assets |
| `missingUsageKeys` | `NS…UsageDescription`: Camera, Contacts, Location When In Use, Location Always and When In Use, Microphone, Photo Library | Yes, neutral wording; **tell the human** to review |
| `missingBackgroundModes` | `UIBackgroundModes`: `voip`, `audio` | **E7**: affects App Store review |
| `missingAppGroups` | `group.com.waangu.chat` on the app **and** its broadcast-upload extension | **E7**: needs the Apple Developer portal |

The app must also talk to the Waangu chat backend (MQTT topics `waangu-chat/…`, chat API base URLs passed in `ChatDependencies`): **E7** for the values.

---

## Updating later

### App installed with Way 1

- Xcode: **File → Packages → Update to Latest Package Versions**
- Or: `swift package update`

On `0.x`, "Up to Next Minor" won't jump from `0.2.x` to `0.3.0`; raise the rule.

### App installed with Way 2

The app has `.waangu-chat/MERGE_STATE.json` next to its `Package.swift`:

```bash
git -C ~/tools/waangu-chat fetch --tags && git -C ~/tools/waangu-chat checkout <new-version>
python3 $T merge /path/to/app --out /tmp/waangu-merge     # preview
python3 $T apply /path/to/app --out /tmp/waangu-apply     # branch waangu-chat/<new-version>
```

Every file gets a 3-way merge:
- **base**: the previous version
- **ours**: the new version
- **theirs**: the app's merged copy

The app's changes are kept, and its own `Package.swift` isn't touched. Finish as in [2.5](#25-finish-the-merge) and [2.6](#26-verify-way-2).

> [!CAUTION]
> `apply` refuses to update while a merged module still contains `<<<<<<<` markers from a previous merge. **Escalate (E2)**; never delete markers blindly.

---

## Hand-over to the human

When done (or stopped), report:

1. **Way used:** 1 or 2, and why (the `plan.json` classifications)
2. **Branch and worktree:** Way 2 or Way 1 option A, e.g. `waangu-chat/0.1.1`, `<path>`
3. **Merged modules:** `merge.json` → `kits` (Way 2)
4. **Conflicts you resolved:** file + what you kept
5. **Escalated items:** each with its code (E1–E7) and the exact message
6. **Host checklist items** still open
7. **Build and test result**, or why they could not run

---

## Escalation rules

When one applies: **stop**, do not work around it, and report the code, the exact message, and what you propose.

| Code | When | What the human decides |
|---|---|---|
| **E1** | Preflight fails (no Git, uncommitted changes, no Python, no repo access), or `DIRTY` | Fix the environment / commit or stash |
| **E2** | A conflict where both sides change the same logic; deleted-vs-changed files; binary/project files changed on both sides; leftover markers | Which version (or combination) is correct |
| **E3** | Version clash: `externalPackages[].status` = `CONFLICT`, `warnings`, or `swift package resolve` fails (e.g. app `GRDB from 6.0.0` vs ours `exact 7.0.0`) | Move the app to our version, or ask the maintainers to relax our pin |
| **E4** | `STRANGER_LOCAL`: same name, unrelated code | Rename the app's module (recommended), or module aliasing |
| **E5** | Xcode project edits needed (1.2, 2.7, re-linking) | Do the Xcode steps |
| **E6** | A merged module needs something only the app has: an app module import (e.g. `LocalizationKit`) or resources | Move that code to an app module, or ask the maintainers to add it to ours |
| **E7** | App-specific values: `ChatDependencies` wiring, images, background modes, App Group, backend URLs, user identity | Provide the values or assets |

---

## Reference

### Commands

```bash
T=~/tools/waangu-chat/Tools/module_tool.py

python3 $T inspect <app> [--json]
python3 $T plan    <app> [--out DIR]
python3 $T merge   <app> [--out DIR] [--history PATH]
python3 $T apply   <app> [--target NAME] [--worktree DIR] [--history PATH] [--url URL] [--no-verify] [--out DIR]
```

| Command | Changes the app? | Writes |
|---|---|---|
| `inspect` | No | stdout (or JSON with `--json`) |
| `plan` | No | `plan.json`, `report.md` |
| `merge` | No | `merge.json`, `merge-report.md` |
| `apply` | **Only** a new branch + worktree, nothing committed | `merge.json`, `merge-report.md` |

| Option | Meaning |
|---|---|
| `--target NAME` | App target that receives the `WaanguFeatureChat` product |
| `--worktree DIR` | Where to create the worktree (default `../<repo>-waangu-chat-<version>`) |
| `--history PATH` | Local clone of `waangu-user-ios`: 3-way merges with the real common ancestor |
| `--url URL` | Package URL written by Way 1 option A (e.g. the port-443 URL) |
| `--no-verify` | Skip the `swift package dump-package` check |
| `--out DIR` | Output folder (default: a temporary folder; the path is printed) |

### Exit codes

| Code | `plan` | `merge` / `apply` |
|---|---|---|
| `0` | All automatic | All automatic |
| `1` | Approvals required (`requiredApprovals`) | Conflicts or warnings (`needsPerson`, `warnings`) |
| `2` | A needed copy has uncommitted changes | Blockers (`blockers`); nothing applied |
| `3` | Error; nothing changed | Error; nothing changed (worktree rolled back) |

### `plan.json`

```jsonc
{
  "schema": 1,
  "planId": "plan-…",
  "request":   { "feature": "WaanguFeatureChat", "package": "waangu-chat-sdk", "version": "0.1.1",
                 "referenceMode": "release", "historyAvailable": false },
  "destination": { "path": "…", "gitRoot": "…", "head": "…", "branch": "…", "sharedBase": null },
  "modules": [
    { "module": "WaanguCoreKit",
      "requiredByFeatureChat": true,
      "classification": "COPY_MODIFIED",
      "decision": "RECONCILE_THEN_REPLACE",
      "requiresApproval": true,
      "evidence": { "location": "…/Sources/CoreKit", "kind": "swiftpm-target",
                    "files": 59, "identicalToPublished": 45, "changedByThemCount": 2,
                    "changedByThem": ["…"], "onlyInCopy": ["…"] } }
  ],
  "externalPackages": [
    { "package": "grdb.swift", "ourRequirement": "exact: \"7.0.0\"",
      "theirVersion": "6.29.3", "status": "CONFLICT (…)" }       // "OK" | "CHECK (…)" | "CONFLICT (…)"
  ],
  "hostContract": { "missingColors": [], "missingImages": [], "missingUsageKeys": [],
                    "missingBackgroundModes": [], "missingAppGroups": [] },
  "requiredApprovals": [ { "id": "module:CoreKit", "reason": "…" } ]
}
```

### `merge.json`

```jsonc
{
  "schema": 1,
  "command": "apply",                 // "merge" | "apply"
  "mode": "first",                    // "remote" (Way 1 option A) | "first" (Way 2) | "update"
  "version": "0.1.1",
  "fromVersion": null,                // previous version in "update" mode
  "kits": ["WaanguCoreKit", "WaanguSharedUI"],
  "blockers": ["…"],                  // non-empty → nothing applied
  "warnings": ["grdb.swift: CONFLICT …"],
  "decisions":   [ { "file": "Sources/SharedUI/X.swift", "outcome": "…", "person": false } ],
  "needsPerson": [ { "file": "Sources/CoreKit/Y.swift", "outcome": "CONFLICT (2 hunk(s), 3-way): markers written", "person": true } ],
  "reviewAfterConflicts": [ { "file": "Sources/SharedUI/Components/WalletBalanceHeroView.swift",
                              "uses": ["RemoteImage"],
                              "conflictFiles": ["Sources/SharedUI/Components/RemoteImage.swift"] } ],
  "applied": {                        // null for "merge" and when blocked
    "worktree": "/path/to/<repo>-waangu-chat-0.1.1",
    "branch": "waangu-chat/0.1.1",
    "notes": ["…"],
    "verified": [ { "manifest": "Packages/Package.swift", "ok": true, "error": "" } ],
    "xcode": ["… re-link instructions …"],
    "conflicts": [ /* same items as needsPerson */ ]
  }
}
```

`decisions[].file` and `needsPerson[].file` are relative to the folder of the app's `Package.swift` inside the worktree.

### Classifications and decisions

| `classification` | Meaning | Usual `decision` |
|---|---|---|
| `MISSING` | Not in the app | `ADD_PRODUCT` |
| `CANONICAL` | Already provided by `waangu-chat` | `NONE` or `RAISE_REQUIREMENT` |
| `COPY_UNCHANGED` | App copy whose files are all versions of ours | `REPLACE_STALE_COPY` or `REMOVE_LOCAL_COPY` |
| `COPY_MODIFIED` | App copy with files changed by the app (≥ 1 non-trivial file identical to a version of ours) | `RECONCILE_THEN_REPLACE` |
| `COPY_SAME_LINEAGE` | App copy sharing Git history with ours (`--history`) | `REPLACE_STALE_COPY` or `RECONCILE_THEN_REPLACE` |
| `STRANGER_LOCAL` | Same name, no non-trivial file in common with ours (or an Xcode target) | `HUMAN` → **E4** / **E5** |
| `DIRTY` | Uncommitted changes in the copy | `REFUSED_UNCOMMITTED` → **E1** |
| `IMPOSTOR_OR_MIRROR` | `waangu-chat` declared from another URL | `HUMAN` → ask the human |

| `decision` | What happens |
|---|---|
| `ADD_PRODUCT` | SwiftPM adds it with the package |
| `NONE` | Nothing to do |
| `RAISE_REQUIREMENT` | Raise the `waangu-chat` version rule |
| `REPLACE_STALE_COPY` | `apply` replaces the copy with ours |
| `REMOVE_LOCAL_COPY` | Package already added: delete the app's untouched copy |
| `RECONCILE_THEN_REPLACE` | `apply` merges, keeping the app's changes |
| `VERIFY_ON_RESOLVE` | Optional module with the same name: only a problem if SwiftPM reports a duplicate |
| `HUMAN` / `REFUSED_UNCOMMITTED` | Escalate |

### Error messages

| Message | Action |
|---|---|
| `Repository not found` | **E1**: no access |
| `Operation timed out` on port 22 | Use the 443 URL |
| `uncommitted changes in the project; commit or stash them first` | **E1** |
| `cannot merge until a person handles: …` | Map each line to its escalation |
| `branch waangu-chat/<v> already exists` | A previous `apply` is pending: ask the human to finish or delete it |
| `<path> already exists` (worktree) | Same as above, or pass `--worktree` |
| `` target `X` not found in Package.swift `` | Use a target name that exists in the app's `Package.swift` |
| `base version X not found: run the tool from a FULL clone` | `git -C ~/tools/waangu-chat fetch --tags --unshallow` |
| `… is already on waangu-chat X` | Nothing to update |
| `…required using a stable-version but … depends on an unstable-version package` | A dependency is pinned to a branch: **E3** |
| Duplicate module / `multiple targets named …` | The app has an older merged copy of our modules next to the package: remove one of the two |

# module_tool

Adds FeatureChat (`waangu-chat`) to your app **without duplicating modules**.

If your app already has kits with the same names as ours (`CoreKit`, `NetworkKit`, `SharedUI`…), the tool merges each one into **a single copy** that contains our version **and** your changes. Only real conflicts need a person, like a GitHub pull request.

| Command | What it does | Changes your project? |
|---|---|---|
| `plan` | Kit by kit: missing, already ours, your unchanged copy, your modified copy, version clashes, host setup | No |
| `merge` | Preview of the merge: which files merge automatically, which conflict | No |
| `apply` | Does it, on a **new branch in a separate folder** (Git worktree). Nothing is committed: you review, resolve conflicts, commit | Only that new branch |
| `inspect` | Inventory only: your local modules and remote packages | No |

Reports go to a temporary folder, or to `--out`.

## Get the tool

You need read access to `github.com/dondivinAsyst/waangu-chat-SDK`.

```bash
git clone --branch 0.2.6 git@github.com:dondivinAsyst/waangu-chat-SDK.git ~/tools/waangu-chat
```
Use a **full** clone (no `--depth`): updates need the previous version's tag. If port 22 is blocked, use `ssh://git@ssh.github.com:443/dondivinAsyst/waangu-chat-SDK.git`.

If your project has **no** kit with our names, you can also add the package and run the tool from SwiftPM's download (`.build/checkouts/waangu-chat-SDK/Tools/module_tool.py`, or under `~/Library/Developer/Xcode/DerivedData/…/SourcePackages/checkouts/` for Xcode projects). With same-name kits or a version clash (e.g. GRDB), SwiftPM may refuse to resolve, so use the clone.

## First time in a project

```bash
cd /path/to/your-app
python3 ~/tools/waangu-chat/Tools/module_tool.py plan .      # what will happen
python3 ~/tools/waangu-chat/Tools/module_tool.py merge .     # preview of the merge
python3 ~/tools/waangu-chat/Tools/module_tool.py apply . --target YourFeature
```
`--target` is the target of yours that gets the `FeatureChat` product.

What `apply` does, on branch `waangu-chat/<version>` in `../<your-repo>-waangu-chat-<version>`:

**If you have no kit with the same name:** it adds `.package(url: …waangu-chat-SDK.git, from: …)` and the `WaanguFeatureChat` product. That's all.

**If you have kits with the same names:**
1. Merges each same-name kit **in place**, in your own folder (e.g. `Packages/Sources/CoreKit`), file by file:

   | Situation | Result |
   |---|---|
   | File identical, or an older version of ours | ours (automatic) |
   | File changed only by you | yours (automatic) |
   | File added by you | kept (automatic) |
   | Changed on both sides, different lines | merged (automatic) |
   | Changed on both sides, same lines | **conflict**: `<<<<<<<` markers, a person decides |

2. Copies the chat modules you don't have (`FeatureChat`, `ScreenShareTransport`, `SecurityKit`…) next to them, in the same `Sources/`.
3. Edits your `Package.swift` with **additions only**: those modules as targets, the external packages they need, and `"FeatureChat"` in your `--target`. Nothing is removed, so your product names stay and Xcode needs no re-linking.
4. Checks the edited `Package.swift` loads (`swift package dump-package`).
5. Writes `.waangu-chat/MERGE_STATE.json` next to your `Package.swift`, for updates.

`--layout vendor` keeps the older layout (a separate copy in `Vendor/waangu-chat/`).

Then, in the worktree folder:
1. Resolve the conflicts (search for `<<<<<<<`).
2. `swift package resolve`, build, run your tests.
3. Commit and open a pull request.

If `apply` fails halfway, it removes the worktree and the branch it created, so nothing is left behind.

## Updating to a new waangu-chat version

Same command, from the new version:
```bash
cd ~/tools/waangu-chat && git fetch --tags && git checkout <new-version>
cd /path/to/your-app
python3 ~/tools/waangu-chat/Tools/module_tool.py apply .
```
It sees `.waangu-chat/MERGE_STATE.json` and does a 3-way merge for every file of every chat module, where it lives in your `Sources/`:
- **base**: the version you had
- **ours**: the new version
- **theirs**: your merged copy

Your changes are kept, and only real conflicts need a person. In `Package.swift` it only adds what the new version needs (new modules, new dependencies). It refuses to run while old conflict markers (`<<<<<<<`) are still in those modules.

## What `plan` decides, per module FeatureChat needs

| Found in your project as | Meaning | What happens | Person? |
|---|---|---|---|
| `MISSING` | Not there | SwiftPM adds it | no |
| `CANONICAL` | Already from `waangu-chat` | Shared, one copy | no (yes if the version must jump past a `0.x` minor) |
| `COPY_UNCHANGED` | Your copy of our kit; every file is a current or older version of ours | Becomes ours | no |
| `COPY_MODIFIED` | Your copy of our kit, with files you changed (at least one non-empty file of 200+ bytes is identical to a version of ours, however much you changed the rest) | Merged: your changes kept | yes for conflicts |
| `COPY_SAME_LINEAGE` | Same, measured with our Git history (`--history`) | Same, with local/upstream/both counts | yes for conflicts |
| `DIRTY` | Uncommitted changes in your copy | Refused until committed or stashed | **yes** |
| `STRANGER_LOCAL` | Same name, unrelated code: not a single non-trivial file in common with any version of ours | Not merged: rename yours first | **yes** |
| `IMPOSTOR_OR_MIRROR` | A `waangu-chat` from another URL | A person decides | **yes** |

`Tools/KNOWN_BLOBS.txt` holds the Git fingerprint of every past version of every published file. That's how the tool tells **"an older version of our file"** (safe to replace) from **"a file you changed"** (kept).

## What still needs a person

The tool reports these and never guesses:
- **Conflicts**: both sides changed the same lines.
- **Version clashes**: e.g. your `GRDB from: "6.0.0"` vs our `exact: "7.0.0"`. No version satisfies both until someone changes one.
- **Your kit needed things ours doesn't have**: a dependency on one of your modules (e.g. your `SharedUI` imports `LocalizationKit`), or a `Resources` folder. The merged copy can't depend on your app's modules.
- **Same name, unrelated code**: rename yours first.
- **Uncommitted changes** in a copy: commit or stash first.
- **Xcode projects** that link those kits from your local package: re-link them from `waangu-chat` in Xcode. The report lists each target.
- **Files to re-check after a conflict**: the report's "Check after resolving the conflicts" section lists files that took **our** version and use a type from a conflicting file. If you keep **your** side of that file, check those files still match its API (e.g. `RemoteImage.swift` kept as yours → `WalletBalanceHeroView.swift` must call it your way).
- **Host setup**: named colors and images, Info.plist keys, background modes, App Group (listed by `plan`).

## Better merges with our history

Without our Git history, a file you changed is compared with ours **2-way**, so any difference is a conflict. Teams with access to `waangu-user-ios` can add `--history /path/to/waangu-user-ios`, which gives **3-way** merges against the real common ancestor. On the 2026-10-27 test (an old copy of our app), conflicts went from 11 to 7.

Inside `waangu-user-ios`, the tool (`Scripts/module-tool/module_tool.py`) uses the local `packages-release` branch and our full history automatically.

## Exit codes

- `0`: everything automatic
- `1`: decisions needed (conflicts or warnings)
- `2`: blocked (fix the listed items first)
- `3`: error, nothing changed

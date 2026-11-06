#!/usr/bin/env python3
#
# module_tool — prépare l'ajout de FeatureChat (package `waangu-chat`) dans un
# autre projet iOS. LECTURE SEULE : aucune commande ne modifie le projet cible
# ni ce dépôt. Rien n'est compilé : les manifestes sont lus comme du texte,
# les projets Xcode via `plutil`, l'historique via `git` (lecture).
#
#   module_tool.py inspect <projet>
#   module_tool.py plan    <projet> [--out <dossier>]
#
# Référence (« canonique ») : la release locale `packages-release`, c'est-à-dire
# exactement ce qui est publié sur github.com/dondivinAsyst/waangu-chat-SDK, et
# l'historique de ce dépôt d'où elle vient.
#
# Pour chaque module dont FeatureChat a besoin, le projet cible est classé :
#   MISSING            absent                      → ajouté par SwiftPM (auto)
#   CANONICAL          déjà fourni par waangu-chat → partagé (auto)
#   COPY_SAME_LINEAGE  copie locale, même historique que nous
#                        sans modification locale → remplacée par la nôtre (auto)
#                        avec modifications       → réconciliation (humain)
#   COPY_UNCHANGED     copie locale dont chaque fichier est une version des nôtres → remplacée (auto)
#   COPY_MODIFIED      copie locale avec des fichiers changés chez eux → réconciliation (humain)
#   STRANGER_LOCAL     module local du même nom, contenu sans rapport
#   IMPOSTOR_OR_MIRROR un package `waangu-chat` venant d'une autre URL
#   (package déjà ajouté + copie locale : la copie est analysée de la même façon ;
#    une copie inchangée est simplement à supprimer)
#   DIRTY              modifications non commitées dans la copie → refus
#
# Codes de sortie : 0 tout est automatique · 1 décisions humaines requises ·
#                   2 refusé (copie modifiée non commitée) · 3 erreur.
#
# Conception : docs/module-reuse-research/E-dependency-compatibility-spec.md, G-cli-design.md.

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile

TOOL_VERSION = "0.1.0"
# SwiftPM derives the identity from the repository name: .../waangu-chat-SDK.git -> "waangu-chat-sdk"
PACKAGE_IDENTITY = "waangu-chat-sdk"
CANONICAL_ORIGINS = {
    "github.com/dondivinasyst/waangu-chat-sdk",
    "github.com/dondivinasyst/waangu-chat",   # the name before the repository was renamed
}
RELEASE_BRANCH = "packages-release"
FEATURE = "WaanguFeatureChat"   # the manifest target and product name (renamed from FeatureChat, SDK plan direction A)
# Une copie de nos kits se reconnaît à au moins UN fichier non trivial identique à une
# version des nôtres. Un seuil en pourcentage (60 % auparavant) classait « sans rapport »
# des kits copiés puis très modifiés (SharedUI : 22 fichiers sur 39 identiques aux nôtres).
# Les fichiers vides ou minuscules ne comptent pas : du code sans rapport peut en partager.
MIN_SHARED_FILE_BYTES = 200

# Clés Info.plist exigées par le chat (B §6 B5 de la recherche). Elles ne se
# déduisent pas du code source de façon fiable, d'où la liste.
REQUIRED_USAGE_KEYS = [
    "NSCameraUsageDescription",
    "NSContactsUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSPhotoLibraryUsageDescription",
]
REQUIRED_BACKGROUND_MODES = ["voip", "audio"]

SKIP_DIRS = {
    ".git", ".build", "build", "DerivedData", "Pods", "Carthage", "node_modules",
    "checkouts", "SourcePackages", ".swiftpm",
}


# ─── Utilitaires ─────────────────────────────────────────────────────────────

class ToolError(Exception):
    pass


def run(args, cwd=None, input_text=None, check=True):
    proc = subprocess.run(args, cwd=cwd, input=input_text, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise ToolError(f"{' '.join(args)} → {proc.stderr.strip() or proc.returncode}")
    return proc.stdout


def git(repo, *args, check=True, input_text=None):
    return run(["git", "-C", repo, *args], check=check, input_text=input_text)


def redact(url):
    """Retire tout identifiant d'une URL (jamais de jeton dans un rapport)."""
    return re.sub(r"(https?://)[^/@]+@", r"\1", url or "")


def normalize_origin(url):
    """`git@github.com:a/b.git`, `ssh://git@ssh.github.com:443/a/b`, `https://…/a/b.git` → `github.com/a/b`."""
    u = redact(url).strip().lower()
    u = re.sub(r"^(ssh://|https?://|git://)", "", u)
    u = re.sub(r"^[^@/]+@", "", u)
    u = u.replace("ssh.github.com:443/", "github.com/").replace("github.com:", "github.com/")
    u = re.sub(r":\d+/", "/", u)
    return re.sub(r"\.git$", "", u).rstrip("/")


def package_identity(url):
    return normalize_origin(url).split("/")[-1]


def skipped(path, root):
    """Vrai si `path` est dans un dossier ignoré, en ne regardant que la partie sous `root`
    (l'outil lui-même peut vivre dans `.build/checkouts/`, un projet dans un dossier `build`)."""
    rel = os.path.relpath(path, root)
    return rel != "." and any(part in SKIP_DIRS for part in rel.split(os.sep))


def find_files(root, name=None, suffix=None):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if (name and f == name) or (suffix and f.endswith(suffix)):
                out.append(os.path.join(dirpath, f))
    return sorted(out)


def find_dirs(root, suffix):
    out = []
    for dirpath, dirnames, _ in os.walk(root):
        keep = []
        for d in dirnames:
            if d in SKIP_DIRS:
                continue
            if d.endswith(suffix):
                out.append(os.path.join(dirpath, d))
            else:
                keep.append(d)
        dirnames[:] = keep
    return sorted(out)


# ─── Lecture des manifestes SwiftPM (texte, sans compiler) ───────────────────

def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return "\n".join(re.sub(r"(^|\s)//.*$", r"\1", line) for line in src.splitlines())


def balanced(src, start, open_ch, close_ch):
    """Contenu entre `open_ch` à `start` et son `close_ch` correspondant (chaînes ignorées)."""
    depth, i, in_str = 0, start, False
    while i < len(src):
        c = src[i]
        if c == '"' and src[i - 1] != "\\":
            in_str = not in_str
        elif not in_str:
            if c == open_ch:
                depth += 1
            elif c == close_ch:
                depth -= 1
                if depth == 0:
                    return src[start + 1:i]
        i += 1
    return src[start + 1:]


def parse_manifest(text):
    src = strip_comments(text)
    manifest = {"targets": {}, "products": {}, "packages": []}

    for m in re.finditer(r"\.(target|testTarget|executableTarget|binaryTarget|macro|plugin)\s*\(", src):
        body = balanced(src, m.end() - 1, "(", ")")
        name = re.search(r'name:\s*"([^"]+)"', body)
        if not name:
            continue
        deps, products = [], []
        dm = re.search(r"dependencies:\s*\[", body)
        if dm:
            dep_body = balanced(body, dm.end() - 1, "[", "]")
            for pm in re.finditer(r"\.product\s*\(", dep_body):
                pbody = balanced(dep_body, pm.end() - 1, "(", ")")
                pn = re.search(r'name:\s*"([^"]+)"', pbody)
                pk = re.search(r'package:\s*"([^"]+)"', pbody)
                if pn:
                    products.append({"name": pn.group(1), "package": pk.group(1) if pk else pn.group(1)})
            plain = re.sub(r"\.product\s*\((?:[^()]|\([^()]*\))*\)", "", dep_body)
            deps = re.findall(r'"([^"]+)"', plain)
        path = re.search(r'path:\s*"([^"]+)"', body)
        kind = m.group(1)
        has_resources = bool(re.search(r"resources:\s*\[\s*\S", body))
        default_dir = "Tests" if kind == "testTarget" else "Sources"
        manifest["targets"][name.group(1)] = {
            "kind": kind,
            "path": path.group(1) if path else f"{default_dir}/{name.group(1)}",
            "dependencies": deps,
            "productDependencies": products,
            "resources": has_resources,
        }

    for m in re.finditer(r"\.library\s*\(", src):
        body = balanced(src, m.end() - 1, "(", ")")
        name = re.search(r'name:\s*"([^"]+)"', body)
        tm = re.search(r"targets:\s*\[([^\]]*)\]", body)
        if name:
            manifest["products"][name.group(1)] = re.findall(r'"([^"]+)"', tm.group(1)) if tm else []

    for m in re.finditer(r"\.package\s*\(", src):
        body = balanced(src, m.end() - 1, "(", ")")
        url = re.search(r'url:\s*"([^"]+)"', body)
        path = re.search(r'path:\s*"([^"]+)"', body)
        if url:
            req = re.sub(r"\s+", " ", re.sub(r'url:\s*"[^"]+"\s*,?', "", body)).strip(" ,")
            manifest["packages"].append({"url": redact(url.group(1)), "requirement": req,
                                         "identity": package_identity(url.group(1))})
        elif path:
            manifest["packages"].append({"path": path.group(1), "identity": os.path.basename(path.group(1)).lower()})
    return manifest


def closure(targets, start):
    seen, stack = set(), [start]
    while stack:
        t = stack.pop()
        for d in targets.get(t, {}).get("dependencies", []):
            if d not in seen and d in targets:
                seen.add(d)
                stack.append(d)
    return seen


# ─── Référence canonique (ce qui est publié) ─────────────────────────────────
#
# Deux modes, choisis selon l'endroit d'où l'outil est lancé :
#   release : l'outil est `Tools/module_tool.py` d'une copie de waangu-chat
#             (git clone du package). La référence est cette copie, telle quelle.
#             Aucun accès à waangu-user-ios n'est nécessaire.
#   dev     : l'outil est `Scripts/module-tool/` de waangu-user-ios. La référence
#             est la branche locale `packages-release`.
# L'historique de waangu-user-ios (pour dater une copie : « copiée de notre
# commit X ») est disponible en mode dev, ou en mode release avec --history.

def finish_canonical(canon, manifest):
    targets = {n: t for n, t in manifest["targets"].items() if t["kind"] != "testTarget"}
    required = sorted({FEATURE} | closure(targets, FEATURE))
    external = {}
    for name in required:
        for p in targets[name]["productDependencies"]:
            external.setdefault(p["package"].lower(), set()).add(name)
    canon.update({
        "targets": targets,
        "required": required,
        "optional": sorted(set(targets) - set(required)),
        "packages": {p["identity"]: dict(p, usedBy=sorted(external.get(p["identity"], set())))
                     for p in manifest["packages"] if "url" in p},
    })
    return canon


def load_canonical_dev(repo):
    if not git(repo, "rev-parse", "--verify", "-q", RELEASE_BRANCH, check=False).strip():
        raise ToolError(f"branche {RELEASE_BRANCH} introuvable : publiez d'abord (Scripts/publish/publish_waangu_chat.sh)")
    message = git(repo, "log", "-1", "--format=%s", RELEASE_BRANCH).strip()
    vm = re.search(r"waangu-chat (\d+\.\d+\.\d+) - from waangu-user-ios ([0-9a-f]+)", message)
    if not vm:
        raise ToolError(f"message de release inattendu : {message!r}")
    manifest = parse_manifest(git(repo, "show", f"{RELEASE_BRANCH}:Package.swift"))
    all_blobs = set(line.split()[2] for line in git(repo, "ls-tree", "-r", RELEASE_BRANCH).splitlines())
    published_paths = sorted({f"Packages/{t['path']}" for t in manifest["targets"].values()})
    known = all_blobs | lineage_blobs(repo, vm.group(2), published_paths)

    def published_blobs(path):
        out = {}
        for line in git(repo, "ls-tree", "-r", f"{RELEASE_BRANCH}:{path}").splitlines():
            meta, rel = line.split("\t", 1)
            out[rel] = meta.split()[2]
        return out

    def grep(pattern, subdirs):
        posix = pattern.replace(r"\s", "[[:space:]]")  # l'ERE de git grep ne connaît pas \s
        return git(repo, "grep", "-hoE", posix, RELEASE_BRANCH, "--", *subdirs, check=False).splitlines()

    return finish_canonical({
        "mode": "dev",
        "root": repo,
        "version": vm.group(1),
        "sourceCommit": git(repo, "rev-parse", vm.group(2)).strip(),
        "releaseCommit": git(repo, "rev-parse", RELEASE_BRANCH).strip(),
        "historyRepo": repo,
        "publishedBlobsAt": published_blobs,
        "knownBlobs": lambda shas: set(shas) & known,
        "grep": grep,
    }, manifest)


def load_canonical_release(root, history=None):
    info_path = os.path.join(root, "Tools", "RELEASE.json")
    try:
        info = json.load(open(info_path))
    except (OSError, ValueError):
        raise ToolError(f"{info_path} illisible : ce dossier n'est pas une copie publiée de waangu-chat")
    manifest = parse_manifest(open(os.path.join(root, "Package.swift"), encoding="utf-8").read())

    def files_under(path):
        base = os.path.join(root, path)
        return sorted(os.path.join(dp, f) for dp, dn, fs in os.walk(base) for f in fs
                      if not f.startswith(".") and not skipped(dp, base))

    cache = {}

    def published_blobs(path):
        if path not in cache:
            files = files_under(path)
            cache[path] = dict(zip((os.path.relpath(f, os.path.join(root, path)) for f in files), hash_files(files)))
        return cache[path]

    all_blobs = set()
    for top in ("Sources", "Tests"):
        all_blobs |= set(published_blobs(top).values())
    # Empreintes Git de toutes les versions passées des fichiers publiés : une copie
    # ancienne de nos fichiers y figure, une modification faite chez eux non.
    try:
        all_blobs |= set(open(os.path.join(root, "Tools", "KNOWN_BLOBS.txt")).read().split())
    except OSError:
        pass

    def grep(pattern, subdirs):
        rx, out = re.compile(pattern), []
        for sub in subdirs:
            for f in files_under(sub):
                if f.endswith(".swift"):
                    for line in open(f, encoding="utf-8", errors="replace"):
                        out += [m.group(0) for m in rx.finditer(line)]
        return out

    source = info.get("sourceCommit", "")
    history_repo = None
    if history:
        found = subprocess.run(["git", "-C", history, "cat-file", "-e", f"{source}^{{commit}}"],
                               capture_output=True).returncode == 0
        if found:
            history_repo = git(history, "rev-parse", "--show-toplevel").strip()
        else:
            raise ToolError(f"--history {history} : commit source {source[:8]} introuvable (mettez ce dépôt à jour)")
    release_commit = git(root, "rev-parse", "HEAD", check=False).strip() or info.get("version")

    return finish_canonical({
        "mode": "release",
        "root": root,
        "version": info["version"],
        "sourceCommit": source,
        "releaseCommit": release_commit,
        "historyRepo": history_repo,
        "publishedBlobsAt": published_blobs,
        "knownBlobs": lambda shas: set(shas) & all_blobs,  # release + KNOWN_BLOBS.txt (lignée publiée)
        "grep": grep,
    }, manifest)


def canonical_host_contract(canon):
    """Ressources que le chat attend de l'app hôte, lues dans le code publié."""
    colors, images = set(), set()
    pattern = r'(Color|Image|UIImage|UIColor)\(\s*(named:\s*)?"[A-Za-z0-9_.-]+"'
    for line in canon["grep"](pattern, ["Sources/FeatureChat", "Sources/SharedUI"]):
        m = re.search(r'(Color|Image|UIImage|UIColor)\(\s*(?:named:\s*)?"([^"]+)"', line)
        if m:
            (colors if m.group(1) in ("Color", "UIColor") else images).add(m.group(2))
    groups = set()
    for line in canon["grep"](r'"group\.[A-Za-z0-9_.-]+"', ["Sources/ScreenShareTransport"]):
        groups |= set(re.findall(r'"(group\.[A-Za-z0-9_.-]+)"', line))
    return {"colors": sorted(colors), "images": sorted(images), "appGroups": sorted(groups),
            "usageKeys": REQUIRED_USAGE_KEYS, "backgroundModes": REQUIRED_BACKGROUND_MODES}


# ─── Inventaire du projet cible ──────────────────────────────────────────────

def read_resolved(path):
    try:
        data = json.load(open(path))
    except (OSError, ValueError):
        return []
    pins = data.get("pins") or data.get("object", {}).get("pins", [])
    out = []
    for p in pins:
        url = p.get("location") or p.get("repositoryURL") or ""
        state = p.get("state", {})
        out.append({"identity": p.get("identity") or package_identity(url), "url": redact(url),
                    "version": state.get("version"), "revision": state.get("revision"),
                    "branch": state.get("branch"), "file": path})
    return out


def read_pbxproj(path):
    try:
        raw = run(["plutil", "-convert", "json", "-o", "-", path])
        objects = json.loads(raw)["objects"]
    except (ToolError, ValueError, KeyError):
        return None
    targets, remote_refs, local_refs, settings = [], {}, {}, []
    for oid, o in objects.items():
        if o.get("isa") == "XCRemoteSwiftPackageReference":
            remote_refs[oid] = {"url": redact(o.get("repositoryURL", "")), "requirement": o.get("requirement", {})}
        elif o.get("isa") == "XCLocalSwiftPackageReference":
            local_refs[oid] = {"relativePath": o.get("relativePath")}
    for oid, o in objects.items():
        if o.get("isa") != "PBXNativeTarget":
            continue
        products = []
        for pid in o.get("packageProductDependencies", []):
            p = objects.get(pid, {})
            ref = p.get("package")
            # Xcode récent : un produit de package LOCAL n'a pas de champ `package` du tout.
            local = local_refs.get(ref) or ({"implicit": True} if ref is None else None)
            products.append({"product": p.get("productName"),
                             "remote": remote_refs.get(ref), "local": local})
        for cid in objects.get(o.get("buildConfigurationList"), {}).get("buildConfigurations", []):
            settings.append(objects.get(cid, {}).get("buildSettings", {}))
        targets.append({"name": o.get("name"), "productType": o.get("productType"), "packageProducts": products})
    return {"file": path, "targets": targets, "remotePackages": list(remote_refs.values()),
            "localPackages": list(local_refs.values()), "buildSettings": settings}


def inspect_project(dest):
    dest = os.path.abspath(dest)
    if not os.path.isdir(dest):
        raise ToolError(f"dossier introuvable : {dest}")
    git_root = git(dest, "rev-parse", "--show-toplevel", check=False).strip() or None

    manifests = []
    for path in find_files(dest, name="Package.swift"):
        try:
            m = parse_manifest(open(path, encoding="utf-8", errors="replace").read())
        except OSError:
            continue
        m["file"] = path
        m["dir"] = os.path.dirname(path)
        manifests.append(m)

    projects = [p for p in (read_pbxproj(os.path.join(x, "project.pbxproj"))
                            for x in find_dirs(dest, ".xcodeproj")) if p]

    resolved = []
    for path in find_files(dest, name="Package.resolved"):
        resolved.extend(read_resolved(path))

    # Modules locaux : targets SwiftPM non-test + targets Xcode de type framework.
    local_modules = {}
    for m in manifests:
        for name, t in m["targets"].items():
            if t["kind"] in ("testTarget",):
                continue
            local_modules.setdefault(name, []).append({
                "kind": f"swiftpm-{t['kind']}", "manifest": m["file"],
                "dir": os.path.normpath(os.path.join(m["dir"], t["path"]))})
    for p in projects:
        for t in p["targets"]:
            if t["productType"] and "framework" in t["productType"]:
                local_modules.setdefault(t["name"], []).append({"kind": "xcode-framework", "project": p["file"], "dir": None})

    # Dépendances de package distantes (manifestes + projets Xcode).
    remote = []
    for m in manifests:
        for p in m["packages"]:
            if "url" in p:
                remote.append(dict(p, declaredIn=m["file"]))
    for p in projects:
        for r in p["remotePackages"]:
            remote.append({"url": r["url"], "identity": package_identity(r["url"]),
                           "requirement": json.dumps(r["requirement"], sort_keys=True), "declaredIn": p["file"]})

    # Contrat hôte : catalogues d'assets, Info.plist, entitlements.
    assets = set()
    for cat in find_dirs(dest, ".xcassets"):
        for dirpath, dirnames, _ in os.walk(cat):
            for d in dirnames:
                if d.endswith((".colorset", ".imageset")):
                    assets.add(os.path.splitext(d)[0])
    plist_keys, background_modes, app_groups = set(), set(), set()
    for path in find_files(dest, name="Info.plist"):
        try:
            data = plistlib.load(open(path, "rb"))
        except Exception:
            continue
        plist_keys |= set(data)
        background_modes |= set(data.get("UIBackgroundModes", []))
    for p in projects:
        for s in p["buildSettings"]:
            for k in s:
                if k.startswith("INFOPLIST_KEY_"):
                    plist_keys.add(k[len("INFOPLIST_KEY_"):])
    for path in find_files(dest, suffix=".entitlements"):
        try:
            data = plistlib.load(open(path, "rb"))
        except Exception:
            continue
        app_groups |= set(data.get("com.apple.security.application-groups", []))

    return {
        "path": dest,
        "gitRoot": git_root,
        "head": git(git_root, "rev-parse", "HEAD", check=False).strip() if git_root else None,
        "branch": git(git_root, "branch", "--show-current", check=False).strip() if git_root else None,
        "manifests": [{"file": m["file"], "targets": sorted(m["targets"]), "packages": m["packages"]} for m in manifests],
        "xcodeProjects": [{"file": p["file"], "targets": p["targets"], "remotePackages": p["remotePackages"],
                           "localPackages": p["localPackages"]} for p in projects],
        "localModules": local_modules,
        "remotePackages": remote,
        "resolvedPins": resolved,
        "host": {"assets": sorted(assets), "plistKeys": sorted(plist_keys),
                 "backgroundModes": sorted(background_modes), "appGroups": sorted(app_groups)},
    }


# ─── Identité d'une copie locale ─────────────────────────────────────────────

def hash_files(paths):
    if not paths:
        return []
    return run(["git", "hash-object", "--stdin-paths"], input_text="\n".join(paths) + "\n").split()


def lineage_blobs(repo, rev, paths):
    """Empreintes de toutes les versions de `paths` dans l'historique de `rev` (et seulement lui).

    Ne PAS utiliser « l'objet existe dans le dépôt » : un dépôt peut contenir les
    branches d'un autre projet (fetch), et leurs fichiers modifiés passeraient
    pour des versions des nôtres. Même règle que Tools/KNOWN_BLOBS.txt."""
    out = git(repo, "log", "-m", "--format=", "--raw", "--no-abbrev", "--no-renames", rev, "--", *paths)
    blobs = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 4 and line.startswith(":"):
            blobs.update(x for x in parts[2:4] if x != "0" * 40)
    return blobs


def shared_bases(canon_repo, canon_rev, dest_repo, dest_head):
    """Meilleurs ancêtres communs (comme `git merge-base --all`) sans réunir les deux dépôts.

    Ancêtres communs = commits à la fois dans notre historique et dans celui du
    projet cible ; on garde ceux qui ne sont l'ancêtre d'aucun autre. Un
    historique « croisé » en a plusieurs : on les renvoie tous, le plus récent
    d'abord (c'est celui que `git merge-base` a choisi sur les clones testés).
    """
    ours = set(git(canon_repo, "rev-list", canon_rev).split())
    common = [c for c in git(dest_repo, "rev-list", dest_head).split() if c in ours]
    if not common:
        return []
    best = git(dest_repo, "merge-base", "--independent", *common).split()
    dated = git(dest_repo, "show", "-s", "--format=%ct %H", *best).split("\n")
    return [line.split()[1] for line in sorted((l for l in dated if l.strip()), reverse=True)]


def classify_copy(module, copy, canon, dest_info, base):
    """Évidence et classification d'une copie locale du module `module`."""
    evidence = {"location": copy.get("dir") or copy.get("project") or copy.get("manifest"), "kind": copy["kind"]}
    directory = copy.get("dir")
    if not directory or not os.path.isdir(directory):
        evidence["note"] = "source folder not found; identity cannot be checked"
        return "STRANGER_LOCAL", evidence

    files = sorted(os.path.join(dp, f) for dp, dn, fs in os.walk(directory)
                   for f in fs if not f.startswith(".") and not skipped(dp, directory))
    rel = [os.path.relpath(f, directory) for f in files]
    blobs = hash_files(files)
    known = canon["knownBlobs"](blobs)
    published = canon["publishedBlobsAt"](canon["targets"][module]["path"])
    evidence.update({
        "files": len(files),
        "filesKnownInOurHistory": sum(1 for b in blobs if b in known),
        "identicalToPublished": sum(1 for r, b in zip(rel, blobs) if published.get(r) == b),
        "differentFromPublished": sum(1 for r, b in zip(rel, blobs) if r in published and published[r] != b),
        "onlyInCopy": sorted(r for r in rel if r not in published)[:50],
        "differentFiles": sorted(r for r, b in zip(rel, blobs) if r in published and published[r] != b)[:50],
        "onlyInPublished": len(set(published) - set(rel)),
    })
    evidence["changedByThem"] = sorted(r for r, bl in zip(rel, blobs) if bl not in known)[:50]
    evidence["changedByThemCount"] = sum(1 for bl in blobs if bl not in known)
    ratio = evidence["filesKnownInOurHistory"] / len(files) if files else 0.0
    evidence["blobMatchRatio"] = round(ratio, 3)
    evidence["sharedNonTrivialFiles"] = sorted(
        r for r, f, bl in zip(rel, files, blobs) if bl in known and os.path.getsize(f) >= MIN_SHARED_FILE_BYTES)[:50]

    git_root = dest_info["gitRoot"]
    if git_root:
        relpath = os.path.relpath(directory, git_root)
        dirty = git(git_root, "status", "--porcelain", "--", relpath, check=False).strip()
        if dirty:
            evidence["uncommitted"] = dirty.splitlines()[:50]
            return "DIRTY", evidence
        if base:
            canon_path = canon["targetsFull"].get(module, {}).get("path")
            local = set(git(git_root, "diff", "--name-only", base, "HEAD", "--", relpath).split())
            local_rel = {os.path.relpath(os.path.join(git_root, p), directory) for p in local}
            upstream_rel = set()
            if canon_path:
                full_path = f"Packages/{canon_path}"
                upstream = git(canon["historyRepo"], "diff", "--name-only", base, canon["sourceCommit"], "--", full_path).split()
                upstream_rel = {os.path.relpath(p, full_path) for p in upstream}
            both = sorted(local_rel & upstream_rel)
            evidence.update({"base": base, "localChanged": len(local_rel), "upstreamChanged": len(upstream_rel),
                             "bothChanged": len(both), "bothChangedFiles": both[:50],
                             "localChangedFiles": sorted(local_rel)[:50]})
            return "COPY_SAME_LINEAGE", evidence

    if files and evidence["changedByThemCount"] == 0:
        return "COPY_UNCHANGED", evidence      # chaque fichier est une version (actuelle ou ancienne) des nôtres
    if evidence["sharedNonTrivialFiles"]:
        return "COPY_MODIFIED", evidence       # copie des nôtres, avec des fichiers changés chez eux
    return "STRANGER_LOCAL", evidence


# ─── Plan ────────────────────────────────────────────────────────────────────

DECISIONS = {
    # classification → (décision, approbation humaine requise)
    "MISSING": ("ADD_PRODUCT", False),
    "CANONICAL": ("NONE", False),
    "IMPOSTOR_OR_MIRROR": ("HUMAN", True),
    "DUPLICATE": ("HUMAN", True),
    "DIRTY": ("REFUSED_UNCOMMITTED", True),
    "COPY_UNCHANGED": ("REPLACE_STALE_COPY", False),
    "COPY_MODIFIED": ("RECONCILE_THEN_REPLACE", True),
    "STRANGER_LOCAL": ("HUMAN", True),
}


def version_tuple(v):
    try:
        return tuple(int(x) for x in v.split("."))
    except (AttributeError, ValueError):
        return None


def requirement_range(req):
    """Règle SwiftPM → (min inclus, max exclu) en tuples, ou None si non comprise."""
    m = re.search(r'exact:\s*"([^"]+)"', req) or re.search(r'\.exact\(\s*"([^"]+)"', req)
    if m:
        v = version_tuple(m.group(1))
        return (v, v[:2] + (v[2] + 1,)) if v else None
    m = re.search(r'from:\s*"([^"]+)"', req) or re.search(r'upToNextMajor\(\s*from:\s*"([^"]+)"', req)
    if m:
        v = version_tuple(m.group(1))
        return (v, (v[0] + 1, 0, 0)) if v else None
    m = re.search(r'upToNextMinor\(\s*from:\s*"([^"]+)"', req)
    if m:
        v = version_tuple(m.group(1))
        return (v, (v[0], v[1] + 1, 0)) if v else None
    m = re.search(r'"([0-9.]+)"\s*\.\.<\s*"([0-9.]+)"', req)
    if m:
        return (version_tuple(m.group(1)), version_tuple(m.group(2)))
    return None


def external_conflicts(canon, dest_info):
    """Nos dépendances externes face à celles du projet : version épinglée, sinon règle déclarée."""
    pins = {p["identity"]: p for p in dest_info["resolvedPins"]}
    declared = {}
    for r in dest_info["remotePackages"]:
        declared.setdefault(r["identity"], r)
    out = []
    for ident, ours in sorted(canon["packages"].items()):
        req = ours["requirement"]
        our_range = requirement_range(req)
        theirs = pins.get(ident)
        if theirs:
            tv = version_tuple(theirs.get("version"))
            status = "OK"
            if theirs.get("branch") or not tv:
                status = "CHECK (pinned to a branch or revision in the project)"
            elif our_range and not (our_range[0] <= tv < our_range[1]):
                status = f"CONFLICT (we need `{req}`)"
                dec = next((r for r in dest_info["remotePackages"] if r["identity"] == ident), None)
                their_range = requirement_range(dec.get("requirement", "")) if dec else None
                if their_range and max(our_range[0], their_range[0]) < min(our_range[1], their_range[1]):
                    # Le pin est périmé, mais leur règle admet notre version : SwiftPM re-résout.
                    status = f"OK (pinned {theirs.get('version')}, but their rule `{dec['requirement']}` allows ours: the pin will move)"
            out.append({"package": ident, "ourRequirement": req,
                        "theirVersion": theirs.get("version") or theirs.get("revision"), "status": status})
            continue
        dec = declared.get(ident)
        if not dec:
            continue
        their_range = requirement_range(dec.get("requirement", ""))
        status = "CHECK (their rule could not be read)"
        if our_range and their_range:
            overlap = max(our_range[0], their_range[0]) < min(our_range[1], their_range[1])
            status = "OK" if overlap else f"CONFLICT (their `{dec['requirement']}` and our `{req}` have no version in common)"
        out.append({"package": ident, "ourRequirement": req, "theirVersion": f"rule `{dec.get('requirement')}`",
                    "status": status})
    return out


def build_plan(canon, dest):
    canon["targetsFull"] = {}
    if canon["historyRepo"]:
        canon["targetsFull"] = parse_manifest(
            git(canon["historyRepo"], "show", f"{canon['sourceCommit']}:Packages/Package.swift"))["targets"]
    dest_info = inspect_project(dest)

    # Le projet cible dépend-il déjà de waangu-chat ?
    ours_remote = [r for r in dest_info["remotePackages"] if r["identity"] == PACKAGE_IDENTITY]
    pin = next((p for p in dest_info["resolvedPins"] if p["identity"] == PACKAGE_IDENTITY), None)
    canonical_dep = None
    impostor = None
    for r in ours_remote:
        if normalize_origin(r["url"]) in CANONICAL_ORIGINS:
            canonical_dep = r
        else:
            impostor = r

    base, bases = None, []
    if canon["historyRepo"] and dest_info["gitRoot"] and any(n in dest_info["localModules"] for n in canon["required"] + canon["optional"]):
        bases = shared_bases(canon["historyRepo"], canon["sourceCommit"], dest_info["gitRoot"], dest_info["head"])
        base = bases[0] if bases else None

    modules = []
    for name in canon["required"] + canon["optional"]:
        required = name in canon["required"]
        copies = dest_info["localModules"].get(name, [])
        entry = {"module": name, "requiredByFeatureChat": required}
        if impostor:
            classification, evidence = "IMPOSTOR_OR_MIRROR", {"url": impostor["url"]}
        elif canonical_dep and copies:
            # Le package est déjà déclaré ET le projet garde sa propre copie : on
            # analyse quand même la copie, pour dire si elle peut juste être supprimée.
            classification, evidence = classify_copy(name, copies[0], canon, dest_info, base)
            evidence["packageAlreadyAdded"] = canonical_dep["url"]
            if len(copies) > 1:
                evidence["otherCopies"] = copies[1:]
        elif canonical_dep:
            classification = "CANONICAL"
            evidence = {"package": canonical_dep["url"], "pinnedVersion": pin and pin.get("version")}
        elif copies:
            classification, evidence = classify_copy(name, copies[0], canon, dest_info, base)
            if len(copies) > 1:
                evidence["otherCopies"] = copies[1:]
        else:
            classification, evidence = "MISSING", {}

        if classification == "COPY_SAME_LINEAGE":
            if evidence.get("localChanged", 0) == 0:
                decision, approval = "REPLACE_STALE_COPY", False
            else:
                decision, approval = "RECONCILE_THEN_REPLACE", True
        elif classification == "CANONICAL":
            pv = version_tuple(evidence.get("pinnedVersion"))
            cv = version_tuple(canon["version"])
            if pv and cv and pv < cv:
                same_line = pv[0] == cv[0] and (cv[0] > 0 or pv[1] == cv[1])
                decision, approval = "RAISE_REQUIREMENT", not same_line
            else:
                decision, approval = "NONE", False
        else:
            decision, approval = DECISIONS[classification]

        if not required and classification in ("MISSING", "CANONICAL"):
            decision, approval = "NONE", False  # module optionnel : rien à faire tant qu'il n'est pas utilisé
        elif not required and decision != "REPLACE_STALE_COPY":
            # Kit optionnel du même nom, que le projet n'utilise pas chez nous : un
            # conflit de nom n'est certain qu'à la résolution SwiftPM. On signale
            # sans bloquer ; si SwiftPM le refuse, il se traite comme un requis.
            decision, approval = "VERIFY_ON_RESOLVE", False
        if evidence.get("packageAlreadyAdded") and decision == "REPLACE_STALE_COPY":
            decision = "REMOVE_LOCAL_COPY"
        entry.update({"classification": classification, "decision": decision,
                      "requiresApproval": approval, "evidence": evidence})
        modules.append(entry)

    contract = canonical_host_contract(canon)
    host = dest_info["host"]
    host_todo = {
        "missingColors": [c for c in contract["colors"] if c not in host["assets"]],
        "missingImages": [i for i in contract["images"] if i not in host["assets"]],
        "missingUsageKeys": [k for k in contract["usageKeys"] if k not in host["plistKeys"]],
        "missingBackgroundModes": [b for b in contract["backgroundModes"] if b not in host["backgroundModes"]],
        "missingAppGroups": [g for g in contract["appGroups"] if g not in host["appGroups"]],
    }

    plan = {
        "schema": 1,
        "tool": {"name": "module_tool", "version": TOOL_VERSION},
        "request": {"feature": FEATURE, "package": PACKAGE_IDENTITY, "version": canon["version"],
                    "referenceMode": canon["mode"], "historyAvailable": bool(canon["historyRepo"]),
                    "releaseCommit": canon["releaseCommit"], "sourceCommit": canon["sourceCommit"]},
        "destination": {"path": dest_info["path"], "gitRoot": dest_info["gitRoot"],
                        "head": dest_info["head"], "branch": dest_info["branch"], "sharedBase": base, "sharedBases": bases},
        "modules": modules,
        "externalPackages": external_conflicts(canon, dest_info),
        "hostContract": host_todo,
        "inventory": {"manifests": dest_info["manifests"], "xcodeProjects": dest_info["xcodeProjects"]},
    }
    plan["requiredApprovals"] = [
        {"id": f"module:{m['module']}", "reason": f"{m['classification']} → {m['decision']}"}
        for m in modules if m["requiresApproval"]
    ] + [
        {"id": f"package:{p['package']}", "reason": p["status"]}
        for p in plan["externalPackages"] if p["status"].startswith("CONFLICT")
    ]
    plan["planId"] = "plan-" + hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()[:16]
    plan["createdAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    return plan


# ─── Rapports ────────────────────────────────────────────────────────────────

AUTO_TEXT = {
    "ADD_PRODUCT": "added automatically by SwiftPM",
    "NONE": "nothing to do",
    "REPLACE_STALE_COPY": "their copy has no local changes → replace it with ours",
    "REMOVE_LOCAL_COPY": "package already added; their copy has no local changes → delete their copy",
    "RAISE_REQUIREMENT": "raise the waangu-chat version requirement",
    "RECONCILE_THEN_REPLACE": "their copy has local changes → reconcile, then replace",
    "HUMAN": "a person decides",
    "REFUSED_UNCOMMITTED": "uncommitted changes in their copy → commit or stash first",
    "VERIFY_ON_RESOLVE": "same name as one of our kits: if SwiftPM reports a duplicate, treat it like a required module",
}


def module_line(m):
    e = m["evidence"]
    detail = ""
    if m["classification"] == "COPY_SAME_LINEAGE":
        detail = f"base {e['base'][:8]} · local {e['localChanged']} / upstream {e['upstreamChanged']} / both {e['bothChanged']}"
    elif m["classification"] in ("COPY_UNCHANGED", "COPY_MODIFIED", "STRANGER_LOCAL") and "files" in e:
        detail = (f"{e['files']} files: {e['identicalToPublished']} same as ours now, "
                  f"{e['files'] - e['identicalToPublished'] - e['changedByThemCount']} older version of ours, "
                  f"{e['changedByThemCount']} changed by them")
    elif m["classification"] == "CANONICAL":
        detail = f"waangu-chat {e.get('pinnedVersion') or '?'}"
    elif m["classification"] == "DIRTY":
        detail = f"{len(e.get('uncommitted', []))} uncommitted file(s)"
    return detail


def exit_code(plan):
    if any(m["decision"] == "REFUSED_UNCOMMITTED" for m in plan["modules"] if m["requiredByFeatureChat"]):
        return 2
    return 1 if plan["requiredApprovals"] else 0


def render_markdown(plan):
    d, r = plan["destination"], plan["request"]
    lines = [
        f"# Integration plan: {r['feature']} {r['version']} → {os.path.basename(d['path'])}",
        "",
        f"Plan `{plan['planId']}` · {plan['createdAt']} · module_tool {plan['tool']['version']} · read-only (nothing was changed)",
        "",
        "| | |", "|---|---|",
        f"| Destination | `{d['path']}` |",
        f"| Git | branch `{d['branch']}`, HEAD `{(d['head'] or '-')[:8]}` |",
        f"| Shared history with waangu-user-ios | {('yes, base `' + d['sharedBase'][:8] + '`' + (' (other merge-bases: ' + ', '.join('`' + b[:8] + '`' for b in d['sharedBases'][1:]) + ')' if len(d['sharedBases']) > 1 else '')) if d['sharedBase'] else 'no'} |",
        f"| Package | `{r['package']}` {r['version']} (release `{r['releaseCommit'][:8]}`, from `{r['sourceCommit'][:8]}`) |",
        f"| Reference | {'this published copy of waangu-chat' if r['referenceMode'] == 'release' else 'local branch packages-release'}"
        f"{'' if r['historyAvailable'] else ' · without waangu-user-ios history (copies compared file by file)'} |",
        "",
        "## Modules FeatureChat needs",
        "",
        "| Module | Found as | Evidence | What happens | Needs a person |",
        "|---|---|---|---|---|",
    ]
    for m in plan["modules"]:
        if m["requiredByFeatureChat"]:
            lines.append(f"| {m['module']} | {m['classification']} | {module_line(m)} | {AUTO_TEXT[m['decision']]} | "
                         f"{'**yes**' if m['requiresApproval'] else 'no'} |")
    optional = [m for m in plan["modules"] if not m["requiredByFeatureChat"] and m["classification"] != "MISSING"]
    if optional:
        lines += ["", "## Optional kits with the same name in the project", "",
                  "Not needed to compile FeatureChat. They matter only if the project also uses our version.", "",
                  "| Module | Found as | Evidence | What happens |", "|---|---|---|---|"]
        for m in optional:
            lines.append(f"| {m['module']} | {m['classification']} | {module_line(m)} | {AUTO_TEXT[m['decision']]} |")

    detail = [m for m in plan["modules"] if m["classification"] in ("COPY_SAME_LINEAGE", "COPY_MODIFIED", "STRANGER_LOCAL", "DIRTY")]
    if detail:
        lines += ["", "## Copies in detail", ""]
        for m in detail:
            e = m["evidence"]
            lines.append(f"### {m['module']}")
            lines.append(f"- Location: `{e.get('location')}`")
            if "files" in e:
                lines.append(f"- Files: {e['files']} · identical to published: {e['identicalToPublished']} · "
                             f"different: {e['differentFromPublished']} · only in their copy: {len(e['onlyInCopy'])} · "
                             f"only in ours: {e['onlyInPublished']}")
            if e.get("changedByThem") and m["classification"] != "COPY_SAME_LINEAGE":
                lines.append("- Changed by them (matches no version of ours: keep it, in our kit or in an app module):")
                lines += [f"  - `{f}`" for f in e["changedByThem"]]
            if e.get("bothChangedFiles"):
                lines.append("- Changed on both sides since the base (possible conflicts, run reconcile for real ones):")
                lines += [f"  - `{f}`" for f in e["bothChangedFiles"]]
            if e.get("localChangedFiles") and m["decision"] == "RECONCILE_THEN_REPLACE":
                only_local = [f for f in e["localChangedFiles"] if f not in e.get("bothChangedFiles", [])]
                if only_local:
                    lines.append("- Changed only on their side (keep: move to our kit or to an app module):")
                    lines += [f"  - `{f}`" for f in only_local]
            if e.get("onlyInCopy"):
                lines.append("- Files that exist only in their copy:")
                lines += [f"  - `{f}`" for f in e["onlyInCopy"]]
            if e.get("uncommitted"):
                lines.append("- Uncommitted:")
                lines += [f"  - `{f}`" for f in e["uncommitted"]]
            lines.append("")

    if plan["externalPackages"]:
        lines += ["## External packages already in the project", "",
                  "| Package | Our rule | Their version | Status |", "|---|---|---|---|"]
        for p in plan["externalPackages"]:
            lines.append(f"| {p['package']} | `{p['ourRequirement']}` | {p['theirVersion']} | {p['status']} |")
        lines.append("")

    h = plan["hostContract"]
    lines += ["## Host setup still missing (chat compiles without it, but won't fully work)", ""]
    rows = [("Colors", h["missingColors"]), ("Images", h["missingImages"]), ("Info.plist keys", h["missingUsageKeys"]),
            ("Background modes", h["missingBackgroundModes"]), ("App Group", h["missingAppGroups"])]
    for label, items in rows:
        lines.append(f"- [{' ' if items else 'x'}] {label}: {', '.join('`' + i + '`' for i in items) if items else 'present'}")
    lines += ["- [ ] `ChatDependencies`: build it like `makeChatDependencies()` in waangu-user-ios (not checked by the tool)", ""]

    lines += ["## Decisions needed", ""]
    if plan["requiredApprovals"]:
        lines += [f"- [ ] `{a['id']}`: {a['reason']}" for a in plan["requiredApprovals"]]
    else:
        lines.append("None: everything above is automatic.")
    return "\n".join(lines) + "\n"


def print_summary(plan):
    d = plan["destination"]
    print(f"Destination  {d['path']}  ({d['branch'] or 'no git'} @ {(d['head'] or '-')[:8]})")
    print(f"Package      waangu-chat {plan['request']['version']}   shared history: "
          f"{d['sharedBase'][:8] if d['sharedBase'] else 'no'}")
    print()
    for m in plan["modules"]:
        if not m["requiredByFeatureChat"] and m["classification"] == "MISSING":
            continue
        flag = "PERSON" if m["requiresApproval"] else "auto  "
        opt = "" if m["requiredByFeatureChat"] else " (optional)"
        print(f"  [{flag}] {m['module']:<22} {m['classification']:<18} {module_line(m)}{opt}")
    for p in plan["externalPackages"]:
        if p["status"] != "OK":
            print(f"  [PERSON] package {p['package']:<14} {p['status']} (theirs: {p['theirVersion']})")
    missing = sum(len(v) for v in plan["hostContract"].values())
    print(f"\nHost setup items missing: {missing}   Decisions needed: {len(plan['requiredApprovals'])}")


# ─── Fusion : une seule copie de chaque kit, dans le projet (option 1) ───────
#
# Un module Swift ne peut exister qu'une fois dans une app. Quand le projet a
# son propre `CoreKit` (même nom que le nôtre), `apply` en fait UNE copie :
#   - le package waangu-chat est copié dans le projet : `Vendor/waangu-chat/` ;
#   - chaque kit du même nom y est fusionné fichier par fichier avec leur copie
#     (fusion à trois : base commune, la nôtre, la leur — `git merge-file`) ;
#   - leur dossier en double est supprimé, et leur `Package.swift` pointe vers
#     `Vendor/waangu-chat` pour ces kits.
# Seuls les vrais conflits demandent une personne. Tout se fait dans un worktree
# Git, sur une nouvelle branche, sans commit : leur copie de travail n'est pas
# touchée. Sans kit en double, `apply` ajoute simplement la dépendance distante.
#
# Mise à jour (le projet a déjà `Vendor/waangu-chat`) : même commande depuis la
# nouvelle release ; base = l'ancienne release (tag Git de waangu-chat), nôtre =
# la nouvelle, leur = le dossier fusionné. Leurs changements sont conservés.

VENDOR_REL = os.path.join("Vendor", "waangu-chat")
STATE_REL = os.path.join("Tools", "MERGE_STATE.json")
DEFAULT_REMOTE_URL = "git@github.com:dondivinAsyst/waangu-chat-SDK.git"
NO_MERGE_SUFFIXES = (".pbxproj", ".entitlements", ".xcconfig")


def run_bytes(args, cwd=None):
    proc = subprocess.run(args, cwd=cwd, capture_output=True)
    if proc.returncode != 0:
        raise ToolError(f"{' '.join(args)} → {proc.stderr.decode(errors='replace').strip() or proc.returncode}")
    return proc.stdout


def is_binary(data):
    return b"\0" in data[:8192]


class FileSet:
    """Fichiers d'un arbre : chemin relatif → empreinte Git (+ lecture du contenu)."""

    def __init__(self, blobs, reader):
        self.blobs, self._reader = blobs, reader

    def read(self, rel):
        return self._reader(rel) if rel in self.blobs else None

    @staticmethod
    def from_dir(directory, prune=()):
        files = []
        for dp, dn, fs in os.walk(directory):
            dn[:] = [d for d in dn if d not in SKIP_DIRS and d not in prune]
            files += [os.path.join(dp, f) for f in fs if f != ".DS_Store"]
        files.sort()
        rels = [os.path.relpath(f, directory) for f in files]
        return FileSet(dict(zip(rels, hash_files(files))),
                       lambda rel: open(os.path.join(directory, rel), "rb").read())

    @staticmethod
    def from_git(repo, treeish):
        blobs = {}
        if git(repo, "rev-parse", "--verify", "-q", treeish, check=False).strip():
            for line in git(repo, "ls-tree", "-r", treeish).splitlines():
                meta, rel = line.split("\t", 1)
                if meta.split()[1] == "blob":
                    blobs[rel] = meta.split()[2]
        return FileSet(blobs, lambda rel: run_bytes(["git", "-C", repo, "cat-file", "blob", blobs[rel]]))

    def sub(self, prefix):
        prefix = prefix.rstrip("/") + "/"
        blobs = {r[len(prefix):]: b for r, b in self.blobs.items() if r.startswith(prefix)}
        return FileSet(blobs, lambda rel: self._reader(prefix + rel))


EMPTY = FileSet({}, lambda rel: None)


def release_fileset(canon):
    if canon["mode"] == "release":
        return FileSet.from_dir(canon["root"], prune=(".git",))
    return FileSet.from_git(canon["root"], RELEASE_BRANCH)


def merge_file(theirs, base, ours, label_theirs, label_ours):
    with tempfile.TemporaryDirectory() as d:
        paths = []
        for name, data in (("theirs", theirs), ("base", base or b""), ("ours", ours)):
            p = os.path.join(d, name)
            open(p, "wb").write(data)
            paths.append(p)
        style = ["--zdiff3"] if base is not None else []
        proc = subprocess.run(["git", "merge-file", "-p", *style, "-L", label_theirs, "-L", "base", "-L", label_ours,
                               *paths], capture_output=True)
        if proc.returncode < 0:
            raise ToolError(f"git merge-file failed: {proc.stderr.decode(errors='replace')}")
        return proc.stdout, proc.returncode  # code = nombre de conflits


TOP_TYPE_DECL = re.compile(rb"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|open|internal|final|fileprivate|private)\s+)*"
                           rb"(?:struct|class|enum|protocol|actor|typealias)\s+([A-Z]\w*)", re.M)


def declared_types(data):
    """Types déclarés au premier niveau d'un fichier Swift (commentaires ignorés)."""
    text = re.sub(rb"/\*.*?\*/", b"", data, flags=re.S)
    text = b"\n".join(l for l in text.split(b"\n") if not l.lstrip().startswith(b"//"))
    return {m.decode() for m in TOP_TYPE_DECL.findall(text)}


def pair_moved_files(ours, theirs):
    """({leur chemin: notre chemin}, {leur chemin: (notre chemin, score)}) : fichiers déplacés.

    Un fichier présent seulement chez eux et un autre seulement chez nous sont le même
    fichier s'ils portent le même nom (unique de chaque côté), sinon si leurs contenus
    se ressemblent nettement — ce second cas n'est que SIGNALÉ (deux DTO voisins peuvent se
    ressembler sans être le même fichier ; fusionner ferait perdre l'un). Sans cela, la fusion garderait les deux et le module
    déclarerait deux fois le même type (cas réel : Storable.swift déplacé de
    Protocols/Database/ vers Protocols/Storage/Database/)."""
    import difflib
    ours_only = sorted(set(ours.blobs) - set(theirs.blobs))
    theirs_only = sorted(set(theirs.blobs) - set(ours.blobs))
    pairs, maybe = {}, {}
    by_name_o, by_name_t = {}, {}
    for r in ours_only:
        by_name_o.setdefault(os.path.basename(r), []).append(r)
    for r in theirs_only:
        by_name_t.setdefault(os.path.basename(r), []).append(r)
    for name, ts in by_name_t.items():
        os_ = by_name_o.get(name, [])
        if len(ts) == 1 and len(os_) == 1:
            pairs[ts[0]] = os_[0]
    rest_o = [r for r in ours_only if r not in pairs.values() and r.endswith(".swift")]
    rest_t = [r for r in theirs_only if r not in pairs and r.endswith(".swift")]
    if rest_o and rest_t and len(rest_o) * len(rest_t) <= 20000:
        texts_o = {r: (ours.read(r) or b"").decode("utf-8", "replace") for r in rest_o}
        for t in rest_t:
            tt = (theirs.read(t) or b"").decode("utf-8", "replace")
            best, score = None, 0.0
            for o, ot in texts_o.items():
                sm = difflib.SequenceMatcher(None, tt, ot)
                if sm.real_quick_ratio() < 0.7 or sm.quick_ratio() < 0.7:
                    continue
                r = sm.ratio()
                if r > score:
                    best, score = o, r
            if best and score >= 0.7:
                maybe[t] = (best, round(score, 2))
    return pairs, maybe


def merge_trees(ours, theirs, base, known, label_theirs, label_ours):
    """Fusion fichier par fichier. Renvoie (contenu fusionné {rel: bytes}, décisions)."""
    merged, decisions = {}, []

    def decide(rel, outcome, person=False, note=""):
        decisions.append({"file": rel, "outcome": outcome, "person": person, "note": note})

    _our_types = []

    def our_types():
        if not _our_types:
            names = set()
            for r in ours.blobs:
                if r.endswith(".swift"):
                    names |= declared_types(ours.read(r) or b"")
            _our_types.append(names)
        return _our_types[0]

    # Fichiers déplacés/renommés : leur version est fusionnée sous NOTRE chemin.
    moves, maybe_moves = pair_moved_files(ours, theirs)
    for their_path, (our_path, score) in sorted(maybe_moves.items()):
        decide(their_path, f"maybe moved/renamed: looks like our {our_path} ({int(score * 100)}% similar). "
                           f"If it is the same file, merge it into ours and delete this one", person=True)
    if moves:
        t_blobs = {moves.get(r, r): bl for r, bl in theirs.blobs.items()}
        reverse = {v: k for k, v in moves.items()}
        theirs = FileSet(t_blobs, lambda rel, _old=theirs: _old.read(reverse.get(rel, rel)))
        for their_path, our_path in sorted(moves.items()):
            decide(our_path, f"moved/renamed: their {their_path} merged here (our path)")

    for rel in sorted(set(ours.blobs) | set(theirs.blobs)):
        o, t, b = ours.blobs.get(rel), theirs.blobs.get(rel), base.blobs.get(rel)
        if t is None:
            merged[rel] = ours.read(rel)
            if b is not None and b != o:
                decide(rel, "deleted by them, changed by us: ours kept", person=True)
            elif b is not None:
                decide(rel, "deleted by them: ours kept (chat needs it)", person=True)
            else:
                decide(rel, "ours (they never had it)")
            continue
        if o is None:
            if t in known or (b is not None and t == b):
                lost = declared_types(theirs.read(rel) or b"") - our_types()
                if lost:
                    # Leur code peut encore s'en servir (cas réel : `Routing`, retiré chez
                    # nous, utilisé par 8 fichiers de leur app) : on garde leur fichier.
                    merged[rel] = theirs.read(rel)
                    decide(rel, f"removed by us but still declares {', '.join(sorted(lost))}, which ours no longer "
                                f"has: theirs kept (their code may use it)")
                    continue
                decide(rel, "removed by us, never changed by them: dropped")
            elif b is not None:
                merged[rel] = theirs.read(rel)
                decide(rel, "changed by them, removed by us: theirs kept", person=True)
            else:
                merged[rel] = theirs.read(rel)
                decide(rel, "added by them: kept")
            continue
        if o == t:
            merged[rel] = ours.read(rel)
            continue
        if t in known or (b is not None and t == b):
            merged[rel] = ours.read(rel)
            decide(rel, "older version of ours: updated to ours")
            continue
        if b is not None and b == o:
            merged[rel] = theirs.read(rel)
            decide(rel, "changed only by them: theirs kept")
            continue
        o_data, t_data = ours.read(rel), theirs.read(rel)
        b_data = base.read(rel) if b is not None else None
        if rel.endswith(NO_MERGE_SUFFIXES) or is_binary(o_data) or is_binary(t_data):
            merged[rel] = o_data
            decide(rel, "binary or project file changed on both sides: ours kept, theirs in the report", person=True)
            continue
        result, conflicts = merge_file(t_data, b_data, o_data, label_theirs, label_ours)
        merged[rel] = result
        if conflicts:
            how = "3-way" if b_data is not None else "no common base: 2-way"
            decide(rel, f"CONFLICT ({conflicts} hunk(s), {how}): markers written", person=True)
        else:
            decide(rel, "changed on both sides: merged automatically")
    return merged, decisions


# ── Édition du Package.swift (texte, commentaires et mise en forme conservés) ──

def mask_comments(src):
    """Même longueur que `src`, commentaires remplacés par des espaces (les chaînes restent)."""
    out, i, n, in_str = list(src), 0, len(src), False
    while i < n:
        c = src[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def close_of(masked, open_idx):
    """Index du caractère fermant correspondant à `masked[open_idx]` ( ( ou [ )."""
    pairs = {"(": ")", "[": "]"}
    stack, i, in_str = [], open_idx, False
    while i < len(masked):
        c = masked[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in pairs:
            stack.append(pairs[c])
        elif c in ")]":
            stack.pop()
            if not stack:
                return i
        i += 1
    raise ToolError("Package.swift: unclosed parenthesis or bracket")


def calls(masked, kinds):
    """[(début, fin_exclue, type)] des appels `.kind(`…`)` au niveau du texte."""
    out = []
    for m in re.finditer(r"\.(%s)\s*\(" % "|".join(kinds), masked):
        end = close_of(masked, m.end() - 1) + 1
        out.append((m.start(), end, m.group(1)))
    return out


def call_name(src, start, end):
    m = re.search(r'name:\s*"([^"]+)"', src[start:end])
    return m.group(1) if m else None


def argument_array(masked, start, end, key):
    """(index du « [ », index du « ] ») de l'argument `key: [ … ]` au premier niveau de l'appel."""
    open_paren = masked.index("(", start)
    depth, i, in_str = 0, open_paren + 1, False
    while i < end - 1:
        c = masked[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif depth == 0 and masked.startswith(key, i) and re.match(r"%s\s*:\s*\[" % key, masked[i:]) \
                and not (masked[i - 1].isalnum() or masked[i - 1] == "_"):
            lb = masked.index("[", i)
            return lb, close_of(masked, lb)
        i += 1
    return None


def array_elements(masked, lb, rb):
    """Éléments de premier niveau d'un tableau : [(début, fin_exclue)] sans les espaces."""
    out, depth, start, i, in_str = [], 0, lb + 1, lb + 1, False
    while i <= rb:
        c = masked[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "([":
            depth += 1
        elif c in ")]" and i < rb:
            depth -= 1
        elif (c == "," and depth == 0) or i == rb:
            a, b = start, i
            while a < b and masked[a].isspace():
                a += 1
            while b > a and masked[b - 1].isspace():
                b -= 1
            if a < b:
                out.append((a, b))
            start = i + 1
        i += 1
    return out


def element_target_name(text):
    m = re.fullmatch(r'"([^"]+)"', text) or re.fullmatch(r'\.(?:target|byName)\s*\(\s*name:\s*"([^"]+)"[^)]*\)', text)
    return m.group(1) if m else None


def removal_span(src, start, end):
    """Étend [début, fin) pour retirer aussi la virgule qui suit, la ligne vide laissée et le
    bloc de commentaires collé juste au-dessus (ex. `// MARK: - CoreKit`)."""
    span = _removal_span(src, start, end)
    line_start = span[0]
    if line_start == src.rfind("\n", 0, start) + 1:  # l'appel commence sa ligne
        while line_start > 0:
            prev = src.rfind("\n", 0, line_start - 1) + 1
            if src[prev:line_start].strip().startswith("//"):
                line_start = prev
            else:
                break
    return line_start, span[1]


def _removal_span(src, start, end):
    j = end
    while j < len(src) and src[j] in " \t":
        j += 1
    if j < len(src) and src[j] == ",":
        j += 1
    k = j
    while k < len(src) and src[k] in " \t":
        k += 1
    if k < len(src) and src[k] == "\n":
        line_start = src.rfind("\n", 0, start) + 1
        if src[line_start:start].strip() == "":
            return line_start, k + 1
    return start, j


def rewrite_manifest(src, kits, package_line, add_product_to=None):
    """Retire les targets/produits `kits`, redirige les dépendances vers waangu-chat,
    ajoute la dépendance de package. Renvoie (nouveau texte, notes)."""
    notes, edits = [], []  # edits : (début, fin, remplacement)
    masked = mask_comments(src)
    product_expr = lambda name: f'.product(name: "{name}", package: "{PACKAGE_IDENTITY}")'

    all_calls = calls(masked, ["target", "testTarget", "executableTarget", "macro", "plugin", "library", "binaryTarget"])
    for start, end, kind in all_calls:
        name = call_name(masked, start, end)
        if kind == "library":
            arr = argument_array(masked, start, end, "targets")
            if not arr:
                continue
            elems = array_elements(masked, *arr)
            keep = [e for e in elems if element_target_name(src[e[0]:e[1]]) not in kits]
            if len(keep) == len(elems):
                continue
            if not keep:
                edits.append((*_removal_span(src, start, end), ""))  # produits : on garde les commentaires de section
                notes.append(f"product `{name}` removed (it now comes from waangu-chat)")
            else:
                edits.append((arr[0] + 1, arr[1], ", ".join(src[a:b] for a, b in keep)))
                notes.append(f"product `{name}`: kits from waangu-chat removed from its targets")
            continue
        if kind in ("target", "binaryTarget") and name in kits:
            edits.append((*removal_span(src, start, end), ""))
            notes.append(f"target `{name}` removed (merged into Vendor/waangu-chat)")
            continue
        arr = argument_array(masked, start, end, "dependencies")
        replaced = []
        if arr:
            for a, b in array_elements(masked, *arr):
                dep = element_target_name(src[a:b])
                if dep in kits:
                    edits.append((a, b, product_expr(dep)))
                    replaced.append(dep)
        if name == add_product_to:
            insert = product_expr(FEATURE)
            if arr:
                edits.append((arr[0] + 1, arr[0] + 1, insert + ", "))
            else:
                nm = re.search(r'name:\s*"[^"]+"\s*,?', src[start:end])
                pos = start + nm.end()
                edits.append((pos, pos, f" dependencies: [{insert}],"))
            notes.append(f"`{FEATURE}` added to target `{name}`")
        if replaced:
            notes.append(f"`{name}`: {', '.join(sorted(set(replaced)))} now from waangu-chat"
                         + (" (test target: check `@testable import` still builds)" if kind == "testTarget" else ""))
    if add_product_to and not any(call_name(masked, s, e) == add_product_to for s, e, k in all_calls if k != "library"):
        raise ToolError(f"target `{add_product_to}` not found in Package.swift")

    pkg = re.search(r"\bPackage\s*\(", masked)
    if not pkg:
        raise ToolError("no Package( call found in the manifest")
    pstart, pend = pkg.start(), close_of(masked, pkg.end() - 1) + 1
    # `dependencies:` de premier niveau dans l'appel Package( (pas celles des targets)
    deps = argument_array(masked, pstart, pend, "dependencies")
    if deps:
        lb = deps[0]
        indent = re.search(r"\n([ \t]*)\S", src[lb:]).group(1) if re.search(r"\n([ \t]*)\S", src[lb:]) else "        "
        edits.append((lb + 1, lb + 1, f"\n{indent}{package_line},"))
    else:
        tg = re.search(r"\n([ \t]*)targets\s*:", masked[pstart:pend])
        if not tg:
            raise ToolError("neither `dependencies:` nor `targets:` in Package(")
        pos = pstart + tg.start() + 1
        ind = tg.group(1)
        edits.append((pos, pos, f"{ind}dependencies: [\n{ind}    {package_line},\n{ind}],\n"))
    notes.append(f"package dependency added: `{package_line}`")

    out = src
    for a, b, text in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
        out = out[:a] + text + out[b:]
    if edits:
        out = re.sub(r"\n(?:[ \t]*\n){2,}", "\n\n", out)  # les blocs retirés ne laissent pas de trous
    return out, notes


def verify_manifest(path):
    """`swift package dump-package` : le manifeste se charge-t-il ? (pas de compilation du projet)"""
    proc = subprocess.run(["swift", "package", "dump-package"], cwd=os.path.dirname(path), capture_output=True, text=True)
    if proc.returncode != 0:
        return False, (proc.stderr or proc.stdout).strip()[-2000:]
    return True, ""


# ── Plan de fusion et application ──

def find_vendored(dest):
    for path in find_files(dest, name="MERGE_STATE.json"):
        if path.endswith(os.path.join(VENDOR_REL, STATE_REL)):
            return os.path.dirname(os.path.dirname(path))
    return None


def kit_compatibility(kit, manifest, merged, canon, merged_kits, plan):
    """Ce que leur version du kit demandait et que la nôtre n'a pas : dépendances, ressources, imports."""
    out = []
    theirs = parse_manifest(open(manifest, encoding="utf-8").read())["targets"].get(kit, {})
    ours = canon["targets"][kit]
    our_deps = set(ours["dependencies"]) | {p["name"] for p in ours["productDependencies"]}
    our_all = set(our_deps)
    for d in list(our_deps):
        our_all |= closure(canon["targets"], d)
    extra = [d for d in theirs.get("dependencies", []) if d not in merged_kits and d not in our_all]
    extra += [p["name"] for p in theirs.get("productDependencies", []) if p["name"] not in our_all]
    kit_path = ours["path"]
    if extra:
        out.append({"file": f"{kit_path} (target)", "person": True, "note": "",
                    "outcome": f"their {kit} also depended on {', '.join(sorted(set(extra)))}, which waangu-chat's "
                               f"{kit} does not: code using it won't compile in the merged copy"})
    if theirs.get("resources") and not ours.get("resources"):
        out.append({"file": f"{kit_path} (target)", "person": True, "note": "",
                    "outcome": f"their {kit} declared resources; waangu-chat's {kit} declares none, so their "
                               f"resource files won't be bundled"})
    their_modules = set(plan["inventory"]["manifests"] and sum((m["targets"] for m in plan["inventory"]["manifests"]), []))
    foreign = (their_modules - merged_kits - set(canon["targets"])) | set(extra)
    used = {}
    for rel, data in merged.items():
        if data is None or not rel.endswith(".swift"):
            continue
        for m in re.finditer(rb"^[ \t]*(?:@\w+[ \t]+)*import[ \t]+(?:(?:typealias|struct|class|enum|protocol|let|var|func)[ \t]+)?(\w+)", data, re.M):
            name = m.group(1).decode()
            if name in foreign:
                used.setdefault(name, []).append(rel)
    for name, files in sorted(used.items()):
        out.append({"file": f"{kit_path}/{files[0]}", "person": True, "note": "",
                    "outcome": f"imports {name}, a module of their app that waangu-chat's {kit} cannot depend on "
                               f"({len(files)} file(s))"})
    return out


TYPE_DECL = re.compile(rb"\b(?:struct|class|enum|protocol|actor)\s+([A-Z]\w*)")


def review_after_conflicts(sides, added=None):
    """Fichiers mis à jour automatiquement qui utilisent un type déclaré dans un fichier en conflit.

    Si la personne garde LEUR côté de ce fichier, l'API du type peut différer de
    celle que le fichier automatique attend (cas réel : WalletBalanceHeroView mis à
    jour vers notre version, qui appelle RemoteImage à notre façon, alors que leur
    RemoteImage a été gardé)."""
    conflicted = {}
    for kit_path, ours, theirs, merged, dec in sides:
        for d in dec:
            if d["person"] and d["outcome"].startswith("CONFLICT"):
                rel = d["file"][len(kit_path) + 1:]
                for side in (ours, theirs):
                    data = side.read(rel) or b""
                    for name in TYPE_DECL.findall(data):
                        conflicted.setdefault(name.decode(), d["file"])
    if not conflicted:
        return []
    pattern = re.compile(rb"\b(" + b"|".join(re.escape(n.encode()) for n in sorted(conflicted)) + rb")\b")
    out = []
    # Modules ajoutés tels quels (FeatureChat…) : c'est notre code, il dépend de NOS types.
    for path, tree in sorted((added or {}).items()):
        for rel, data in sorted(tree.items()):
            if not data or not rel.endswith(".swift"):
                continue
            used = sorted({m.decode() for m in pattern.findall(data)})
            if used:
                out.append({"file": f"{path}/{rel}", "uses": used, "conflictFiles": sorted({conflicted[u] for u in used})})
    for kit_path, ours, theirs, merged, dec in sides:
        # Seuls les fichiers où NOTRE version a été prise risquent de ne plus coller à
        # LEUR version d'un fichier en conflit ; ceux où la leur a été gardée y collent déjà.
        took_ours = ("older version of ours", "ours (they never had it)", "merged automatically")
        auto = {d["file"][len(kit_path) + 1:] for d in dec
                if not d["person"] and any(t in d["outcome"] for t in took_ours)}
        for rel in sorted(auto):
            data = merged.get(rel)
            if not data or not rel.endswith(".swift"):
                continue
            full = f"{kit_path}/{rel}"
            used = sorted({m.decode() for m in pattern.findall(data) if conflicted[m.decode()] != full})
            if used:
                out.append({"file": full, "uses": used, "conflictFiles": sorted({conflicted[u] for u in used})})
    return out


def build_merge(canon, dest, history=None, layout="inplace"):
    """Prépare la fusion (sans rien écrire). Renvoie un dict décrivant tout ce qu'`apply` fera."""
    dest = os.path.abspath(dest)
    rel_fs = release_fileset(canon)
    label_ours = f"waangu-chat {canon['version']}"

    inplace_state = find_inplace_state(dest)
    if inplace_state:  # ── mise à jour d'une fusion sur place
        return build_update_inplace(canon, inplace_state, rel_fs, label_ours)

    vendored = find_vendored(dest)
    if vendored:  # ── mise à jour d'une copie déjà fusionnée
        state = json.load(open(os.path.join(vendored, STATE_REL)))
        old = state["version"]
        if old == canon["version"]:
            raise ToolError(f"{vendored} is already on waangu-chat {old}")
        if canon["mode"] != "release" or not git(canon["root"], "rev-parse", "--verify", "-q", f"{old}^{{commit}}",
                                                 check=False).strip():
            raise ToolError(f"base version {old} not found: run the tool from a FULL clone of waangu-chat "
                            f"(git clone without --depth), which has the tag {old}")
        base_fs = FileSet.from_git(canon["root"], f"{old}^{{tree}}")
        theirs_fs = FileSet.from_dir(vendored, prune=("Tools",))
        unresolved = [r for r in theirs_fs.blobs
                      if not is_binary(theirs_fs.read(r) or b"") and re.search(rb"^<<<<<<< ", theirs_fs.read(r) or b"", re.M)]
        if unresolved:
            return {"mode": "update", "from": old, "to": canon["version"], "vendoredDir": vendored, "files": {},
                    "tools": {}, "decisions": [], "kits": state.get("kits", []), "manifests": [], "warnings": [],
                    "blockers": [f"unresolved conflict markers from the previous merge in {len(unresolved)} file(s), "
                                 f"e.g. {unresolved[0]}: resolve and commit them first"]}
        ours_fs = FileSet({r: b for r, b in rel_fs.blobs.items() if not r.startswith("Tools/")}, rel_fs.read)
        base_fs = FileSet({r: b for r, b in base_fs.blobs.items() if not r.startswith("Tools/")}, base_fs.read)
        merged, decisions = merge_trees(ours_fs, theirs_fs, base_fs, set(),
                                        f"theirs (merged {old})", label_ours)
        tools = {r: rel_fs.read(r) for r in rel_fs.blobs if r.startswith("Tools/")}
        return {"mode": "update", "from": old, "to": canon["version"], "vendoredDir": vendored,
                "files": merged, "tools": tools, "decisions": decisions,
                "kits": state.get("kits", []), "manifests": [], "blockers": [], "warnings": []}

    plan = build_plan(canon, dest)
    blockers, warnings = [], []
    dest_info_manifests = {m["file"] for m in plan["inventory"]["manifests"]}
    by_manifest = {}
    for m in plan["modules"]:
        cls = m["classification"]
        if cls in ("MISSING", "CANONICAL"):
            continue
        if cls == "DIRTY":
            blockers.append(f"{m['module']}: uncommitted changes in their copy (commit or stash first)")
        elif cls == "STRANGER_LOCAL":
            blockers.append(f"{m['module']}: their module has the same name but unrelated code; a person decides "
                            f"(rename theirs) before merging")
        elif cls == "IMPOSTOR_OR_MIRROR":
            blockers.append(f"waangu-chat is declared from another URL: {m['evidence'].get('url')}")
        else:
            loc = m["evidence"].get("location")
            manifest = next((f for f in dest_info_manifests
                             if loc and os.path.dirname(f) == os.path.commonpath([os.path.dirname(f), loc])), None)
            if not manifest or not loc or not os.path.isdir(loc):
                blockers.append(f"{m['module']}: copy is not a SwiftPM target folder ({loc}); not merged automatically")
            else:
                by_manifest.setdefault(manifest, []).append((m["module"], loc, m))
    for p in plan["externalPackages"]:
        if p["status"].startswith("CONFLICT"):
            warnings.append(f"{p['package']}: {p['status']} (theirs {p['theirVersion']}). SwiftPM won't resolve "
                            f"until a person aligns the versions.")

    if by_manifest and layout == "inplace":
        return build_merge_inplace(canon, dest, plan, by_manifest, blockers, warnings, rel_fs, label_ours)

    kits = []
    files = {}
    decisions = []
    base_mode = "none"
    sides = []
    for manifest, entries in by_manifest.items():
        for kit, loc, m in entries:
            kit_path = canon["targets"][kit]["path"]
            ours = rel_fs.sub(kit_path)
            theirs = FileSet.from_dir(loc)
            base = EMPTY
            if m["classification"] == "COPY_SAME_LINEAGE" and canon["historyRepo"]:
                base = FileSet.from_git(canon["historyRepo"], f"{m['evidence']['base']}:Packages/{kit_path}")
                base_mode = "lineage"
            known = canon["knownBlobs"](list(theirs.blobs.values()))  # versions (anciennes ou non) des nôtres
            merged, dec = merge_trees(ours, theirs, base, known, f"theirs ({os.path.basename(dest)})", label_ours)
            for d in dec:
                d["file"] = f"{kit_path}/{d['file']}"
            decisions += dec
            decisions += kit_compatibility(kit, manifest, merged, canon, {k for k, _, _ in entries}, plan)
            sides.append((kit_path, ours, theirs, merged, dec))
            files.update({f"{kit_path}/{r}": data for r, data in merged.items()})
            kits.append({"kit": kit, "theirCopy": loc, "manifest": manifest, "path": kit_path,
                         "classification": m["classification"]})
    return {"mode": "first" if kits else "remote", "to": canon["version"], "kits": kits, "files": files,
            "decisions": decisions, "baseMode": base_mode, "blockers": blockers, "warnings": warnings,
            "plan": plan, "manifests": sorted(by_manifest), "reviewAfterConflicts": review_after_conflicts(sides)}


# ─── Fusion SUR PLACE (mise en page par défaut) ──────────────────────────────
#
# Les kits fusionnés restent dans LEURS dossiers (`Packages/Sources/CoreKit`…) ;
# les autres modules de waangu-chat (FeatureChat, ScreenShareTransport…) sont
# copiés à côté, dans le même `Sources/`, et déclarés comme targets de LEUR
# `Package.swift`, avec les packages externes dont ils ont besoin. Pas de second
# package, pas de `Vendor/`, et leurs produits gardent leurs noms : rien à
# relier dans Xcode.
#
# État : `<dossier du Package.swift>/.waangu-chat/MERGE_STATE.json`.

INPLACE_STATE_REL = os.path.join(".waangu-chat", "MERGE_STATE.json")


def find_inplace_state(dest):
    for path in find_files(dest, name="MERGE_STATE.json"):
        if path.endswith(INPLACE_STATE_REL):
            return path
    return None


def manifest_call_texts(src, kinds):
    """{nom: texte source exact} des appels `.kind(name: …)` d'un manifeste."""
    masked = mask_comments(src)
    out = {}
    for start, end, kind in calls(masked, kinds):
        name = call_name(masked, start, end)
        if name:
            out[name] = src[start:end]
    return out


def manifest_package_texts(src):
    """{identité: texte source} des `.package(url: …)` de premier niveau d'un manifeste."""
    masked = mask_comments(src)
    pkg = re.search(r"\bPackage\s*\(", masked)
    out = {}
    if not pkg:
        return out
    pend = close_of(masked, pkg.end() - 1) + 1
    deps = argument_array(masked, pkg.start(), pend, "dependencies")
    if not deps:
        return out
    for a, b in array_elements(masked, *deps):
        text = src[a:b]
        m = re.search(r'url:\s*"([^"]+)"', text)
        if m:
            out[package_identity(m.group(1))] = text
    return out


def dependency_exprs(target_text):
    """Éléments du tableau `dependencies:` d'un texte `.target(...)`, tels qu'écrits."""
    masked = mask_comments(target_text)
    arr = argument_array(masked, 0, len(masked), "dependencies")
    if not arr:
        return []
    return [target_text[a:b] for a, b in array_elements(masked, *arr)]


def dep_key(expr):
    """Clé de comparaison d'une dépendance : nom du module ou du produit."""
    name = element_target_name(expr)
    if name:
        return name
    m = re.search(r'\.product\s*\(\s*name:\s*"([^"]+)"', expr)
    return m.group(1) if m else expr.strip()


def reindent(text, indent):
    lines = text.split("\n")
    base = len(lines[-1]) - len(lines[-1].lstrip()) if len(lines) > 1 else 0
    shift = indent - base if len(lines) > 1 else 0
    out = [indent * " " + lines[0].lstrip()]
    for l in lines[1:]:
        if not l.strip():
            out.append("")
        elif shift >= 0:
            out.append(" " * shift + l)
        else:
            out.append(l[min(-shift, len(l) - len(l.lstrip())):])
    return "\n".join(out)


def edit_manifest_inplace(src, add_packages, add_targets, add_deps, add_feature_to, header):
    """Ajouts seulement (rien n'est retiré) : packages externes, targets, dépendances.

    add_packages : [texte `.package(...)`] ; add_targets : [texte `.target(...)`] ;
    add_deps : {target: [expr]} ; add_feature_to : target qui reçoit FeatureChat."""
    masked = mask_comments(src)
    edits, notes = [], []
    pkg = re.search(r"\bPackage\s*\(", masked)
    if not pkg:
        raise ToolError("no Package( call found in the manifest")
    pstart, pend = pkg.start(), close_of(masked, pkg.end() - 1) + 1

    if add_packages:
        deps = argument_array(masked, pstart, pend, "dependencies")
        if deps:
            lb = deps[0]
            m = re.search(r"\n([ \t]*)\S", src[lb:deps[1]])
            ind = len(m.group(1)) if m else 8
            text = "".join("\n" + reindent(p, ind) + "," for p in add_packages)
            edits.append((lb + 1, lb + 1, f"\n{' ' * ind}// {header}{text}"))
        else:
            tg = re.search(r"\n([ \t]*)targets\s*:", masked[pstart:pend])
            if not tg:
                raise ToolError("neither `dependencies:` nor `targets:` in Package(")
            pos, ind = pstart + tg.start() + 1, tg.group(1)
            body = "".join(reindent(p, len(ind) + 4) + ",\n" for p in add_packages)
            edits.append((pos, pos, f"{ind}// {header}\n{ind}dependencies: [\n{body}{ind}],\n"))
        idents = [package_identity(re.search(r'url:\s*"([^"]+)"', p).group(1)) for p in add_packages]
        notes.append("external packages added: " + ", ".join(idents))

    targets_by_name = {}
    for start, end, kind in calls(masked, ["target", "executableTarget", "testTarget"]):
        nm = call_name(masked, start, end)
        if nm:
            targets_by_name[nm] = (start, end)

    for name, exprs in add_deps.items():
        if not exprs or name not in targets_by_name:
            continue
        start, end = targets_by_name[name]
        arr = argument_array(masked, start, end, "dependencies")
        if arr:
            elems = array_elements(masked, *arr)
            if elems:
                last_end = elems[-1][1]
                edits.append((last_end, last_end, "".join(", " + e for e in exprs)))
            else:
                edits.append((arr[0] + 1, arr[0] + 1, ", ".join(exprs)))
        else:
            nm = re.search(r'name:\s*"[^"]+"\s*,?', src[start:end])
            pos = start + nm.end()
            edits.append((pos, pos, f" dependencies: [{', '.join(exprs)}],"))
        notes.append(f"`{name}`: added {', '.join(dep_key(e) for e in exprs)}")

    if add_feature_to:
        if add_feature_to not in targets_by_name:
            raise ToolError(f"target `{add_feature_to}` not found in Package.swift")

    if add_targets:
        tarr = argument_array(masked, pstart, pend, "targets")
        if not tarr:
            raise ToolError("no `targets:` in Package(")
        elems = array_elements(masked, *tarr)
        ind = 8
        if elems:
            line_start = src.rfind("\n", 0, elems[0][0]) + 1
            ind = elems[0][0] - line_start
        close = tarr[1]
        before = src[:close].rstrip()
        needs_comma = elems and not before.endswith(",")
        insert_at = len(before)
        text = ("," if needs_comma else "") + f"\n\n{' ' * ind}// MARK: - {header}\n" + \
               "".join(reindent(t, ind) + ",\n\n" for t in add_targets).rstrip() + "\n"
        edits.append((insert_at, insert_at, text))
        notes.append(f"targets added: {', '.join(call_name(mask_comments(t), 0, len(t)) for t in add_targets)}")

    out = src
    for a, b, text in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
        out = out[:a] + text + out[b:]
    return out, notes


def build_merge_inplace(canon, dest, plan, by_manifest, blockers, warnings, rel_fs, label_ours):
    """Première intégration, sur place. Ne touche à rien : décrit ce qu'`apply` écrira."""
    if len(by_manifest) > 1:
        blockers.append("the same-name kits are spread over several Package.swift files; merge in place needs one")
    manifest = next(iter(by_manifest))
    mdir = os.path.dirname(manifest)
    their_src = open(manifest, encoding="utf-8").read()
    their_targets = parse_manifest(their_src)["targets"]
    our_src = rel_fs.read("Package.swift").decode()
    our_target_texts = manifest_call_texts(our_src, ["target"])
    our_packages = manifest_package_texts(our_src)
    their_packages = {p["identity"] for p in parse_manifest(their_src)["packages"] if "url" in p}

    entries = by_manifest[manifest]
    merged_names = {k for k, _, _ in entries}
    files, decisions, kits, sides = {}, [], [], []
    base_mode = "none"

    for kit, loc, m in entries:
        kit_path = canon["targets"][kit]["path"]
        ours = rel_fs.sub(kit_path)
        theirs = FileSet.from_dir(loc)
        base = EMPTY
        if m["classification"] == "COPY_SAME_LINEAGE" and canon["historyRepo"]:
            base = FileSet.from_git(canon["historyRepo"], f"{m['evidence']['base']}:Packages/{kit_path}")
            base_mode = "lineage"
        known = canon["knownBlobs"](list(theirs.blobs.values()))
        merged, dec = merge_trees(ours, theirs, base, known, f"theirs ({os.path.basename(dest)})", label_ours)
        rel_loc = os.path.relpath(loc, mdir)
        for d in dec:
            d["file"] = f"{rel_loc}/{d['file']}"
        decisions += dec
        sides.append((rel_loc, ours, theirs, merged, dec))
        files[rel_loc] = merged
        kits.append({"kit": kit, "path": rel_loc, "classification": m["classification"]})

    # Modules de waangu-chat que l'app n'a pas : copiés tels quels dans son Sources/.
    new_modules = []
    for name, t in sorted(canon["targets"].items()):
        if name in merged_names:
            continue
        if name in their_targets:
            blockers.append(f"{name}: the app already declares a target with this name that is not a copy of ours")
            continue
        target_dir = os.path.join(mdir, t["path"])
        if os.path.isdir(target_dir) and any(f != ".DS_Store" for _, _, fs in os.walk(target_dir) for f in fs):
            blockers.append(f"{name}: folder {os.path.relpath(target_dir, mdir)} already exists with files")
            continue
        files[t["path"]] = {r: rel_fs.read(f"{t['path']}/{r}") for r in rel_fs.sub(t["path"]).blobs}
        new_modules.append(name)

    # Package.swift : ajouts seulement.
    needed_packages = set()
    for name in new_modules + sorted(merged_names):
        for p in canon["targets"][name]["productDependencies"]:
            needed_packages.add(p["package"].lower())
    add_packages = [our_packages[i] for i in sorted(needed_packages) if i in our_packages and i not in their_packages]
    add_targets = [our_target_texts[n] for n in new_modules if n in our_target_texts]
    add_deps = {}
    for name in merged_names:
        have = {dep_key(e) for e in dependency_exprs(manifest_call_texts(their_src, ["target"]).get(name, ""))}
        missing = [e for e in dependency_exprs(our_target_texts.get(name, "")) if dep_key(e) not in have]
        if missing:
            add_deps[name] = missing
    for name, t in canon["targets"].items():
        if name in merged_names and t.get("resources") and not their_targets.get(name, {}).get("resources"):
            decisions.append({"file": f"{t['path']} (target)", "person": True, "note": "",
                              "outcome": f"our {name} declares resources and yours doesn't: add `resources:` to your "
                                         f"{name} target"})

    return {"mode": "first", "layout": "inplace", "to": canon["version"], "kits": kits, "files": files,
            "decisions": decisions, "baseMode": base_mode, "blockers": blockers, "warnings": warnings,
            "plan": plan, "manifests": [manifest], "manifestDir": mdir, "newModules": new_modules,
            "manifestEdits": {"packages": add_packages, "targets": add_targets, "deps": add_deps},
            "modulePaths": {**{k["kit"]: k["path"] for k in kits},
                            **{n: canon["targets"][n]["path"] for n in new_modules}},
            "reviewAfterConflicts": review_after_conflicts(
                sides, {canon["targets"][n]["path"]: files[canon["targets"][n]["path"]] for n in new_modules})}


def build_update_inplace(canon, state_path, rel_fs, label_ours):
    """Mise à jour sur place : base = ancienne release (tag), nôtre = nouvelle, leur = leurs dossiers."""
    state = json.load(open(state_path))
    mdir = os.path.dirname(os.path.dirname(state_path))
    old = state["version"]
    if old == canon["version"]:
        raise ToolError(f"{mdir} is already on waangu-chat {old}")
    if canon["mode"] != "release" or not git(canon["root"], "rev-parse", "--verify", "-q", f"{old}^{{commit}}",
                                             check=False).strip():
        raise ToolError(f"base version {old} not found: run the tool from a FULL clone of waangu-chat "
                        f"(git clone without --depth), which has the tag {old}")
    base_all = FileSet.from_git(canon["root"], f"{old}^{{tree}}")
    old_manifest = parse_manifest(base_all.read("Package.swift").decode())["targets"]
    our_src = rel_fs.read("Package.swift").decode()
    our_target_texts = manifest_call_texts(our_src, ["target"])
    our_packages = manifest_package_texts(our_src)
    manifest = os.path.join(mdir, "Package.swift")
    their_src = open(manifest, encoding="utf-8").read()
    their_packages = {p["identity"] for p in parse_manifest(their_src)["packages"] if "url" in p}

    files, decisions, sides, blockers, warnings = {}, [], [], [], []
    paths = dict(state["modulePaths"])
    for name, rel_loc in sorted(paths.items()):
        theirs = FileSet.from_dir(os.path.join(mdir, rel_loc))
        bad = [r for r in theirs.blobs if not is_binary(theirs.read(r) or b"")
               and re.search(rb"^<<<<<<< ", theirs.read(r) or b"", re.M)]
        if bad:
            blockers.append(f"unresolved conflict markers from the previous merge in {rel_loc}/{bad[0]}: "
                            f"resolve and commit them first")
            continue
        if name not in canon["targets"]:
            decisions.append({"file": rel_loc, "person": True, "note": "",
                              "outcome": f"{name} was removed from waangu-chat {canon['version']}: decide whether to keep it"})
            continue
        new_path, old_path = canon["targets"][name]["path"], old_manifest.get(name, {}).get("path", rel_loc)
        merged, dec = merge_trees(rel_fs.sub(new_path), theirs, base_all.sub(old_path), set(),
                                  f"theirs (merged {old})", label_ours)
        for d in dec:
            d["file"] = f"{rel_loc}/{d['file']}"
        decisions += dec
        sides.append((rel_loc, rel_fs.sub(new_path), theirs, merged, dec))
        files[rel_loc] = merged

    new_modules = []
    for name, t in sorted(canon["targets"].items()):
        if name not in paths:
            files[t["path"]] = {r: rel_fs.read(f"{t['path']}/{r}") for r in rel_fs.sub(t["path"]).blobs}
            new_modules.append(name)
            paths[name] = t["path"]

    needed = set()
    for name in paths:
        for p in canon["targets"].get(name, {}).get("productDependencies", []):
            needed.add(p["package"].lower())
    add_packages = [our_packages[i] for i in sorted(needed) if i in our_packages and i not in their_packages]
    add_targets = [our_target_texts[n] for n in new_modules if n in our_target_texts]
    their_texts = manifest_call_texts(their_src, ["target"])
    add_deps = {}
    for name in paths:
        if name in new_modules or name not in our_target_texts:
            continue
        have = {dep_key(e) for e in dependency_exprs(their_texts.get(name, ""))}
        missing = [e for e in dependency_exprs(our_target_texts[name]) if dep_key(e) not in have]
        if missing:
            add_deps[name] = missing
    return {"mode": "update", "layout": "inplace", "from": old, "to": canon["version"],
            "kits": sorted(paths), "files": files, "decisions": decisions, "blockers": blockers,
            "warnings": warnings, "manifests": [manifest], "manifestDir": mdir, "newModules": new_modules,
            "manifestEdits": {"packages": add_packages, "targets": add_targets, "deps": add_deps},
            "modulePaths": paths, "reviewAfterConflicts": review_after_conflicts(sides)}


def apply_inplace(canon, merge, git_root, wt, version, target):
    """Écrit la fusion sur place dans le worktree. Renvoie les notes."""
    in_wt = lambda p: os.path.join(wt, os.path.relpath(p, git_root))
    mdir = in_wt(merge["manifestDir"])
    notes = []
    for rel_loc, tree in merge["files"].items():
        folder = os.path.join(mdir, rel_loc)
        if os.path.isdir(folder):
            # Retire les fichiers que la fusion remplace (pas ceux des dossiers ignorés : build, .build…).
            for dp, dn, fs in os.walk(folder):
                dn[:] = [d for d in dn if d not in SKIP_DIRS]
                for f in fs:
                    os.remove(os.path.join(dp, f))
        for rel, data in tree.items():
            if data is None:
                continue
            path = os.path.join(folder, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)
    for name in merge["newModules"]:
        notes.append(f"{name}: added in {merge['modulePaths'][name]}")
    for k in merge["kits"] if merge["mode"] == "first" else []:
        notes.append(f"{k['kit']}: merged in place in {k['path']}")

    path = os.path.join(mdir, "Package.swift")
    e = merge["manifestEdits"]
    feature_to = target if merge["mode"] == "first" else None
    deps = {k: list(v) for k, v in e["deps"].items()}
    if feature_to:
        deps.setdefault(feature_to, []).append(f'"{FEATURE}"')
    text, mnotes = edit_manifest_inplace(open(path, encoding="utf-8").read(), e["packages"], e["targets"],
                                         deps, feature_to, f"waangu-chat {version}")
    open(path, "w", encoding="utf-8").write(text)
    notes += [f"Package.swift: {n}" for n in mnotes]

    state = {"package": PACKAGE_IDENTITY, "layout": "inplace", "version": version,
             "sourceCommit": canon["sourceCommit"],
             "mergedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
             "modulePaths": merge["modulePaths"],
             "personNeeded": [d["file"] for d in merge["decisions"] if d["person"]]}
    if merge["mode"] == "update":
        state["updatedFrom"] = merge["from"]
    sp = os.path.join(mdir, INPLACE_STATE_REL)
    os.makedirs(os.path.dirname(sp), exist_ok=True)
    open(sp, "w").write(json.dumps(state, indent=2, sort_keys=True) + "\n")
    notes.append(f"state written: {os.path.relpath(sp, wt)}")
    return notes


def apply_merge(canon, dest, merge, worktree=None, target=None, url=DEFAULT_REMOTE_URL, verify=True):
    dest = os.path.abspath(dest)
    git_root = git(dest, "rev-parse", "--show-toplevel", check=False).strip()
    if not git_root:
        raise ToolError(f"{dest} is not a Git repository: apply works on a new branch")
    if merge["blockers"]:
        raise ToolError("cannot merge until a person handles:\n  - " + "\n  - ".join(merge["blockers"]))
    dirty = git(git_root, "status", "--porcelain", "--untracked-files=no").strip()
    if dirty:
        raise ToolError("uncommitted changes in the project; commit or stash them first:\n" + dirty)
    version = merge["to"]
    branch = f"waangu-chat/{version}"
    if git(git_root, "rev-parse", "--verify", "-q", f"refs/heads/{branch}", check=False).strip():
        raise ToolError(f"branch {branch} already exists")
    wt = os.path.abspath(worktree or os.path.join(os.path.dirname(git_root), f"{os.path.basename(git_root)}-waangu-chat-{version}"))
    if os.path.exists(wt):
        raise ToolError(f"{wt} already exists")
    git(git_root, "worktree", "add", "-q", "-b", branch, wt, "HEAD")
    try:
        return _apply_in_worktree(canon, merge, git_root, wt, branch, version, target, url, verify)
    except BaseException:
        # Rien ne doit rester d'un apply interrompu : le worktree et la branche créés ici partent.
        git(git_root, "worktree", "remove", "--force", wt, check=False)
        git(git_root, "branch", "-D", branch, check=False)
        raise


def _apply_in_worktree(canon, merge, git_root, wt, branch, version, target, url, verify):
    in_wt = lambda p: os.path.join(wt, os.path.relpath(p, git_root))
    if merge.get("layout") == "inplace":
        notes = apply_inplace(canon, merge, git_root, wt, version, target)
        verified = []
        if verify:
            for manifest in merge["manifests"]:
                ok, err = verify_manifest(in_wt(manifest))
                verified.append({"manifest": os.path.relpath(in_wt(manifest), wt), "ok": ok, "error": err})
        # Sur place, leurs produits gardent leurs noms : rien à relier dans Xcode.
        return {"worktree": wt, "branch": branch, "notes": notes, "verified": verified, "xcode": [],
                "conflicts": [d for d in merge["decisions"] if d["person"]]}
    notes = []

    def write_tree(root, files):
        for rel, data in files.items():
            if data is None:
                continue
            path = os.path.join(root, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)

    def remove_dir(path):
        if os.path.isdir(path):
            for dp, dn, fs in os.walk(path, topdown=False):
                for f in fs:
                    os.remove(os.path.join(dp, f))
                for d in dn:
                    os.rmdir(os.path.join(dp, d))
            os.rmdir(path)

    rel_fs = release_fileset(canon)
    state = {"package": PACKAGE_IDENTITY, "version": version, "sourceCommit": canon["sourceCommit"],
             "mergedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
             "kits": [k["kit"] for k in merge["kits"]] if merge["mode"] != "update" else merge["kits"],
             "personNeeded": [d["file"] for d in merge["decisions"] if d["person"]]}

    if merge["mode"] == "update":
        vend = in_wt(merge["vendoredDir"])
        for entry in os.listdir(vend):
            if entry != ".git":
                p = os.path.join(vend, entry)
                remove_dir(p) if os.path.isdir(p) else os.remove(p)
        write_tree(vend, merge["files"])
        write_tree(vend, merge["tools"])
        state["updatedFrom"] = merge["from"]
        open(os.path.join(vend, STATE_REL), "w").write(json.dumps(state, indent=2) + "\n")
        notes.append(f"Vendor/waangu-chat updated {merge['from']} → {version}")
    elif merge["mode"] == "first":
        for manifest in merge["manifests"]:
            mdir = os.path.dirname(in_wt(manifest))
            vend = os.path.join(mdir, VENDOR_REL)
            write_tree(vend, {r: rel_fs.read(r) for r in rel_fs.blobs})
            mine = [k for k in merge["kits"] if k["manifest"] == manifest]
            for k in mine:
                remove_dir(os.path.join(vend, k["path"]))
            write_tree(vend, {r: d for r, d in merge["files"].items()
                              if any(r.startswith(k["path"] + "/") for k in mine)})
            for k in mine:
                remove_dir(in_wt(k["theirCopy"]))
                notes.append(f"{k['kit']}: their copy removed, merged copy in {os.path.relpath(os.path.join(vend, k['path']), wt)}")
            open(os.path.join(vend, STATE_REL), "w").write(json.dumps(state, indent=2) + "\n")
            path = in_wt(manifest)
            text, mnotes = rewrite_manifest(open(path, encoding="utf-8").read(), {k["kit"] for k in mine},
                                            f'.package(path: "{VENDOR_REL}")',
                                            add_product_to=target if manifest == merge["manifests"][0] else None)
            open(path, "w", encoding="utf-8").write(text)
            notes += [f"{os.path.relpath(path, wt)}: {n}" for n in mnotes]
    else:  # aucun kit en double : simple dépendance distante
        manifests = sorted((m["file"] for m in merge["plan"]["inventory"]["manifests"]), key=len)
        if not manifests:
            notes.append(f"no Package.swift: add {url} in Xcode (File → Add Package Dependencies), product {FEATURE}")
        else:
            path = in_wt(manifests[0])
            text, mnotes = rewrite_manifest(open(path, encoding="utf-8").read(), set(),
                                            f'.package(url: "{url}", from: "{version}")', add_product_to=target)
            open(path, "w", encoding="utf-8").write(text)
            notes += [f"{os.path.relpath(path, wt)}: {n}" for n in mnotes]

    verified = []
    if verify and merge["mode"] != "update":
        edited = merge["manifests"]
        if merge["mode"] == "remote" and merge["plan"]["inventory"]["manifests"]:
            edited = [sorted((m["file"] for m in merge["plan"]["inventory"]["manifests"]), key=len)[0]]
        for manifest in edited:
            ok, err = verify_manifest(in_wt(manifest))
            verified.append({"manifest": os.path.relpath(in_wt(manifest), wt), "ok": ok, "error": err})

    xcode = []
    if merge["mode"] == "first":
        removed = {k["kit"] for k in merge["kits"]}
        for proj in merge["plan"]["inventory"]["xcodeProjects"]:
            for t in proj["targets"]:
                hits = [p["product"] for p in t["packageProducts"] if p["product"] in removed and p.get("local")]
                if hits:
                    xcode.append(f"{os.path.relpath(proj['file'], git_root)} › target `{t['name']}`: links "
                                 f"{', '.join(sorted(set(hits)))} from your local package. In Xcode, remove them from "
                                 f"Frameworks, Libraries…, then add the same products from package `waangu-chat`.")
    return {"worktree": wt, "branch": branch, "notes": notes, "verified": verified, "xcode": xcode,
            "conflicts": [d for d in merge["decisions"] if d["person"]]}


def render_merge_markdown(merge, applied=None):
    lines = [f"# waangu-chat {merge['to']}: merge report", ""]
    if merge["mode"] == "update":
        where = merge.get("vendoredDir") or merge.get("manifestDir")
        lines += [f"Update of `{where}` from {merge['from']} to {merge['to']} "
                  f"(3-way: base {merge['from']}, ours {merge['to']}, theirs = the merged copy).", ""]
    elif merge["mode"] == "first" and merge.get("layout") == "inplace":
        lines += [f"Merged in place, in your own `Sources/`: {', '.join(k['kit'] + ' (`' + k['path'] + '`)' for k in merge['kits'])}.",
                  f"Added next to them as new targets of your Package.swift: {', '.join(merge['newModules']) or 'none'}.",
                  f"Common base: {'Git history (3-way)' if merge['baseMode'] == 'lineage' else 'none, files compared 2-way; older versions of ours recognized by fingerprint'}.", ""]
    elif merge["mode"] == "first":
        lines += [f"Kits merged into one copy: {', '.join(k['kit'] for k in merge['kits'])}.",
                  f"Common base: {'Git history (3-way)' if merge['baseMode'] == 'lineage' else 'none, files compared 2-way; older versions of ours recognized by fingerprint'}.", ""]
    else:
        lines += ["No kit with the same name: waangu-chat is added as a normal remote dependency.", ""]
    for title, items in (("Blocked (a person must act first)", merge["blockers"]), ("Warnings", merge["warnings"])):
        if items:
            lines += [f"## {title}", ""] + [f"- {i}" for i in items] + [""]
    person = [d for d in merge["decisions"] if d["person"]]
    auto = [d for d in merge["decisions"] if not d["person"]]
    lines += ["## Needs a person", ""]
    lines += [f"- [ ] `{d['file']}`: {d['outcome']}" for d in person] or ["Nothing: no conflicts."]
    review = merge.get("reviewAfterConflicts") or []
    if review:
        lines += ["", "## Check after resolving the conflicts", "",
                  "These files were updated automatically but use a type from a conflicting file. If you keep "
                  "**their** side of that file, check that these still match its API.", ""]
        by_conflict = {}
        for r in review:
            for c in r["conflictFiles"]:
                by_conflict.setdefault(c, []).append(r["file"])
        for c, users in sorted(by_conflict.items()):
            lines.append(f"- [ ] When resolving `{c}`, check: " + ", ".join(f"`{u}`" for u in users))
    lines += ["", "## Done automatically", ""]
    counts = {}
    for d in auto:
        counts[d["outcome"]] = counts.get(d["outcome"], 0) + 1
    lines += [f"- {n} file(s): {o}" for o, n in sorted(counts.items(), key=lambda x: -x[1])] or ["-"]
    files_changed = [d for d in auto if d["outcome"] in ("changed on both sides: merged automatically",
                                                         "changed only by them: theirs kept", "added by them: kept")]
    if files_changed:
        lines += ["", "Their changes kept (review once):", ""] + [f"- `{d['file']}`: {d['outcome']}" for d in files_changed]
    if applied:
        lines += ["", "## Applied", "", f"- Worktree: `{applied['worktree']}`", f"- Branch: `{applied['branch']}` (nothing committed)"]
        lines += [f"- {n}" for n in applied["notes"]]
        for v in applied["verified"]:
            lines.append(f"- Manifest `{v['manifest']}` loads: {'yes' if v['ok'] else 'NO: ' + v['error']}")
        if applied["xcode"]:
            lines += ["", "## Xcode (manual)", ""] + [f"- [ ] {x}" for x in applied["xcode"]]
        lines += ["", "## Next", "",
                  f"1. Resolve the conflicts above in `{applied['worktree']}` (search for `<<<<<<<`).",
                  "2. `swift package resolve`, build and run the tests there.",
                  "3. Commit on the branch and open a pull request."]
    return "\n".join(lines) + "\n"


# ─── Entrée ──────────────────────────────────────────────────────────────────

def main(argv=None):
    parser = argparse.ArgumentParser(description="Read-only integration planner for waangu-chat.")
    sub = parser.add_subparsers(dest="command", required=True)
    p_inspect = sub.add_parser("inspect", help="inventory of a project (read-only)")
    p_inspect.add_argument("project")
    p_inspect.add_argument("--json", action="store_true", help="print the full inventory as JSON")
    p_plan = sub.add_parser("plan", help="plan for adding FeatureChat (read-only)")
    p_plan.add_argument("project")
    p_plan.add_argument("--out", help="folder for plan.json and report.md (default: a temporary folder, "
                                      "or build/module-tool/<planId> inside waangu-user-ios)")
    p_plan.add_argument("--history", help="path to a waangu-user-ios clone: enables 'copied from our commit X' "
                                          "detection when the tool runs from a published copy")
    for name, help_text in (("merge", "preview the merge of same-name kits (read-only)"),
                            ("apply", "merge into a new branch (git worktree) of the project; nothing committed")):
        sp = sub.add_parser(name, help=help_text)
        sp.add_argument("project")
        sp.add_argument("--out", help="folder for the report")
        sp.add_argument("--history", help="path to a waangu-user-ios clone (3-way merges with our history)")
        sp.add_argument("--layout", choices=["inplace", "vendor"], default="inplace",
                        help="inplace (default): merged kits stay in your Sources/, chat modules are added next to "
                             "them in your Package.swift. vendor: separate copy in Vendor/waangu-chat")
        if name == "apply":
            sp.add_argument("--target", help=f"target that gets the {FEATURE} product")
            sp.add_argument("--worktree", help="where to create the worktree (default: next to the project)")
            sp.add_argument("--url", default=DEFAULT_REMOTE_URL, help="package URL when no merge is needed")
            sp.add_argument("--no-verify", action="store_true", help="skip `swift package dump-package`")
    args = parser.parse_args(argv)

    here = os.path.dirname(os.path.abspath(__file__))
    release_root = os.path.dirname(here)
    is_release = os.path.basename(here) == "Tools" and os.path.isfile(os.path.join(here, "RELEASE.json"))
    try:
        if args.command == "inspect":
            info = inspect_project(args.project)
            if args.json:
                print(json.dumps(info, indent=2, sort_keys=True))
            else:
                print(f"Project   {info['path']}  ({info['branch'] or 'no git'} @ {(info['head'] or '-')[:8]})")
                print(f"Manifests {len(info['manifests'])} · Xcode projects {len(info['xcodeProjects'])} · "
                      f"pinned packages {len({p['identity'] for p in info['resolvedPins']})}")
                print("Local modules:")
                for name, copies in sorted(info["localModules"].items()):
                    print(f"  {name:<26} {copies[0]['kind']}  {copies[0].get('dir') or copies[0].get('project')}")
                print("Remote packages:")
                for r in sorted({(r['identity'], r['url']) for r in info["remotePackages"]}):
                    print(f"  {r[0]:<26} {r[1]}")
            return 0

        if is_release:
            canon = load_canonical_release(release_root, history=getattr(args, "history", None))
            default_out = os.path.join(tempfile.gettempdir(), "waangu-chat-module-tool")
        else:
            repo = git(here, "rev-parse", "--show-toplevel").strip()
            canon = load_canonical_dev(repo)
            default_out = os.path.join(repo, "build", "module-tool")
        if args.command in ("merge", "apply"):
            merge = build_merge(canon, args.project, layout=args.layout)
            applied = None
            if args.command == "apply" and not merge["blockers"]:
                applied = apply_merge(canon, args.project, merge, worktree=args.worktree, target=args.target,
                                      url=args.url, verify=not args.no_verify)
            report = render_merge_markdown(merge, applied)
            key = hashlib.sha256(report.encode()).hexdigest()[:16]
            out = args.out or os.path.join(default_out, f"merge-{key}")
            os.makedirs(out, exist_ok=True)
            open(os.path.join(out, "merge-report.md"), "w").write(report)
            summary = {
                "schema": 1, "command": args.command, "mode": merge["mode"], "version": merge["to"],
                "fromVersion": merge.get("from"), "project": os.path.abspath(args.project),
                "kits": [k["kit"] if isinstance(k, dict) else k for k in merge["kits"]],
                "blockers": merge["blockers"], "warnings": merge["warnings"],
                "decisions": merge["decisions"],
                "needsPerson": [d for d in merge["decisions"] if d["person"]],
                "reviewAfterConflicts": merge.get("reviewAfterConflicts") or [],
                "applied": applied,
            }
            with open(os.path.join(out, "merge.json"), "w") as f:
                json.dump(summary, f, indent=2, sort_keys=True)
            person = [d for d in merge["decisions"] if d["person"]]
            print(f"{args.command}: waangu-chat {merge['to']} → {os.path.abspath(args.project)}  ({merge['mode']})")
            for k in merge["kits"]:
                print(f"  kit {k['kit'] if isinstance(k, dict) else k}")
            for b_ in merge["blockers"]:
                print(f"  BLOCKED  {b_}")
            for w in merge["warnings"]:
                print(f"  WARNING  {w}")
            print(f"  automatic: {len(merge['decisions']) - len(person)} file(s)   needs a person: {len(person)}")
            for d in person[:30]:
                print(f"    [PERSON] {d['file']}: {d['outcome']}")
            review = merge.get("reviewAfterConflicts") or []
            if review:
                by_conflict = {}
                for r in review:
                    for c in r["conflictFiles"]:
                        by_conflict.setdefault(c, []).append(r["file"].rsplit("/", 1)[-1])
                print(f"  check after resolving conflicts ({len(review)} file(s) took our version and use a conflicting type):")
                for c, users in sorted(by_conflict.items()):
                    more = f" (+{len(users) - 6} more)" if len(users) > 6 else ""
                    print(f"    [CHECK]  {c.rsplit('/', 1)[-1]} → {', '.join(users[:6])}{more}")
            if applied:
                print(f"\n  worktree: {applied['worktree']}\n  branch:   {applied['branch']} (nothing committed)")
                for v in applied["verified"]:
                    print(f"  manifest {v['manifest']} loads: {'yes' if v['ok'] else 'NO'}")
            print(f"\nReport: {os.path.join(out, 'merge-report.md')}\nJSON:   {os.path.join(out, 'merge.json')}")
            if merge["blockers"]:
                return 2
            return 1 if person or merge["warnings"] else 0

        plan = build_plan(canon, args.project)
        out = args.out or os.path.join(default_out, plan["planId"])
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "plan.json"), "w") as f:
            json.dump(plan, f, indent=2, sort_keys=True)
        with open(os.path.join(out, "report.md"), "w") as f:
            f.write(render_markdown(plan))
        print_summary(plan)
        print(f"\nPlan:   {os.path.join(out, 'plan.json')}\nReport: {os.path.join(out, 'report.md')}")
        return exit_code(plan)
    except ToolError as e:
        print(f"error: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())

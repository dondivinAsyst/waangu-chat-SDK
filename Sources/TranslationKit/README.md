# TranslationKit — How to Use

This is the translation system for the Waangu app. It handles showing text in the right language throughout the app. This guide explains everything you need to know to use it, from the basic idea to real examples — no deep technical knowledge required.

---

## The basic idea

Imagine the app needs to show a message like **"Alice joined the group"**. But:
- In French it should say **"Alice a rejoint le groupe"**
- In Spanish it should say **"Alice se unió al grupo"**
- In German it should say **"Alice ist der Gruppe beigetreten"**

Instead of hardcoding that text anywhere, you give TranslationKit:
1. A **key** — a short name that identifies which text you want (like `"user_joined"`)
2. A **variable** to fill in — the actual name (like `"Alice"`)

And TranslationKit gives you back the correct sentence in the right language.

```
You ask:  key = "user_joined", fill-in = "Alice"
You get:  "Alice a rejoint le groupe"  ← in French
          "Alice joined the group"      ← in English
          etc.
```

That's it. The feature that shows the message doesn't need to know anything about languages or translation files. It just asks for the text by name.

---

## Where does the text come from?

TranslationKit looks for the translations in this order:

**First** — it uses whatever it already loaded (super fast, no waiting).

**Second** — if nothing is loaded yet, it checks if translations were saved on the device from a previous session (even works offline after first use).

**Third** — if nothing was ever saved, it falls back to the default translation files that ship with the app itself. These cover French, English, Spanish, and German out of the box.

So the app **always has translations available**, even on first launch with no internet connection.

---

## The translation text files

The default translations live in the `Resources/` folder inside this module:

```
Resources/
├── translations_fr.json   ← French
├── translations_en.json   ← English
├── translations_es.json   ← Spanish
└── translations_de.json   ← German
```

They look like this:

```json
{
  "locale": "fr",
  "version": 1,
  "modules": {
    "common": {
      "ok": "OK",
      "cancel": "Annuler"
    },
    "chat": {
      "user_joined": "%1$s a rejoint le groupe",
      "user_joined_you": "Vous avez rejoint le groupe"
    }
  }
}
```

What you need to know about this format:
- `locale` — which language this file is for
- `version` — a number that goes up every time translations are updated
- `modules` — groups of translations organized by feature (`chat`, `common`, `wallet`, etc.)
- `%1$s` — a placeholder that gets replaced by a real value (like a person's name). `%1$s` is the first value, `%2$s` is the second, and so on.
- `common` — a special group that any feature can use as a fallback (things like "OK", "Cancel", "Error")

If you update translations from the server, the server sends a file in the same format. TranslationKit saves it automatically and uses it going forward.

---

## How to use it in your feature — step by step

### Step 1 — Your feature already has access to the translator

When a feature screen or ViewModel is created, the translation service is passed to it automatically through the app's dependency system. You don't need to set anything up yourself. It's available as `translationService` in your feature's dependencies.

### Step 2 — Know your keys

Every feature has a list of keys. For the chat feature, the keys are in:

```
FeatureChat/Translation/ChatTranslationKeys.swift
```

Each key is just a name that identifies a piece of text. For example:

```
ChatTranslationKeys.USER_JOINED        →  "user_joined"
ChatTranslationKeys.GROUP_CREATED_YOU  →  "group_created_you"
ChatTranslationKeys.TYPING_TEXT        →  "typing_text"
```

You use the constant name (like `ChatTranslationKeys.USER_JOINED`), not the raw string value, so it's easy to find and refactor.

### Step 3 — Ask for the translated text

In your ViewModel or wherever you need the text:

```swift
// Simple — no fill-in values needed
let text = translationService.resolve(
    key: ChatTranslationKeys.GROUP_CREATED_YOU,
    module: ChatTranslationKeys.MODULE
).value
// → "Vous avez créé le groupe"

// With one fill-in (the person's name)
let text = translationService.resolve(
    key: ChatTranslationKeys.USER_JOINED,
    module: ChatTranslationKeys.MODULE,
    args: ["Alice"]   // replaces %1$s
).value
// → "Alice a rejoint le groupe"

// With two fill-ins
let text = translationService.resolve(
    key: ChatTranslationKeys.USER_ADDED_ACTOR,
    module: ChatTranslationKeys.MODULE,
    args: ["Alice", "Bob"]   // Alice replaces %1$s, Bob replaces %2$s
).value
// → "Alice a ajouté Bob"
```

`.value` at the end gives you the final text as a plain `String` ready to display.

---

## What if a translation is missing?

TranslationKit never crashes and never returns blank. If a key is not found:

1. It tries the `common` module (shared translations)
2. If still not found, it returns the key itself as plain text (e.g. `"user_joined"`)

So the worst case a user sees is a code-looking word instead of a translation — not a crash, not a blank screen.

---

## Receiving fresh translations from the server

When the app gets updated translations from the backend (for example after a content update), the data layer calls `updatePayload`. TranslationKit handles saving it to the device and updating all text automatically.

### If your server sends a standard format

If the server response directly matches the JSON structure shown above, just build the payload and hand it over:

```swift
// After getting a response from the server
let freshPayload = TranslationPayloadBuilder(locale: "fr", version: 5)
    .addModule("common", translations: serverResponse.common)
    .addModule("chat",   translations: serverResponse.chat)
    .build()

translationService.updatePayload(freshPayload)
// Done — every screen now shows the updated text
```

### If your server sends a different format

No problem. You provide a small conversion function that tells TranslationKit how to read your server's format:

```swift
translationService.updatePayload(from: rawDataFromServer) { serverJson in
    // serverJson is the raw dictionary from the server
    // Pick out the fields that match your API's structure
    guard
        let version     = serverJson["ver"]  as? Int,
        let locale      = serverJson["lang"] as? String,
        let chatStrings = serverJson["chat"] as? [String: String]
    else { return nil }  // if something is missing, skip the update

    return TranslationPayloadBuilder(locale: locale, version: version)
        .addModule("chat", translations: chatStrings)
        .build()
}
```

TranslationKit doesn't care what format the server uses. You just tell it how to map the data.

---

## Changing the language

When the user switches the app language in Settings:

```swift
// Set the new language in app settings first
appSettings.languageCode = .es  // switching to Spanish

// Tell TranslationKit to reload for the new language
translationService.reloadPayload(for: "es")
// All text in the app immediately switches to Spanish
```

---

## Adding translations for a new feature

Say you're building a new feature called Marketplace.

**Step 1 — Add your texts to the JSON files**

Open each file in `Resources/` and add a new section:

```json
"marketplace": {
    "item_sold": "%1$s a vendu %2$s",
    "order_placed": "Commande passée avec succès"
}
```

Do this for every language file (`translations_fr.json`, `translations_en.json`, etc.)

**Step 2 — Create your key list**

Create a file `MarketplaceTranslationKeys.swift` inside your feature:

```swift
struct MarketplaceTranslationKeys {
    static let MODULE       = "marketplace"   // must match the JSON section name
    static let ITEM_SOLD    = "item_sold"
    static let ORDER_PLACED = "order_placed"
}
```

**Step 3 — Use it**

```swift
// One fill-in
let text = translationService.resolve(
    key: MarketplaceTranslationKeys.ITEM_SOLD,
    module: MarketplaceTranslationKeys.MODULE,
    args: ["Alice", "Sac en cuir"]
).value
// → "Alice a vendu Sac en cuir"

// No fill-in
let text = translationService.resolve(
    key: MarketplaceTranslationKeys.ORDER_PLACED,
    module: MarketplaceTranslationKeys.MODULE
).value
// → "Commande passée avec succès"
```

That's everything. You don't need to change anything in TranslationKit itself.

---

## All chat translation keys

These are already set up and ready to use in the chat feature.

| What it shows | Key constant | Fill-ins needed |
|---|---|---|
| Someone joined the group | `USER_JOINED` | Person's name |
| You joined the group | `USER_JOINED_YOU` | None |
| Someone added someone | `USER_ADDED_ACTOR` | Actor name, target name |
| You added someone | `USER_ADDED_YOU_ACTOR` | Target name |
| Someone added you | `USER_ADDED_YOU_TARGET` | Actor name |
| Someone left the group | `USER_LEFT` | Person's name |
| You left the group | `USER_LEFT_YOU` | None |
| Someone removed someone | `USER_REMOVED_ACTOR` | Actor name, target name |
| Someone removed you | `USER_REMOVED_YOU_TARGET` | Actor name |
| Someone made someone admin | `ADD_ADMIN_ACTOR` | Actor name, target name |
| You made someone admin | `ADD_ADMIN_YOU_ACTOR` | Target name |
| Someone made you admin | `ADD_ADMIN_YOU_TARGET` | Actor name |
| Someone removed someone's admin | `REMOVE_ADMIN_ACTOR` | Actor name, target name |
| You removed someone's admin | `REMOVE_ADMIN_YOU_ACTOR` | Target name |
| Someone removed your admin | `REMOVE_ADMIN_YOU_TARGET` | Actor name |
| Someone created the group | `GROUP_CREATED_ACTOR` | Person's name |
| You created the group | `GROUP_CREATED_YOU` | None |
| Someone changed the group name | `GROUP_NAME_CHANGED_ACTOR` | Person's name |
| You changed the group name | `GROUP_NAME_CHANGED_YOU` | None |
| Someone changed the group photo | `GROUP_PIC_CHANGED_ACTOR` | Person's name |
| You changed the group photo | `GROUP_PIC_CHANGED_YOU` | None |
| Messages are encrypted | `ENCRYPTION_ENABLED` | None |
| Someone turned on disappearing messages | `DISAPPEARING_ON_ACTOR` | Person's name |
| You turned on disappearing messages | `DISAPPEARING_ON_YOU` | None |
| Someone turned off disappearing messages | `DISAPPEARING_OFF_ACTOR` | Person's name |
| You turned off disappearing messages | `DISAPPEARING_OFF_YOU` | None |
| Someone is typing | `TYPING_TEXT` | Person's name |
| Someone is recording audio | `RECORDING_AUDIO` | Person's name |

---

## Common questions

**Do I need internet for translations to work?**
No. The app ships with default translations built in. They always work offline. Updated translations from the server are a bonus, not a requirement.

**What if I use the wrong number of fill-ins?**
If you provide fewer fill-ins than the template needs, the placeholder (`%2$s`) will appear as-is in the text. If you provide too many, the extras are ignored. Neither causes a crash.

**Can I use the same translator in multiple features?**
Yes — and that's the point. The single translator instance is shared across all features. Chat, Wallet, Marketplace, Doctor — they all use the same one.

**Can the translations update without a new app release?**
Yes. When the server sends a fresh payload with a higher version number, TranslationKit saves it to the device. From that point forward, the app uses the updated text even after restart.

**What happens if a key doesn't exist in the translation file?**
TranslationKit first checks the `common` module. If still not found, it returns the key name itself as plain text. Never crashes, never blank.

# Tally

An iPhone note-taking app where the to-dos inside a note can be assigned to **more than
one person at a time**, and each of them ticks their own box.

The use case it was built around: a packing list for a two-day trip where both kids need
the same things. "2 pairs of socks" is one line assigned to both of them, showing `0/2`
until each has packed. Next trip, the same list becomes a new note with every box cleared.

## What it does

- **Notes made of blocks** — headings, prose, bullets, to-dos and dividers. Markdown
  shortcuts as you type: `# `, `## `, `- `, `[] `, `---`. Inline `**bold**`, `_italic_`
  and `` `code` `` are styled live, with the delimiters faded rather than hidden so text
  never jumps around under the caret.
- **Multi-assignee to-dos** — assign an item to any number of people. Each of them gets
  their own box; the item is only complete when everyone is done.
- **The two popups**
  - *Ticking* an item with two or more assignees opens **Who did it?**, so whoever packed
    the socks can tick their own box. One assignee (or none) ticks straight through with
    no popup, because the question has only one answer.
  - *Creating* a to-do opens **Assign to**, listing everyone you have used before, most
    recent first, with the typed name offered as a new person. How eagerly this appears is
    a setting — see [Assignee prompting](#assignee-prompting).
- **Sticky assignees** — after the first item in a note goes to Alma and Vidar, every
  following to-do picks them up automatically. That is what keeps a twenty-item packing
  list from turning into twenty questions.
- **Templates** — *New from this…* copies a note's structure, keeps (or swaps, or drops)
  the assignees, and clears every box. *Reset all checkboxes* reuses a note in place. Pin
  a note to Templates and it sits at the top of the list.
- **Markdown in and out** — share a note as markdown, paste markdown into a note, or
  import `.md` files.

## Building it

Requires **Xcode 16** or newer (the project uses synchronized file groups) and iOS 17+.

```sh
open Tally.xcodeproj      # then just Run
```

If your Xcode is older, or the project file ever misbehaves, regenerate it:

```sh
brew install xcodegen && xcodegen generate
```

The bundle identifier is `se.zerogravity.Tally` — change it in the target's Signing &
Capabilities before running on a device.

### Tests

The logic that is worth testing — markdown, template cloning, completion arithmetic,
block ordering — lives in `Tally/Core` and depends on nothing but Foundation. It is
exposed as a Swift package so it runs anywhere, with no simulator involved:

```sh
swift test
```

Xcode compiles the very same files into the app target through the synchronized `Tally`
folder, so there is no duplication and no package reference inside the project file.

> **These tests have not been run.** They were written in a Linux container with no Swift
> toolchain and no Xcode, and the network policy there blocked installing one. Expect to
> fix a compile error or two on the first build. `swift test` is the fastest way to find
> them, since it exercises `Core` without needing a simulator.

## How it is put together

```
Tally/
  Core/         pure Foundation — drafts, markdown, cloning, ordering, completion
  Model/        SwiftData: Document, Block, Person, Assignment (+ draft mapping)
  Features/     DocumentList, Editor, Assignees, Templates, Settings
  Support/      colours, inline markdown, live highlighting, haptics
Tests/CoreTests/
```

Everything with real logic in it works on the value types in `Core`; the SwiftData objects
are storage. `Model/DraftMapping.swift` is the only file that knows about both.

### Why per-assignee completion is its own record

`Assignment` is a join between a `Block` and a `Person` carrying a `completedAt` date,
rather than a list of people on the block. That is what lets "2 pairs of socks" be half
done, and it makes "everything Vidar still owes me" a cheap query if an inbox screen ever
gets built.

The store is local only — no accounts, no network. It does follow the rules SwiftData's
CloudKit support imposes (every attribute defaulted or optional, no unique constraints,
every relationship with an inverse), so syncing could be added later without a migration.

### Block ordering

Blocks carry a fractional `position: Double`. Splitting a line in the middle of a long
note writes one number instead of renumbering everything below it; when repeated splitting
finally exhausts the gap, `FractionalIndex.needsRenormalisation` catches it and the
document is evenly renumbered.

### The one bit of UIKit

`BlockTextView` wraps `UITextView`. SwiftUI's `TextField` cannot say where the caret is or
that backspace was pressed on an empty selection, and a Notes-style editor needs both:
return splits a line at the caret, backspace at position 0 folds a line into the one
above. It is the most likely place to need adjustment on a real device.

## Markdown format

Ordinary GitHub-flavored markdown with one extension: people are named at the end of a
to-do line, and a trailing `✓` marks the ones who are already done.

```markdown
# Trip to Åre

## Kids

- [ ] 2 pairs of socks @Alma✓ @Vidar
- [x] Toothbrush @Alma✓
- [ ] Sunscreen
```

Every assignee always carries their own mark, and the leading box summarises the item as a
whole — so it only reads `[x]` once everyone is done. That keeps the file honest in any
markdown viewer while still carrying the per-person detail. Names with spaces are
bracketed: `@[Alma Svensson]`. A mention only counts at the end of a line, so
`- [ ] Mail teacher@school.se` stays text.

If a hand-written file disagrees with itself — `- [x] Socks @Alma✓ @Vidar` — the
per-person marks win, because they are the more specific statement.

Round trips are content-preserving, with two documented exceptions: the first `# heading`
becomes the note's title, and blank paragraphs used purely as editor spacing are dropped.

## Assignee prompting

Settings → *New to-dos* chooses when **Assign to** appears:

| Mode | Behaviour |
| --- | --- |
| Every to-do | Ask each time a to-do is finished with nobody on it. |
| First in a note *(default)* | Ask once; the rest of the note reuses that answer. |
| Never | Assign from the chips under an item instead. |

The default exists because asking on every line is correct exactly once and irritating
nineteen times. Tapping the chips under any item reopens the picker whenever you want it.

## Not in this version

- Sharing a note with someone else's device, and their ticks syncing back. The data model
  is shaped for it; the transport is not there.
- Reminders, due dates, recurring notes.
- Nested numbered lists, tables, images.

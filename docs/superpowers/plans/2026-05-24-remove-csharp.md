# Remove C# / .NET from Project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip every C# / .NET artefact from this Godot 4.6 project so it runs as a pure GDScript project — no `.cs` sources, no `.csproj`/`.sln`, no `[dotnet]` config block, no `.godot/mono/` regeneration.

**Architecture:** This is a Godot mono (C#-enabled) project that only ever contained one C# script ([Scripts/PlayerPointClick.cs](Scripts/PlayerPointClick.cs)). The script has already been deleted from the working tree (visible in `git status` as `D`). What remains is project-level mono plumbing: `.csproj`, `.sln`, the `[dotnet]` section in `project.godot`, the lscache file, and the auto-generated `.godot/mono/` build output. Removing the plumbing tells Godot to stop treating this as a mono project, after which `.godot/mono/` will no longer be regenerated.

**Tech Stack:** Godot 4.6.2 (non-mono build is what we want), GDScript only, Box2D physics addon.

---

## File Inventory (decisions locked in here)

**Tracked files to delete from git:**
- [2DPlatformerSample.csproj](2DPlatformerSample.csproj) — C# project file
- [2DPlatformerSample.sln](2DPlatformerSample.sln) — Visual Studio solution
- [2DPlatformerSample.csproj.lscache](2DPlatformerSample.csproj.lscache) — C# Dev Kit cache (should never have been committed)
- [Scripts/PlayerPointClick.cs](Scripts/PlayerPointClick.cs) — already `D` in working tree, just needs to be staged
- `Scripts/PlayerPointClick.cs.uid` — already `D` in working tree, just needs to be staged

**Tracked files to modify:**
- [project.godot](project.godot#L30-L32) — drop the `[dotnet]` section (lines 30–32)
- [.gitignore](.gitignore) — append patterns so the lscache and any stray `.csproj.user`/`bin`/`obj` cannot creep back

**Untracked filesystem state to clean (gitignored under `.godot/`):**
- `.godot/mono/` — auto-generated mono build output; safe to delete because `.godot/` is gitignored. Will not regenerate once `[dotnet]` is removed from `project.godot` AND no `.csproj` exists.

**Files NOT touched by this plan:**
- All other `D` entries in `git status` (Prefab/, Scenes/Levels/, Scripts/AudioManager.gd, etc.) — those are unrelated to C# and represent a separate in-progress reorg. Stage only the C# deletions.
- `addons/godot-box2d/` — pure GDExtension, no C# involvement.
- `2DPlatformerSample.code-workspace` — VSCode workspace, no C# settings inside.

---

## Pre-flight Check

- [ ] **Step 1: Confirm Godot 4.6 non-mono binary is available**

Run:
```bash
ls "d:/GoDot" | grep -i "godot"
```
Expected: a non-mono `Godot_v4.6.x-stable_win64.exe`. The current `.code-workspace` points to `d:\GoDot\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe` — verify the file is the standard (non-mono) build. If only the mono build is present, download the standard build before continuing. The project will still open in a mono Godot binary, but the `[dotnet]` removal is the point — using a non-mono binary makes regression obvious.

- [ ] **Step 2: Confirm baseline — game runs before changes**

Run the project from Godot once (or via headless smoke if you prefer):
```bash
"d:/GoDot/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe" --path "d:/GoDot/Projects/2DPlatformerSample" --quit-after 60
```
Expected: project opens, imports run, exits without errors. If errors exist already, capture them so we can distinguish pre-existing from new.

- [ ] **Step 3: Verify the C# script is already gone from the working tree**

Run:
```bash
ls "d:/GoDot/Projects/2DPlatformerSample/Scripts/PlayerPointClick.cs" 2>&1
```
Expected: "No such file or directory" (the file is `D` in `git status`).

If the file unexpectedly exists, stop and reconcile with the user — something has been re-added since the plan was written.

---

## Task 1: Stage the already-deleted C# script

**Files:**
- Modify (stage deletion): `Scripts/PlayerPointClick.cs`
- Modify (stage deletion): `Scripts/PlayerPointClick.cs.uid`

- [ ] **Step 1: Stage only the two C# deletions (not the other `D` entries)**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git add Scripts/PlayerPointClick.cs Scripts/PlayerPointClick.cs.uid
```

- [ ] **Step 2: Verify staging is exactly those two files**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git diff --cached --name-status
```
Expected output (exactly two lines):
```
D	Scripts/PlayerPointClick.cs
D	Scripts/PlayerPointClick.cs.uid
```

If other files appear in the staged set, run `git restore --staged <file>` to unstage them. The reorg deletions belong to a different change.

- [ ] **Step 3: Commit**

```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git commit -m "chore: remove PlayerPointClick C# script"
```

---

## Task 2: Remove project-level C# build files

**Files:**
- Delete: `2DPlatformerSample.csproj`
- Delete: `2DPlatformerSample.csproj.lscache`
- Delete: `2DPlatformerSample.sln`

- [ ] **Step 1: Delete the three files via git so the index and working tree stay in sync**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git rm 2DPlatformerSample.csproj 2DPlatformerSample.csproj.lscache 2DPlatformerSample.sln
```

- [ ] **Step 2: Verify all three are staged for deletion**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git diff --cached --name-status
```
Expected (exactly three lines):
```
D	2DPlatformerSample.csproj
D	2DPlatformerSample.csproj.lscache
D	2DPlatformerSample.sln
```

- [ ] **Step 3: Verify the files are gone from disk**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
ls 2DPlatformerSample.csproj 2DPlatformerSample.csproj.lscache 2DPlatformerSample.sln 2>&1
```
Expected: three "No such file or directory" lines.

- [ ] **Step 4: Commit**

```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git commit -m "chore: remove .csproj/.sln/.lscache (.NET project files)"
```

---

## Task 3: Remove the `[dotnet]` section from `project.godot`

**Files:**
- Modify: [project.godot](project.godot#L30-L32)

- [ ] **Step 1: Read the section to confirm exact content**

Read [project.godot](project.godot) lines 28–35. The current content is:

```
[dotnet]

project/assembly_name="2DPlatformerSample"

[editor_plugins]
```

- [ ] **Step 2: Remove the section using Edit**

Use the Edit tool on [project.godot](project.godot):

`old_string`:
```
[dotnet]

project/assembly_name="2DPlatformerSample"

[editor_plugins]
```

`new_string`:
```
[editor_plugins]
```

Note: this removes the `[dotnet]` header, the `project/assembly_name` line, AND the blank line that follows the section — leaving exactly one blank line separating the previous `[display]` section from `[editor_plugins]` (because the blank line *before* `[dotnet]` is preserved).

- [ ] **Step 3: Verify the section is gone and the file is still parseable**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
grep -n "dotnet\|assembly_name" project.godot
```
Expected: no output (zero matches).

Also verify the surrounding sections are intact:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
grep -n "^\[" project.godot
```
Expected: `[animation]`, `[application]`, `[display]`, `[editor_plugins]`, `[input]`, `[physics]`, `[rendering]` — no `[dotnet]`.

- [ ] **Step 4: Stage and commit**

```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git add project.godot
git commit -m "chore: remove [dotnet] section from project.godot"
```

---

## Task 4: Tighten `.gitignore` so .NET cruft cannot return

**Files:**
- Modify: [.gitignore](.gitignore)

- [ ] **Step 1: Read current `.gitignore`**

Read [.gitignore](.gitignore). Confirm it currently ignores `.godot/` and `.mono/` but not `.csproj.lscache`, `.csproj.user`, `bin/`, `obj/`. The `.lscache` file was tracked previously — that should not happen again even if someone re-adds C# Dev Kit later.

- [ ] **Step 2: Append C#/.NET ignore patterns**

Use the Edit tool on [.gitignore](.gitignore). Append the following block to the end of the file (preserve existing content):

`old_string`:
```
# Mono-specific ignores
.mono/
data_*/
mono_crash.*.json
```

`new_string`:
```
# Mono-specific ignores
.mono/
data_*/
mono_crash.*.json

# .NET / C# Dev Kit (project is GDScript-only — these should never appear)
*.csproj.lscache
*.csproj.user
*.sln.DotSettings.user
bin/
obj/
```

- [ ] **Step 3: Verify .gitignore changes**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
tail -10 .gitignore
```
Expected: the appended block is present and `.mono/` is still above it.

- [ ] **Step 4: Stage and commit**

```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git add .gitignore
git commit -m "chore: ignore .NET build artefacts (csproj.user, bin, obj)"
```

---

## Task 5: Delete the auto-generated `.godot/mono/` directory

**Files:**
- Delete (untracked, gitignored): `.godot/mono/`

This directory is build output from the previous mono-enabled state. It is gitignored (`.godot/` is in `.gitignore`), so no git operations are needed — just remove it from disk so Godot's next import does not see it.

- [ ] **Step 1: Confirm the directory exists and is gitignored**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
ls .godot/mono
git check-ignore -v .godot/mono
```
Expected: `metadata` and `temp` subdirectories listed; `git check-ignore` confirms `.gitignore:2:.godot/` matches.

- [ ] **Step 2: Delete the directory**

Run via the Bash tool (POSIX `rm -rf` works here):
```bash
rm -rf "d:/GoDot/Projects/2DPlatformerSample/.godot/mono"
```
PowerShell equivalent if you prefer: `Remove-Item -Recurse -Force "d:/GoDot/Projects/2DPlatformerSample/.godot/mono"`.

- [ ] **Step 3: Verify it's gone**

Run:
```bash
ls "d:/GoDot/Projects/2DPlatformerSample/.godot/mono" 2>&1
```
Expected: "No such file or directory".

- [ ] **Step 4: (no commit)**

`.godot/` is gitignored, so there is nothing to stage or commit. Skip.

---

## Task 6: Verification — open project in Godot and confirm no mono regeneration

**Files:** none modified.

- [ ] **Step 1: Open project in Godot once (headless, with auto-quit)**

Run:
```bash
"d:/GoDot/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe" --path "d:/GoDot/Projects/2DPlatformerSample" --quit-after 60
```
Expected: project opens, imports run, exits cleanly (exit code 0). No errors mentioning `dotnet`, `mono`, `assembly`, or `C#`. If the Godot binary is the mono variant, it may print a one-line note that no C# project was found — that is fine and is the goal.

- [ ] **Step 2: Confirm `.godot/mono/` did NOT regenerate**

Run:
```bash
ls "d:/GoDot/Projects/2DPlatformerSample/.godot/mono" 2>&1
```
Expected: "No such file or directory". If the directory came back, the `[dotnet]` section was not fully removed OR a stray `.csproj` exists — re-run Task 3 verification and `ls *.csproj *.sln` at the project root.

- [ ] **Step 3: Confirm no stray C# files in working tree or index**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git ls-files | grep -iE "\.cs$|\.csproj|\.sln|lscache" || echo "clean"
find . -name "*.cs" -not -path "./.godot/*" 2>/dev/null || echo "no .cs files"
```
Expected: both commands print `clean` / `no .cs files` (or produce no output for `find`).

- [ ] **Step 4: Run the demo scene to confirm the game still works**

Launch the demo menu interactively:
```bash
"d:/GoDot/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe" --path "d:/GoDot/Projects/2DPlatformerSample"
```
Manually: click into one demo scene, confirm it loads and player moves. Close the window when done. If anything errors with a `null script` or missing-class message, capture the error — it may indicate a `.tscn` still references the removed C# class (none were found during planning, but verify).

- [ ] **Step 5: Final `git status` should be clean of this change set**

Run:
```bash
cd "d:/GoDot/Projects/2DPlatformerSample"
git status
```
Expected: no entries related to `.csproj`, `.sln`, `.cs`, `lscache`, `mono`, or `[dotnet]`. Other unrelated `D` entries from the pre-existing reorg may still be present — that is expected and not part of this plan.

---

## Done When

- `git ls-files` contains zero `.cs`, `.csproj`, `.sln`, or `.lscache` paths.
- `project.godot` has no `[dotnet]` section.
- `.godot/mono/` does not exist on disk and does not regenerate after a Godot import.
- The demo menu still opens and at least one demo scene plays.
- Four commits land on `master`: PlayerPointClick deletion, project files deletion, project.godot edit, .gitignore tightening.

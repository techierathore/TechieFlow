# How to save a Claude Code conversation to a file

| | |
|---|---|
| For | The owner. Nothing here is an agent instruction. |
| Written | 2026-09-09 |
| Applies to | Any folder you talk to Claude Code in — this is not a TechieFlow feature |

---

## Why you cannot just select the text

The terminal window is not a document. It is a screen that gets **repainted** while text arrives: lines are redrawn, re-wrapped to the width of your window, and pushed up as new output comes in. When you select part of it, you copy whatever happens to be painted at that instant.

That is why pasted text comes out with sentences cut off mid-word and fragments fused into words nobody wrote — `figuto`, `fouTfLens`, `bugm`. Nothing is wrong with your terminal or your mouse. There is simply no complete copy of the text on the screen to take.

**Claude Code also writes every conversation to a plain text file on your disk, as it happens.** That copy is exact and complete. The command below reads that file and turns it into readable markdown.

---

## The short version

Open your terminal, go to the project folder, and run one line:

```
cd /mnt/c/3AIGenCode/TechieFlow
bash ~/claude-export.sh
```

It prints where it saved the file:

```
Saved: docs/chat-history/claude-2026-09-09-f0b7ae48.md
  12 question(s), 84 answer(s), 48399 characters
```

Open that file in VS Code, Notepad or anything else. Copy from **there**, not from the terminal.

---

## Step by step

### Step 1 — open a terminal in the right folder

The command has to run **from the project folder you were talking to Claude about**. Claude Code files each conversation under the folder it happened in, so running it somewhere else finds nothing.

Three ways to get there:

- **In Claude Code itself.** Type an exclamation mark, a space, then the command. `! bash ~/claude-export.sh` — the `!` runs it in your current session, in the right folder already, and the output appears in the conversation.
- **In a Windows terminal.** Open Windows Terminal or PowerShell, type `wsl`, then `cd /mnt/c/3AIGenCode/TechieFlow`.
- **From VS Code.** Open the project, then Terminal → New Terminal. Make sure it says WSL and not PowerShell.

### Step 2 — run the command

```
bash ~/claude-export.sh
```

That is the whole command. No arguments needed.

### Step 3 — read what it printed

It tells you the file it wrote:

```
Saved: docs/chat-history/claude-2026-09-09-f0b7ae48.md
```

The name is the date plus the first part of the conversation's id, so several exports never overwrite each other.

### Step 4 — open the file

From Windows, the path above lives at:

```
C:\3AIGenCode\TechieFlow\docs\chat-history\claude-2026-09-09-f0b7ae48.md
```

Open it in VS Code (best — it renders the markdown) or Notepad. Everything in it is complete: every question you asked and every answer, in order, with the code blocks and tables intact.

---

## The other things it can do

### See which conversations exist for this folder

```
bash ~/claude-export.sh --list
```

```
Conversations for /mnt/c/3AIGenCode/TechieFlow — newest first:

  f0b7ae48-2d0b-45d1-907d-775854f0b516
     2343 KB · last touched 2026-09-09 16:13
     you last said: "Two more things : 1. About the session chat history command..."

  9998a62b-bcb5-4107-82df-733f8627a949
     3234 KB · last touched 2026-09-08 19:53
     you last said: "ok does the framework need to be updated in repositories using it ?..."
```

Newest is at the top. With no arguments, the export always takes the newest one.

**It shows the last thing you said in each conversation**, which is how you tell two of them apart without opening either.

---

## Two Claude Code windows open at once

This is the common case and it has two shapes. Which one you are in decides what you do.

### Shape 1 — the two windows are in different folders

**Nothing to think about.** Claude Code keeps a separate history folder for every project path, so the two conversations are never in the same place. The folder you run the command from picks the window:

```
cd /mnt/c/3AIGenCode/TechieFlow
bash ~/claude-export.sh          # the TechieFlow window

cd /mnt/c/1MyCode/TfLens
bash ~/claude-export.sh          # the TfLens window
```

Run it twice, once per folder, and you have both. They cannot be confused with each other.

### Shape 2 — both windows are in the same folder

Now both conversations live in the same history folder, and `--list` shows both. Two ways to pick:

**By what you last said.** Run `--list` and read the `you last said:` line under each id. That is the surest way — it is your own words, and it will be obviously one window or the other.

**By time.** The top entry is whichever window you spoke in most recently. If you have just typed in the window you want, it is the top one and plain `bash ~/claude-export.sh` gets it.

Then export the one you want by its id:

```
bash ~/claude-export.sh --session 9998a62b-bcb5-4107-82df-733f8627a949
```

### The way that never needs any of this

Type the command **inside the window you want**, with an exclamation mark in front:

```
! bash ~/claude-export.sh
```

Claude Code runs it in that session, in that folder, and the answer appears in that conversation. There is no picking, because you asked the window itself. This is the method to prefer whenever you have more than one window open.

One detail: the file is written the moment you run it, so it contains the conversation **up to that point**. Run it again at the end to capture the rest — a later export with the same date and id simply overwrites the earlier one, so you always end with the complete conversation.

---

## Two more options

### Save it somewhere else

Give it a path instead:

```
bash ~/claude-export.sh /mnt/c/3AIGenCode/notes/monday-session.md
```

### Do it in any other project

Same command, different folder. It works anywhere, not only in TechieFlow:

```
cd /mnt/c/1MyCode/TfLens
bash ~/claude-export.sh
```

---

## Where things are

| What | Where |
|---|---|
| The command | `/home/srkra/claude-export.sh` — in WSL, in your home folder |
| Claude's own records | `/home/srkra/.claude/projects/<folder-name>/*.jsonl` — one file per conversation |
| Where exports land | `docs/chat-history/` inside the project, unless you name a different path |

The exporter is **not** part of TechieFlow. It is not in `.tfcore/`, it is not copied into projects by `update-framework.sh`, and no framework rule depends on it. It is a personal utility that happens to live in your home folder, which is why the command starts with `~/` rather than `.tfcore/`.

---

## If something goes wrong

**"no Claude Code history for this folder"** — you are in the wrong folder. The message prints the path it looked in. `cd` to the project you were talking about and run it again.

**"python3 is required"** — python3 is missing from this machine. TechieFlow needs it too, so this would be breaking other things as well.

**The file is there but looks empty** — you exported a conversation that has no text in it yet, or the wrong one. Run `--list` and pick a different id.

**It saved to your home folder instead of `docs/`** — the folder you ran it from has no `docs/` directory, so it fell back to `~/claude-session.md`. Run it from the project root, not from a sub-folder.

---

## A note on what is in these files

An exported conversation is a full record of what was said, including anything you pasted in. Treat the file the way you would treat the conversation: it goes in `docs/chat-history/`, which is inside the project, so think before committing one to a public repository.

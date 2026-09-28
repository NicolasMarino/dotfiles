#!/usr/bin/env python3
"""Append a dated journal entry after a session that produced commits, or,
on demand with --allow-no-commits, after any session with enough prose.

Wired to Claude Code's SessionEnd hook. Reads the hook payload on stdin,
decides whether the session is worth recording, extracts the narrative from
the transcript, asks a cheap model to write the entry, and appends it to
today's file in the Obsidian vault.

Three measurements shaped this, all taken on a real 21 MB transcript:

  * The raw transcript is ~5.1M tokens. It can never be sent to a model.
  * Tool results are 6.3 MB of that; 94% of those are base64 images.
  * The assistant's own prose is ~61k tokens and carries the narrative.

So this extracts prose and drops everything else. It also never decides
"significance" by asking a model — it asks git, which is free and matches
what the operator already meant when they committed.

Exit code is always 0. A journal hook must never interrupt a session.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import date, datetime, time, timezone
from pathlib import Path

VAULT = Path(os.environ.get(
    "JOURNAL_VAULT",
    "~/Documents/git/knowledge/knowledge/05_Journal",
)).expanduser()
REPO_ROOT = Path(os.environ.get("JOURNAL_REPO_ROOT", "~/Documents/git")).expanduser()
MODEL = os.environ.get("JOURNAL_MODEL", "haiku")

# Re-entrancy guard. `claude -p` below would otherwise fire this same hook,
# which would call `claude -p` again. --settings disableAllHooks is also
# passed, but an unknown settings key fails silently, so this env sentinel
# is the guard that is actually verifiable.
SENTINEL = "JOURNAL_HOOK_RUNNING"

# Prose under this many characters is a session that did nothing worth
# writing down, even if it happened to touch a commit.
MIN_PROSE_CHARS = 2000

PROMPT = """\
Escribí la entrada de bitácora de hoy para un desarrollador, en español \
rioplatense, en primera persona, con bullets y subtítulos markdown.

Te paso abajo la narración de una sesión de trabajo y, si los hubo, los \
commits que produjo. Escribí SOLO la entrada, sin preámbulo.

Incluí, si están:
- Qué se logró, concreto
- Qué se descubrió que no se sabía, con los números si los hay
- **Dónde se equivocó**, explícitamente. Esta sección es obligatoria si hay \
material: las correcciones valen más que los aciertos.
- Qué queda pendiente

No inventes nada que no esté en el material. Si algo no está, omitilo.
Sé concreto: preferí "70 de 2809 palabras llevan puntuación" antes que \
"Whisper puntúa poco".
"""


def log(msg: str) -> None:
    """Diagnostics go to a file, not stdout — a SessionEnd hook's stdout is
    not a place the operator will look."""
    try:
        p = Path.home() / ".claude" / "hooks" / "journal.log"
        with p.open("a") as fh:
            fh.write(f"{datetime.now(timezone.utc).isoformat()} {msg}\n")
    except OSError:
        pass


def session_start(transcript: Path) -> datetime | None:
    """The timestamp of the transcript's first record, used as the git
    window. Returns None if no record carries one."""
    try:
        with transcript.open() as fh:
            for line in fh:
                try:
                    ts = json.loads(line).get("timestamp")
                except json.JSONDecodeError:
                    continue
                if ts:
                    return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except OSError:
        return None
    return None


def discover_repos() -> dict[str, Path]:
    """Git repos under REPO_ROOT, keyed by their path relative to it.

    Two levels deep, because repos are grouped by owner (`personal/dotfiles`,
    `work/x`): scanning only the first level found no repo at all for those,
    so their sessions were never journaled. A directory that is itself a repo
    is not descended into. The relative path is the key rather than the bare
    name so `personal/x` and `work/x` cannot collide.
    """
    repos: dict[str, Path] = {}
    if not REPO_ROOT.is_dir():
        return repos
    for top in sorted(REPO_ROOT.iterdir()):
        if not top.is_dir():
            continue
        if (top / ".git").exists():
            repos[top.name] = top
            continue
        try:
            children = sorted(top.iterdir())
        except OSError:
            continue
        for child in children:
            if child.is_dir() and (child / ".git").exists():
                repos[f"{top.name}/{child.name}"] = child
    return repos


def repos_touched(transcript: Path, cwd: str | None = None) -> set[str]:
    """Repos where THIS session actually ran `git commit`.

    Two weaker signals were tried first and both were wrong, which is why
    this one is narrow on purpose:

      * "commits since the session started" swept 72 commits, because a
        session can run for days.
      * "repo name appears in the transcript" still swept another project,
        because its name appeared in a settings file the session merely
        read. Being mentioned is not being worked in.

    A `git commit` the session itself executed is a causal link, not a
    coincidence.
    """
    repos = discover_repos()
    if not repos:
        return set()
    # The repo the session stands in, if any: worktrees live inside the repo
    # (`.claude/worktrees/x`), so containment covers them too.
    home_repo = None
    if cwd:
        here = Path(cwd).expanduser()
        for key, path in repos.items():
            if here == path or path in here.parents:
                home_repo = key
                break
    touched: set[str] = set()
    try:
        fh = transcript.open(errors="ignore")
    except OSError:
        return set()
    with fh:
        for line in fh:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = record.get("message") or {}
            if message.get("role") != "assistant":
                continue
            content = message.get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                if block.get("name") != "Bash":
                    continue
                command = str((block.get("input") or {}).get("command", ""))
                if "git commit" not in command:
                    continue
                hit = {k for k in repos if f"/{k}" in command}
                # A commit run in the session's own working directory carries
                # no path at all — `git add x && git commit` names no repo.
                # Missing those loses exactly the commits made where the
                # session was already standing.
                if not hit and home_repo:
                    hit = {home_repo}
                touched |= hit
    return touched


def commits_since(since: datetime, allowed: set[str]) -> list[str]:
    """Commits in the repos this session actually touched, since `since`.

    `since` is the LATER of the session's start and midnight today, because
    the entry is written to a dated file: a six-day session must not file a
    week of history under today's date.
    """
    found: list[str] = []
    for key, repo in sorted(discover_repos().items()):
        if key not in allowed:
            continue
        try:
            out = subprocess.run(
                ["git", "-C", str(repo), "log",
                 f"--since={since.isoformat()}",
                 "--format=%h %s", "--no-merges"],
                capture_output=True, text=True, timeout=15,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if out.returncode != 0:
            continue
        for line in out.stdout.splitlines():
            if line.strip():
                found.append(f"[{repo.name}] {line}")
    return found


def extract_prose(transcript: Path) -> str:
    """Assistant text plus real user turns. Tool results, images, thinking
    blocks and system reminders are dropped — they are 99% of the bytes and
    none of the narrative."""
    parts: list[str] = []
    skip_prefixes = ("<system-reminder", "<local-command", "Caveat:",
                     "<task-notification")
    try:
        fh = transcript.open()
    except OSError:
        return ""
    with fh:
        for line in fh:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = record.get("message") or {}
            role = message.get("role")
            content = message.get("content")
            if role not in ("assistant", "user"):
                continue
            if isinstance(content, str):
                text, kind = content, role
            elif isinstance(content, list):
                chunks = [b.get("text", "") for b in content
                          if isinstance(b, dict) and b.get("type") == "text"]
                text, kind = "\n".join(chunks), role
            else:
                continue
            text = text.strip()
            if not text or text.lstrip().startswith(skip_prefixes):
                continue
            parts.append(f"{'YO' if kind == 'user' else 'ASISTENTE'}: {text}")
    return "\n\n".join(parts)


def ask_model(material: str) -> str:
    env = dict(os.environ)
    env[SENTINEL] = "1"
    # The instruction goes AFTER the material, not before. With the
    # instruction first, a 75k-token body made the model continue the
    # material's own "ASISTENTE:" format and fabricate content instead of
    # summarising. Measured, not assumed.
    try:
        out = subprocess.run(
            ["claude", "-p", "--model", MODEL,
             "--settings", '{"disableAllHooks": true}'],
            input=f"<material>\n{material}\n</material>\n\n{PROMPT}",
            capture_output=True, text=True, timeout=300, env=env,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        log(f"model call failed: {exc}")
        return ""
    if out.returncode != 0:
        log(f"model exited {out.returncode}: {out.stderr[:200]}")
        return ""
    return out.stdout.strip()


def append_entry(entry: str, commits: list[str], session_id: str,
                 day: date, force: bool = False) -> None:
    """Append, never overwrite. A second session on the same day must not
    destroy the first one's entry.

    `day` is the day the WORK belongs to, not the day the process runs. For
    the hook those are the same by construction — its window never reaches
    back past midnight — so passing it changes nothing there. It is what
    lets the on-demand path file a session that crossed midnight under the
    day it was actually worked.
    """
    VAULT.mkdir(parents=True, exist_ok=True)
    target = VAULT / f"{day.isoformat()}.md"
    marker = f"<!-- session {session_id} -->"

    existing = target.read_text() if target.exists() else ""
    if marker in existing and not force:
        log(f"session {session_id} already recorded, skipping")
        return

    block = [marker, entry]
    if commits:
        block += ["", "### Commits", ""]
        block += [f"- `{c}`" for c in commits]
    body = "\n".join(block) + "\n"

    with target.open("a") as fh:
        if existing and not existing.endswith("\n\n"):
            fh.write("\n")
        if existing:
            fh.write("---\n\n")
        fh.write(body)
    log(f"wrote {len(entry)} chars to {target}")


def arg(name: str) -> str | None:
    """`--name value` out of argv. No argparse: the rest of this file reads
    argv by membership, and one convention is easier to follow than two."""
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None


def main() -> int:
    if os.environ.get(SENTINEL):
        return 0  # we are inside our own model call

    dry = "--dry-run" in sys.argv
    force = "--force" in sys.argv
    allow_no_commits = "--allow-no-commits" in sys.argv

    # On demand: the operator asks for the entry mid-session instead of
    # waiting for SessionEnd, so there is no hook payload on stdin. Reading
    # stdin anyway would block on a terminal.
    transcript_arg = arg("--transcript")
    if transcript_arg:
        payload = {
            "transcript_path": transcript_arg,
            "cwd": arg("--cwd") or os.getcwd(),
            "session_id": arg("--session-id") or "manual",
        }
    else:
        try:
            payload = json.load(sys.stdin)
        except (json.JSONDecodeError, ValueError):
            log("no usable payload on stdin")
            return 0
        # The hook path never gets this: every session would otherwise get an
        # entry, commits or not, and the vault would fill with noise.
        allow_no_commits = False

    # Detach before doing anything slow. The model call measured 27 s, and a
    # SessionEnd hook that blocks for that long makes the session hang on
    # exit. Claude Code's settings reportedly have an `async` flag, but an
    # unrecognised settings key fails silently, so this forks rather than
    # trusting one. The parent returns immediately; the child is reparented
    # to init and finishes on its own.
    if not dry and not transcript_arg and "--foreground" not in sys.argv:
        try:
            if os.fork() > 0:
                return 0
            os.setsid()
            devnull = os.open(os.devnull, os.O_RDWR)
            for fd in (0, 1, 2):
                os.dup2(devnull, fd)
        except OSError as exc:
            log(f"fork failed, running inline: {exc}")

    raw_path = payload.get("transcript_path")
    if not raw_path:
        return 0
    transcript = Path(raw_path)
    if not transcript.is_file():
        log(f"transcript missing: {transcript}")
        return 0

    started = session_start(transcript)
    if started is None:
        log("no timestamp in transcript")
        return 0

    # The entry lands in a file named for today, so the window must not
    # reach back past midnight even when the session does.
    # JOURNAL_SINCE exists so this branch can be exercised on a day other
    # than the one being tested; it is never set in normal operation.
    # `--date` anchors the window on a day other than today, which is the
    # whole reason the on-demand path exists: a session that crosses
    # midnight would otherwise file yesterday's work under today, with the
    # window clamped to today's midnight so yesterday's commits fall out of
    # it entirely and the entry is never written at all.
    day_arg = arg("--date")
    anchor = date.fromisoformat(day_arg) if day_arg else datetime.now().date()

    override = os.environ.get("JOURNAL_SINCE")
    if override:
        window = datetime.fromisoformat(override)
    else:
        midnight = datetime.combine(anchor, time()).astimezone()
        window = midnight if day_arg else max(started, midnight)

    allowed = repos_touched(transcript, payload.get("cwd"))
    commits = commits_since(window, allowed)
    if not commits and not allow_no_commits:
        log(f"no commits since {window.isoformat()} in {sorted(allowed)}")
        if dry:
            # Otherwise a dry run that finds nothing prints nothing, which
            # reads as "worked" when it is exactly the case worth diagnosing.
            print(f"window from     : {window.isoformat()}")
            print(f"repos touched   : {sorted(allowed)}")
            print("commits found   : 0 (nothing would be written)")
        return 0

    prose = extract_prose(transcript)
    if len(prose) < MIN_PROSE_CHARS:
        log(f"only {len(prose)} chars of prose, skipping")
        return 0

    material = f"NARRACION DE LA SESION:\n{prose}"
    if commits:
        material = (
            f"COMMITS DE LA SESION:\n" + "\n".join(commits) +
            f"\n\n{material}"
        )

    if dry:
        print(f"session started : {started.isoformat()}")
        print(f"window from     : {window.isoformat()}")
        print(f"repos touched   : {sorted(allowed)}")
        print(f"commits found   : {len(commits)}" +
              (" (gate bypassed: --allow-no-commits)"
               if not commits and allow_no_commits else ""))
        for c in commits[:10]:
            print(f"  {c}")
        print(f"prose extracted : {len(prose):,} chars (~{len(prose)//4:,} tokens)")
        print(f"material total  : {len(material):,} chars (~{len(material)//4:,} tokens)")
        print(f"would write to  : {VAULT / (anchor.isoformat() + '.md')}")
        return 0

    entry = ask_model(material)
    if not entry:
        return 0
    append_entry(entry, commits, str(payload.get("session_id", "unknown")),
                 anchor, force)
    return 0


if __name__ == "__main__":
    sys.exit(main())

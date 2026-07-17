# jymiller/jymiller

Repo: **https://github.com/jymiller/jymiller** (`origin`)

This repo does double duty — the repo name matches the GitHub username, so:

- **`README.md`** → renders as the **GitHub profile** at <https://github.com/jymiller>
- **`index.html` + assets** → served as **GitHub Pages** at <https://jymiller.github.io/jymiller/>

Editing one does not update the other. They are separate surfaces.

## Where things live

Three copies of this project can be in play at once:

| Where | What it is |
|---|---|
| `~/Downloads/source/jymiller` | the normal clone, usually on `main` |
| `.../jymiller/.claude/worktrees/<name>` | a temporary Claude **git worktree** — a second checkout on its own branch, hidden inside the folder above. Disposable. |
| `github.com/jymiller/jymiller` @ `main` | **what GitHub Pages actually serves** |

**Pages serves the remote `main` — not the local disk.** So the live site can be fully
up to date while the local folder still shows old files. If Claude worked in a worktree
and pushed straight to `main`, the local clone will be behind until it's synced:

```bash
git -C ~/Downloads/source/jymiller pull   # fast-forward
git -C ~/Downloads/source/jymiller log --oneline -1
```

Anything left uncommitted in a worktree is lost when that worktree is cleaned up — land
work on `main` before walking away from it.

## Publishing — how the site goes live

Pages is configured as **Deploy from a branch → `main`, root (`/`)**. No build step, no
Actions workflow; `.nojekyll` tells GitHub to serve the HTML as-is.

**Pushing to `main` IS the deploy.**

```bash
git add index.html                # stage specific files, not -A
git commit -m "..."
git push origin HEAD:main         # this publishes
```

Pages rebuilds automatically — live in about a minute. Check it:

```bash
gh api repos/jymiller/jymiller/pages/builds/latest --jq '{status,commit}'
gh api repos/jymiller/jymiller/pages --jq '{html_url,build_type,source}'
```

**Gotcha:** work on a feature branch or in a git worktree does **not** publish until it
lands on `main`. Only `main` is served.

## Layout

| Path | What |
|---|---|
| `index.html` | the one-pager — hero, The Work, Recent Gigs, ticker |
| `projects/` | case-study pages linked from Recent Gigs |
| `assets/` | avatar + QR code SVGs |
| `scripts/` | Snowflake sample SQL (linked from the README) |
| `docs/` | RBAC design + principles (linked from the README) |
| `.nojekyll` | disables Jekyll — serve raw HTML |

## Local preview

```bash
python3 -m http.server 8772       # http://localhost:8772
```

Also defined as the `jymiller` config in `.claude/launch.json`.

## Skills

- **`update-ticker`** (`.claude/skills/update-ticker/`) — regenerates the scrolling ticker at
  the bottom of `index.html` from the Snowflake Bay Area user group feed: evergreen intro +
  next meetup + last recap, chosen by date. Run it after each event, review
  `git diff -- index.html`, then push to `main` once John has OK'd it — never push without
  his explicit go-ahead.

## Conventions

- The ticker block between `<!-- TICKER:START -->` and `<!-- TICKER:END -->` is **generated** —
  don't hand-edit it; run the `update-ticker` skill.
- Case-study pages are self-contained HTML with a `← Back to home` link to `../index.html`.
- QR codes in `assets/` encode `https://jymiller.github.io/jymiller/` and the LinkedIn profile.

### This repo is public — everything committed is published

- Case studies show architecture and outcomes **as delivered**: no per-control implementation
  status (done / pending / deferred), no "this sprint", no unreleased client roadmap, moat, or
  investor framing. A client's *current* security posture is theirs, not ours to publish — for a
  regulated client that reads as a control-weakness inventory. The capability is John's story to
  tell; the client's posture and unshipped plans are not.
- Private or client-specific context goes in Claude's memory
  (`~/.claude/projects/<slug>/memory/`), which lives **outside** the repo and is never published.
  Do not put it in a tracked file. Nothing here is a secret store.
- Local-only artifacts must be ignored by **this repo's** `.gitignore`, not by a machine-global
  ignore — a global ignore does not travel to a fork, a template, CI, or another contributor.
- Third-party data (e.g. the user-group feed) that reaches published HTML must be scheme- and
  host-validated, not just HTML-escaped: `html.escape()` will not stop a `javascript:` href.

## Any other repo — is it publishing Pages, and how?

```bash
gh api repos/OWNER/REPO/pages --jq '{html_url,build_type,source}'
```

- `build_type: legacy` + a `source` branch/path → deploys on push to that branch (like this repo).
- `build_type: workflow` → deploys via a GitHub Actions workflow in `.github/workflows/`.
- `404 Not Found` → Pages is not enabled for that repo.

Two naming rules worth remembering:

- `OWNER/OWNER` → its `README.md` renders on the GitHub **profile** page.
- `OWNER/OWNER.github.io` → publishes to the root domain `https://OWNER.github.io/`.
  Any other repo publishes to a subpath: `https://OWNER.github.io/REPO/` (this repo's case).

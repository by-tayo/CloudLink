# CloudLink Screenshots — Final Set

Every image in this folder has been checked with OCR (not just visually) to confirm no
personal email or university name is present anywhere in the top region. This catches
what a quick visual glance can miss — several images that looked cropped at a glance
still had the email present when actually scanned.

## Required — these match the filenames already referenced in README.md and debugging-notes.md

| Filename | Use |
|---|---|
| `workflow-diagram.png` | README.md architecture section |
| `dlq-connection-before.png` | debugging-notes.md — red warning icon, missing connection |
| `dlq-connection-after.png` | debugging-notes.md — connection fixed, paired with above |
| `error-detail-full-message.png` | debugging-notes.md — the actual 400 error that led to the fix |
| `dlq-success-run.png` | README.md Status section + runbook-dlq-alert.md — the final confirmed successful run |

Drop these five directly into `docs/images/` with these exact names — no renaming needed,
the docs already reference them correctly.

## Optional — supporting detail, not referenced by name in any doc

These are here in case you want to expand the debugging story (e.g. showing the *first*
failed attempt before showing the fix, or the two-bug story in more depth). Use them only
if you add your own image references to `debugging-notes.md` — they're not required.

- `optional-502-response-config.png`
- `optional-first-dlq-attempt-failed.png`
- `optional-run-history-diagram-failed.png`
- `optional-error-BadRequest-short.png`
- `optional-error-properties-panel.png`
- `optional-second-dlq-attempt-still-failing.png`
- `optional-dlq-run-failed-attempt-recapture.png`
- `optional-502-response-detail-recapture.png`

## Verification method

Every file was scanned with Tesseract OCR against the top 350px, searching for "utsa",
"tania", or "university" (case-insensitive). Two images that looked fine on casual visual
inspection — including one originally labeled as the "best" screenshot — were found to
still contain the email and were re-cropped. All 15 source images are now confirmed clean
by this method, not by eyeballing alone.

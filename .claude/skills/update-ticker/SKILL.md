---
name: update-ticker
description: Refresh the scrolling "scroll line" (the blue ticker/newsreel) at the bottom of index.html on John's GitHub Pages site (jymiller.github.io/jymiller) from the Snowflake Bay Area user group feed — advertise the next meetup and recap the last one. Use after each Snowflake Bay Area event, or whenever John asks to update the ticker, scroll line, newsreel, or "next event" line.
---

# Update the Snowflake scroll line (ticker)

The ticker is the blue scrolling bar at the bottom of `index.html`. Its content lives
between the `<!-- TICKER:START -->` and `<!-- TICKER:END -->` markers inside
`.ticker-inner` and is **generated** — never hand-edit it. Source of truth is the
Snowflake Bay Area user group feed only: <https://usergroups.snowflake.com/bay-area/>.

The renderer produces three stanzas: an evergreen "leading the group" intro, the
**next upcoming** meetup (advertise), and the **most recent past** meetup (recap).
Past/upcoming are decided by date, so the ticker self-corrects as events roll by.

## Steps

1. **Regenerate** from the live feed:
   ```
   python3 .claude/skills/update-ticker/render_ticker.py
   ```
   (Pass a saved HTML file as an argument to run offline.) The script rewrites the
   block in place and prints what it chose plus a `REMIND_ON=YYYY-MM-DD` line.

2. **Review** the change: `git diff -- index.html`. Confirm the "Next up" and
   "Last meetup" lines read well; the script keeps titles as the feed publishes them,
   so tidy an awkward title by hand *inside the markers* only if needed.

3. **Ship it.** Per John's git rules, do **not** commit or push without his explicit
   OK. GitHub Pages builds from **main**, so the change must land on `main` to go live
   at <https://jymiller.github.io/jymiller/>. Suggested commit: `Refresh event ticker`.

4. **Re-arm the reminder.** Take `REMIND_ON` from the script output (the morning after
   the next event) and create/update a scheduled reminder so John is prompted to run
   this skill again after that event. If there is no upcoming event, set a check-back
   reminder ~2 weeks out instead. Each run re-points the reminder at the newest event.

## Notes
- No new upcoming event on the feed → the "Next up" stanza is omitted automatically; the
  intro + recap still render. Re-run once a new event is posted.
- If the script errors with "`__NEXT_DATA__` not found," the feed's page structure
  changed — inspect the page and adjust the parser in `render_ticker.py`.

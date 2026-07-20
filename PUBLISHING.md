# Publishing workflow — "11 Days of Agent 365"

My own checklist so future-me stays consistent across the series. This is a personal
project — not official Microsoft content. Preview features may change.

## Each publish day

1. Drop screenshots / recordings into `days/day-NN-.../assets/`.
2. Fill in the README sections for that day:
   - **The problem**, **What Agent 365 does about it**, **Try it yourself**,
     **Watch-outs**, **References**.
3. Replace `POST_URL_PLACEHOLDER` in that day's README with the live LinkedIn URL.
4. Update the root [README.md](README.md) series table: change the **Post** column for
   that day from `_coming DD Jul_` to the live LinkedIn link.
5. Put any day-specific scripts / KQL / configs in `days/day-NN-.../technical/`
   (Days 7 and 9 link to `agent-risk/` and `DEV/` at the repo root instead).

## Never commit

- `.env`
- any `*.config.json` (e.g. `a365.config.json`, `a365.generated.config.json`)
- `manifest/`
- any real tenant IDs, subscription IDs, or customer / person names

These are already covered by [.gitignore](.gitignore) — keep it that way.

## Every day's Watch-outs

- Explicitly label each capability as **preview** or **GA**.
- Cross-check the [preview matrix](docs/preview-matrix.md) and update it if status changed.
- Note anything that tripped me up so readers reproducing it don't hit the same wall.

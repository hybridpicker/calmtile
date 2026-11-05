# Contributing

calmtile is a one-person project; small, focused changes are welcome. Open an issue first for anything larger
than a fix.

## Build and test

```bash
scripts/build.sh                       # self-test, then build/calmtile.app
CALMTILE_STRICT=1 scripts/build.sh     # warnings are errors, as in CI
scripts/check-docs.sh                  # links, anchors, config keys and switches against the docs
```

Only the Xcode Command Line Tools are needed. The layout logic lives in `Sources/CalmCore` without AppKit and
is covered by `Sources/calmcore-selftest`; add a check there for every change to it. Everything that touches
real windows has to be tried on a Mac: see [docs/development.md](docs/development.md) for the test aids and
what has been verified.

## Style

- Swift, no dependencies, no new files unless a new concern needs one.
- Keep the key tap and the main loop free of waits; a call into another app must give up (see the Robustness
  notes in [docs/development.md](docs/development.md)).
- Never log window titles or file names.
- Anything user-visible goes into [docs/manual.md](docs/manual.md); `scripts/check-docs.sh` fails if a config
  key or switch is missing there.

## Commits

One logical change per commit, code and documentation in separate commits. English, imperative title under
about 70 characters ("Fix ...", "Docs: ..."), the reason in the body. Say how you verified the change.

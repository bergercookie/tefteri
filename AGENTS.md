# Instructions for coding agents

## Commit messages

- Do not add a `Claude-Session:` line (or any session link) to commit messages.
- Do not add the session link to pull request descriptions either.

## Visual design (frontend)

The look is defined in `docs/developer/design.md` and implemented in
`frontend/lib/theme/`. When you add or change UI:

- Take colors, fonts, spacing and radii from the theme and the tokens
  (`context.tefteri`, `Space`, `Corner`). Do not hard-code `Color(0x...)`,
  `Colors.*` or font names in `lib/features` or `lib/core`; a test enforces
  this.
- Do not fall back to Material defaults: no seeded `ColorScheme`, no Roboto,
  no stock `AppBar`, elevated cards or bare `ListTile` lists as the main
  structure. Use `EmptyState` and `Loading` for empty and loading states.
- Check the result: regenerate the screenshots (`just docs::screenshots`),
  look at them in light and dark and at phone and desktop widths, and fix
  anything that looks generic, cramped or low-contrast.

## Checks before every push

- Run `pre-commit run --all-files` and `just test` before every push, not only before a
  pull request.
- Fix every failure, even one that your change did not cause. Do not push with a red check,
  and do not skip, disable or loosen a hook or a test to get green.
- If a tool is missing in your environment, so that a hook cannot run, say which hooks you
  could not run in your report. Do not call the checks passing.
- After you push to `master` or to a pull request, read the CI result. If CI fails, fix it in
  a new commit and push again until it is green.

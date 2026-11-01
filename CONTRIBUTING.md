# Contributing

Use `just` for everything (run `just --list`). Contributors and coding agents must not call
the underlying tools (pytest, ruff, flutter, docker...) directly.

1. `devbox shell`
2. `just backend::install frontend::install`
3. `just lint` and `just test` before every pull request.

## Writing style

All prose (README, CONTRIBUTING, `docs/`) follows ASD-STE100 Simplified Technical English.
Use short sentences, the active voice, and simple words. `vale` checks the rules it can
(see `.vale/styles/STE/README.md`); it runs in pre-commit.

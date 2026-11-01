# Architecture

A Python (FastAPI) backend syncs on demand with Vikunja (tasks), Google Calendar (events) and
Trilium Next (notes). It does this through adapter ports. A Flutter client shows the views.

The layers are `api`, `services`, `domain` and `adapters`. The `tach` tool checks them:
`api` calls `services`, `services` use `domain`, and `adapters` implement the `domain` ports.
The `db`, `auth` and `security` modules are used by `services`. The `domain` never uses them.

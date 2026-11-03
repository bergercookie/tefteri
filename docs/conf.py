"""Sphinx configuration for the tefteri documentation."""

project = "tefteri"
extensions = ["myst_parser", "sphinxcontrib.mermaid"]
# Lets Markdown pages use ```mermaid fences for diagrams.
myst_fence_as_directive = ["mermaid"]
# Lets Markdown links point to a heading, for example [text](#run-the-server).
myst_heading_anchors = 3
exclude_patterns = ["_build"]
html_theme = "alabaster"

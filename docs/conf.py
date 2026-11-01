"""Sphinx configuration for the tefteri documentation."""

project = "tefteri"
extensions = ["myst_parser", "sphinxcontrib.mermaid"]
# Lets Markdown pages use ```mermaid fences for diagrams.
myst_fence_as_directive = ["mermaid"]
exclude_patterns = ["_build"]
html_theme = "alabaster"

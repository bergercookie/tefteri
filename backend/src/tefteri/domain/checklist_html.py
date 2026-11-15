"""Read the items of an HTML list such as the one that Trilium's editor writes."""

from __future__ import annotations

from html.parser import HTMLParser


class _ListItem:
    """One open ``<li>``, the text that belongs to it directly, and its nested items."""

    def __init__(self) -> None:
        """Start collecting the text of the item."""
        self.text: list[str] = []
        self.children: list[_ListItem] = []
        self.collecting = True

    def texts(self) -> list[str]:
        """Return this item, then its nested items, in document order."""
        text = " ".join("".join(self.text).split())
        nested = [t for child in self.children for t in child.texts()]
        return [text, *nested] if text else nested


class _ListParser(HTMLParser):
    """Collect each list item in document order, including items of nested lists."""

    def __init__(self) -> None:
        """Start with no items and no open lists."""
        super().__init__(convert_charrefs=True)
        self.roots: list[_ListItem] = []
        self._depth = 0
        self._open: list[_ListItem] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:  # noqa: ARG002
        if tag in ("ul", "ol"):
            self._depth += 1
        elif tag == "li" and self._depth > 0:
            item = _ListItem()
            if self._open:
                # A nested list belongs to the parent item, but its words are items of their own.
                self._open[-1].collecting = False
                self._open[-1].children.append(item)
            else:
                self.roots.append(item)
            self._open.append(item)
        elif tag in ("br", "p", "div") and self._open and self._open[-1].collecting:
            self._open[-1].text.append(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in ("ul", "ol"):
            self._depth = max(0, self._depth - 1)
        elif tag == "li" and self._open:
            self._open.pop()
            if self._open:
                # Words after a nested list still belong to the parent item.
                self._open[-1].collecting = True

    def handle_data(self, data: str) -> None:
        if self._open and self._open[-1].collecting:
            self._open[-1].text.append(data)


def list_items_from_html(body: str) -> list[str]:
    """Return the words of each ``<li>`` in ``body``, in order.

    Nested lists contribute their own items as well. Tags are removed, HTML entities are
    decoded, and runs of white space collapse. The caller cleans repeats and the limits.
    """
    parser = _ListParser()
    parser.feed(body)
    parser.close()
    return [text for root in parser.roots for text in root.texts()]

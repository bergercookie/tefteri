"""Read the items of an HTML list such as the one that Trilium's editor writes."""

from __future__ import annotations

from dataclasses import dataclass
from html.parser import HTMLParser


@dataclass(frozen=True)
class ChecklistTextPart:
    """A run of words in an item. ``url`` is set when the run is a link."""

    text: str
    url: str | None = None


@dataclass(frozen=True)
class ChecklistHtmlItem:
    """One list item: its plain words and the runs that build them."""

    text: str
    parts: tuple[ChecklistTextPart, ...]


@dataclass
class _RawText:
    """Words before the white space is made regular."""

    text: str
    url: str | None


class _ListItem:
    """One open ``<li>``: its words and nested items, in document order."""

    def __init__(self) -> None:
        """Start collecting the words of the item."""
        self.blocks: list[_RawText | _ListItem] = []
        self.collecting = True


def _safe_url(value: str | None) -> str | None:
    """Return a link that Tefteri can open, or ``None`` for a relative or odd target."""
    if value is None:
        return None
    url = value.strip()
    if url.lower().startswith(("http://", "https://", "mailto:")):
        return url
    return None


class _ListParser(HTMLParser):
    """Collect each list item in document order, including items of nested lists."""

    def __init__(self) -> None:
        """Start with no items and no open lists."""
        super().__init__(convert_charrefs=True)
        self.roots: list[_ListItem] = []
        self._depth = 0
        self._open: list[_ListItem] = []
        self._link: str | None = None

    def _add_text(self, text: str, url: str | None = None) -> None:
        if self._open and self._open[-1].collecting:
            self._open[-1].blocks.append(_RawText(text, url if url is not None else self._link))

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:  # noqa: ARG002
        if tag in ("ul", "ol"):
            self._depth += 1
        elif tag == "li" and self._depth > 0:
            item = _ListItem()
            if self._open:
                # A nested list belongs to the parent item, but its words are items of their own.
                self._open[-1].collecting = False
                self._open[-1].blocks.append(item)
            else:
                self.roots.append(item)
            self._open.append(item)
        elif tag == "a":
            self._link = _safe_url(next((value for name, value in attrs if name == "href"), None))
        elif tag in ("br", "p", "div") and self._open and self._open[-1].collecting:
            self._add_text(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in ("ul", "ol"):
            self._depth = max(0, self._depth - 1)
        elif tag == "li" and self._open:
            self._open.pop()
            if self._open:
                # Words after a nested list still belong to the parent item.
                self._open[-1].collecting = True
        elif tag == "a":
            self._link = None

    def handle_data(self, data: str) -> None:
        self._add_text(data)


def _own_parts(item: _ListItem) -> list[_RawText]:
    """Return the words that belong to this item, not to its nested items."""
    return [block for block in item.blocks if isinstance(block, _RawText)]


def _items_in_order(item: _ListItem) -> list[_ListItem]:
    """Return an item and its nested items in document order."""
    out = [item]
    for block in item.blocks:
        if isinstance(block, _ListItem):
            out.extend(_items_in_order(block))
    return out


def _normalise(raw: list[_RawText]) -> tuple[str, tuple[ChecklistTextPart, ...]]:
    """Collapse white space and join neighbouring runs with the same link."""
    parts: list[ChecklistTextPart] = []
    pending_space = False
    for piece in raw:
        for char in piece.text:
            if char.isspace():
                pending_space = True
                continue
            if pending_space and parts:
                # A space inside a link stays in the link. Between a link and other words it
                # is plain, so the underline starts and ends at the words.
                space_url = parts[-1].url if parts[-1].url == piece.url else None
                _append(parts, " ", space_url)
            pending_space = False
            _append(parts, char, piece.url)
    text = "".join(part.text for part in parts)
    return text, tuple(parts)


def _append(parts: list[ChecklistTextPart], text: str, url: str | None) -> None:
    if parts and parts[-1].url == url:
        last = parts[-1]
        parts[-1] = ChecklistTextPart(last.text + text, url)
    else:
        parts.append(ChecklistTextPart(text, url))


def list_items_from_html(body: str) -> list[ChecklistHtmlItem]:
    """Return the items of each ``<li>`` in ``body``, in order.

    Nested lists contribute their own items as well. Tags are removed, HTML entities are
    decoded, and runs of white space collapse. A link keeps its target. The caller drops
    repeats and applies the limits.
    """
    parser = _ListParser()
    parser.feed(body)
    parser.close()
    out: list[ChecklistHtmlItem] = []
    for root in parser.roots:
        for item in _items_in_order(root):
            text, parts = _normalise(_own_parts(item))
            if text:
                out.append(ChecklistHtmlItem(text, parts))
    return out

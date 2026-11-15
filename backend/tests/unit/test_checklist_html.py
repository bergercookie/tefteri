"""Read checklist items from the HTML list that Trilium's editor writes."""

from tefteri.domain.checklist_html import list_items_from_html


def test_a_plain_list_gives_its_items_in_order() -> None:
    body = "<ul><li>Look back at last week</li><li>Clear the inbox</li></ul>"
    assert list_items_from_html(body) == ["Look back at last week", "Clear the inbox"]


def test_paragraphs_entities_and_tags_inside_an_item_are_read_as_words() -> None:
    body = (
        "<ul><li><p>Check &amp; clear <strong>the inbox</strong></p></li>"
        "<li>Review<br>the calendar</li></ul>"
    )
    assert list_items_from_html(body) == ["Check & clear the inbox", "Review the calendar"]


def test_nested_list_items_come_after_their_parent() -> None:
    body = (
        "<ul><li>Plan the week<ul><li>Choose the focus</li></ul></li><li>Close the week</li></ul>"
    )
    assert list_items_from_html(body) == ["Plan the week", "Choose the focus", "Close the week"]


def test_an_ordered_list_and_text_around_it_work() -> None:
    body = "<p>Intro</p><ol><li>One</li><li>Two</li></ol><p>End</p>"
    assert list_items_from_html(body) == ["One", "Two"]


def test_a_note_without_a_list_has_no_items() -> None:
    assert list_items_from_html("<p>No list here.</p>") == []
    assert list_items_from_html("") == []

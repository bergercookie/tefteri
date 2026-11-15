"""Read checklist items from the HTML list that Trilium's editor writes."""

from tefteri.domain.checklist_html import (
    ChecklistHtmlItem,
    ChecklistTextPart,
    list_items_from_html,
)


def texts(body: str) -> list[str]:
    return [item.text for item in list_items_from_html(body)]


def test_a_plain_list_gives_its_items_in_order() -> None:
    body = "<ul><li>Look back at last week</li><li>Clear the inbox</li></ul>"
    assert texts(body) == ["Look back at last week", "Clear the inbox"]


def test_paragraphs_entities_and_tags_inside_an_item_are_read_as_words() -> None:
    body = (
        "<ul><li><p>Check &amp; clear <strong>the inbox</strong></p></li>"
        "<li>Review<br>the calendar</li></ul>"
    )
    assert texts(body) == ["Check & clear the inbox", "Review the calendar"]


def test_nested_list_items_come_after_their_parent() -> None:
    body = (
        "<ul><li>Plan the week<ul><li>Choose the focus</li></ul></li><li>Close the week</li></ul>"
    )
    assert texts(body) == ["Plan the week", "Choose the focus", "Close the week"]


def test_an_ordered_list_and_text_around_it_work() -> None:
    body = "<p>Intro</p><ol><li>One</li><li>Two</li></ol><p>End</p>"
    assert texts(body) == ["One", "Two"]


def test_a_note_without_a_list_has_no_items() -> None:
    assert list_items_from_html("<p>No list here.</p>") == []
    assert list_items_from_html("") == []


def test_a_link_keeps_its_words_and_target() -> None:
    body = (
        "<ul><li>Read <a href='https://example.com/post'>the post</a> before the review</li></ul>"
    )
    assert list_items_from_html(body) == [
        ChecklistHtmlItem(
            "Read the post before the review",
            (
                ChecklistTextPart("Read "),
                ChecklistTextPart("the post", "https://example.com/post"),
                ChecklistTextPart(" before the review"),
            ),
        )
    ]


def test_two_links_and_a_mail_link_are_kept() -> None:
    body = (
        "<ul><li><a href='https://a.test'>A</a> and "
        "<a href='mailto:sam@example.com'>mail Sam</a></li></ul>"
    )
    item = list_items_from_html(body)[0]
    assert item.text == "A and mail Sam"
    assert [part.url for part in item.parts] == ["https://a.test", None, "mailto:sam@example.com"]


def test_a_relative_link_keeps_its_words_but_is_not_a_link() -> None:
    item = list_items_from_html("<ul><li>See <a href='#root/abc'>the note</a></li></ul>")[0]
    assert item.text == "See the note"
    assert [part.url for part in item.parts] == [None]


def test_a_nested_item_can_have_a_link_after_its_parent() -> None:
    body = (
        "<ul><li>Plan the week"
        "<ul><li>Open <a href='https://example.com'>the calendar</a></li></ul></li></ul>"
    )
    items = list_items_from_html(body)
    assert [item.text for item in items] == ["Plan the week", "Open the calendar"]
    assert items[1].parts[-1] == ChecklistTextPart("the calendar", "https://example.com")

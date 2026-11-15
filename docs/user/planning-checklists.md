# Planning checklists

A checklist is a list of things to go through when you plan. You can keep a reusable checklist
for annual planning and another for weekly planning.

## Create or edit a checklist

1. Open the menu, choose Settings, then choose Checklists.
2. Write one item on each line in the checklist you want to change.
3. Choose Save.

Tefteri removes empty lines, extra spaces and list markers such as `-` or `*`. It keeps an item
only once if it appears more than once. A checklist can have up to 50 items, with up to 200
characters in each item. To remove a checklist, delete all its lines. If the box is empty, choose
Start from an example to add a list that you can edit.

To change or remove an item, edit its line and choose Save. Renaming an item makes it a new item,
so it is not ticked in the current period.

## Read a checklist from your notes app

You can keep the checklist in your notes app instead of in Tefteri. Tefteri reads the list from
a note each time it shows the checklist, so a change in the note appears at once. You tick the
items in Tefteri as usual. Tefteri saves the ticks for that period on its own and never writes
them back to the note.

1. In your notes app, write the checklist as an HTML list, one item for each `<li>`. The
   CKEditor in Trilium Next makes this list when you choose the bulleted list button.
2. Open the menu, choose Settings, then choose Checklists.
3. In the part of the week, month or year checklist that you want, type the path of the note in
   **Path in your notes app**.
4. Choose Save.

The path is the title of each note from the root note of the Trilium Next connection, with a
slash between the titles. For example, `Checklists/Weekly` finds the note `Weekly` below the
note `Checklists` below the root note. You can also paste a note ID, or the `#root/...` part of
a Trilium Next address. Tefteri uses the first notes connection of your account.

This is the HTML that Tefteri reads:

```html
<ul>
  <li>Look back at last week</li>
  <li>Check the calendar for the week</li>
  <li>Clear the inbox</li>
</ul>
```

Tags inside an item, such as bold or a paragraph, are ignored. Their words stay. The words of a
nested list become items too, after their parent. Empty items and repeats are removed, as for a
local list.

Ticks belong to the period, as for a local checklist. A new week, month or year starts clean,
and an earlier period keeps its ticks. When you change an item in the note, Tefteri sees it as a
new item, so it is not ticked. A tick for an item that left the note is ignored.

To stop reading the note, delete the path and choose Save. The local list below the path is
used again. The source path is a setting of the current user, so every device shows the same
checklist.

## Use a checklist

The weekly checklist appears beside the weekly planning steps. Read
[Weekly planning](weekly-planning.md#go-through-your-own-checklist).

The annual checklist appears in annual planning. Choose an item to tick or untick it. Ticks are
saved for that week or year. A new week or year starts with a clean checklist, while earlier
periods keep their ticks. Checklist items are reminders; they do not stop you from saving a plan.

A checklist that comes from your notes app shows its path and a Refresh button. Tick its items
in Tefteri, and change the list of items in the note. Tefteri never changes the note.

When no checklist exists for a period, Tefteri shows a message and an action to create one. When
a note path is set but the note has no list, Tefteri says so and offers Refresh.

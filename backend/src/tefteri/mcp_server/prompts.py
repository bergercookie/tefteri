"""Ready-made prompts: the reviews and the planning of a day, as a user would ask for them."""

from typing import Any

from mcp.server.fastmcp import FastMCP


def register(mcp: FastMCP) -> None:
    """Add the prompts to ``mcp``."""

    @mcp.prompt(title="Weekly review")
    def weekly_review(week_of: str = "") -> str:
        """Review a week with the data of tefteri, then save the decisions."""
        which = f"the week of {week_of}" if week_of else "the week that is running"
        return (
            f"Help me do my weekly review of {which} with tefteri.\n\n"
            "1. Call get_overview, so that you know today's date and my calendars.\n"
            "2. Call get_weekly_review. Read the look-back (committed and done tasks, the "
            "leftover tasks, the pace per day, the focus share), the completed work by category, "
            "the tasks that are still open, my events, my daily notes and the trends of the last "
            "weeks.\n"
            "3. Tell me how the week went, in plain words and with the numbers: what I planned, "
            "what I did, how much of the work was goal-aligned, maintenance and off-plan, and "
            "how this week compares with the weeks before. Point out one thing that went well "
            "and one thing to change. Do not invent facts that the data does not show.\n"
            "4. For each milestone that is not finished, propose a decision: recommit (carry it "
            "to next week), park, or decide later. Give a reason for each from the data.\n"
            "5. Ask me what I want to change. Only when I agree, call submit_weekly_review with "
            "my reflection and the decisions.\n"
            "6. Offer to plan next week: list_tasks for the open tasks, find_free_time for the "
            "days, and schedule_task for the ones I choose."
        )

    @mcp.prompt(title="Monthly review")
    def monthly_review(month: str = "") -> str:
        """Review a month: its focus, its key results and the weeks in it."""
        which = f"the month {month}" if month else "this month"
        return (
            f"Help me do my monthly review of {which} with tefteri.\n\n"
            "1. Call get_overview for today's date.\n"
            "2. Call get_monthly_review. Read the focus (the themes I chose), the key results "
            "and their values, the work by category and the numbers of each week.\n"
            "3. Judge the month against its focus: which themes got the work, which got none, "
            "whether the key results moved, and how the weeks compare. Be specific and honest.\n"
            "4. For each theme, propose carry, drop, replace or later, with a reason.\n"
            "5. Call save_monthly_review with preview true, show me the effect, and only when I "
            "agree, call it again with preview false.\n"
            "6. Then help me choose the focus of the next month."
        )

    @mcp.prompt(title="Annual review")
    def annual_review(year: str = "") -> str:
        """Review a year: the goals, the key results and the months."""
        which = f"the year {year}" if year else "this year"
        return (
            f"Help me do my annual review of {which} with tefteri.\n\n"
            "1. Call get_overview for today's date.\n"
            "2. Call get_annual_review. Read each goal with its key results and what they "
            "reached, the record of each month, and the balance of the work.\n"
            "3. For each goal, tell me what was reached and what was not, and what the months "
            "show about my effort. Do not guess about months that have no data.\n"
            "4. Write a short note for the year, and a short note for each goal that deserves "
            "one. Show them to me. Only when I agree, save them with save_annual_review_note.\n"
            "5. Suggest what to carry into the plan of the next year."
        )

    @mcp.prompt(title="Plan my day")
    def plan_my_day(date: str = "") -> str:
        """Look at a day and make a realistic plan for it."""
        which = f"the day {date}" if date else "today"
        return (
            f"Help me plan {which} with tefteri.\n\n"
            "1. Call get_overview, then get_day for that day.\n"
            "2. Call list_tasks for the tasks that are due and the ones that are overdue.\n"
            "3. Call find_free_time. Suggest a realistic order for the tasks, in the free time, "
            "and say what to leave for another day.\n"
            "4. When I agree, use schedule_task to put the tasks at their times, and "
            "create_event for anything that needs a block in my calendar."
        )

    @mcp.prompt(title="Plan my week")
    def plan_my_week(date: str = "") -> str:
        """Spread the open tasks over the days of a week."""
        which = f"the week of {date}" if date else "this week"
        return (
            f"Help me plan {which} with tefteri.\n\n"
            "1. Call get_overview and get_week.\n"
            "2. Call list_tasks with due 'week', 'overdue' and 'none' to see what is open.\n"
            "3. Use find_free_time for each weekday. Propose a plan that does not overload any "
            "day, and keep time free for the unexpected.\n"
            "4. When I agree, use schedule_task for each task."
        )

    @mcp.prompt(title="Catch up on overdue tasks")
    def triage_overdue() -> str:
        """Decide what to do with every task that is overdue."""
        return (
            "Help me catch up on my overdue tasks with tefteri.\n\n"
            "1. Call get_overview, then list_tasks with due 'overdue'.\n"
            "2. For each task, suggest one of: do it today, move it to a later day, or drop "
            "it, with a reason. Ask me about the ones that you cannot judge.\n"
            "3. When I agree, use schedule_task, complete_task or delete_task. Ask before you "
            "delete anything."
        )


__all__: list[Any] = ["register"]

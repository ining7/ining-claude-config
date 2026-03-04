# Plan Mode Rules

When in Plan Mode, before exiting plan mode (ExitPlanMode) for user review, you MUST:

1. Use the `/code-review` skill to send the current plan to an independent Claude instance for review
2. Include the full plan content as the argument
3. After receiving the review feedback, integrate any critical issues into the plan
4. Only then proceed with ExitPlanMode

/// The words of the annual review, explained once at their first use.
library;

import '../projects/term_hint.dart';

/// Terms used on the annual review screen.
const annualReviewTerms = [
  Term('Goal', 'What you wanted to achieve in the year.'),
  Term('Key result', 'A number that shows whether a goal was met.'),
  Term('Hit', 'The last value in the year reached the target.'),
  Term('Theme', 'A long-running project whose work serves a key result.'),
  Term('Milestone', 'A small project that was finished inside the theme.'),
  Term('Snapshot',
      'The saved monthly review. The annual review reads it and never changes it.'),
  Term('Work categories',
      'Goal-aligned, maintenance and off-plan work, counted by the server.'),
];

/// The weekly planning session: a checklist that leads through looking back,
/// choosing up to three projects, giving their tasks a day, and committing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/open_url.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../goals/periods.dart';
import 'finish_step.dart';
import 'look_back_step.dart';
import 'projects_step.dart';
import 'tasks_step.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// The steps of the session, in order.
enum WeeklyStep {
  /// Evaluate the week before.
  lookBack('Look back', 'How did last week go?'),

  /// Pick up to three projects.
  projects('Choose projects', 'Up to three for the week'),

  /// Give the tasks a day.
  tasks('Give tasks a day', 'Spread the work over the week'),

  /// Check and commit.
  finish('Check and commit', 'See the week as a whole');

  const WeeklyStep(this.title, this.hint);

  /// Name in the checklist.
  final String title;

  /// A line under the name.
  final String hint;
}

/// Whether [step] is finished in [s].
bool stepDone(WeeklyStep step, WeeklyState s) {
  final plan = s.plan;
  switch (step) {
    case WeeklyStep.lookBack:
      return s.lookBackSettled;
    case WeeklyStep.projects:
      return plan != null && plan.projects.isNotEmpty;
    case WeeklyStep.tasks:
      return plan != null &&
          plan.projects.isNotEmpty &&
          plan.openTasks > 0 &&
          plan.unscheduledTasks == 0;
    case WeeklyStep.finish:
      return plan?.committed ?? false;
  }
}

/// The first step that is not finished (the last one when all are).
WeeklyStep firstOpenStep(WeeklyState s) => WeeklyStep.values
    .firstWhere((st) => !stepDone(st, s), orElse: () => WeeklyStep.finish);

/// Weekly planning page at `/week/plan`.
class WeeklyPlanningScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [initialDate] is a day in the week to plan
  /// (default: the coming week, or this week on a Monday).
  const WeeklyPlanningScreen({this.initialDate, super.key});

  /// A day in the week to plan.
  final DateTime? initialDate;

  @override
  ConsumerState<WeeklyPlanningScreen> createState() =>
      _WeeklyPlanningScreenState();
}

class _WeeklyPlanningScreenState extends ConsumerState<WeeklyPlanningScreen> {
  late DateTime _week;
  WeeklyStep? _step;
  String? _error;
  Timer? _timer;
  bool _polling = false;

  String get _key => dateKey(_week);

  @override
  void initState() {
    super.initState();
    _week =
        weekStartOf(widget.initialDate ?? defaultPlanningWeek(DateTime.now()));
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer?.cancel();
    final every = ref.read(weeklyPollIntervalProvider);
    if (every != null) _timer = Timer.periodic(every, (_) => _poll());
  }

  Future<void> _poll() async {
    if (!mounted || _polling) return;
    final s = ref.read(weeklyStateProvider(_key)).valueOrNull;
    if (s == null) return;
    final watching = (s.plan?.projects.isNotEmpty ?? false) ||
        (s.lookBack != null && !s.lookBack!.reviewed);
    if (!watching) return;
    _polling = true;
    try {
      await ref.read(weeklyStateProvider(_key).notifier).poll();
    } finally {
      _polling = false;
    }
  }

  void _shiftWeek(int d) {
    setState(() {
      _week = DateTime(_week.year, _week.month, _week.day + 7 * d);
      _step = null;
      _error = null;
    });
  }

  Future<bool> _run(Future<dynamic> Function(WeeklyApi api) call) async {
    final message = await ref
        .read(weeklyStateProvider(_key).notifier)
        .apply((api) async => await call(api) as WeeklyState);
    if (!mounted) return false;
    setState(() => _error = message);
    return message == null;
  }

  Future<void> _setDay(String taskId, DateTime? day) async {
    final message =
        await ref.read(weeklyStateProvider(_key).notifier).setDay(taskId, day);
    if (mounted) setState(() => _error = message);
  }

  void _go(WeeklyStep step) => setState(() {
        _step = step;
        _error = null;
      });

  WeeklyActions get _actions => WeeklyActions(
        week: _key,
        run: _run,
        setDay: _setDay,
        openUrl: (url) => ref.read(openUrlProvider)(Uri.parse(url)),
        changePlan: () => _run((api) => api.reopen(_key)),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weeklyStateProvider(_key));
    // Read the task apps once as soon as a week has loaded, so that the
    // counts are current (the timer then keeps them so).
    ref.listen(weeklyStateProvider(_key), (prev, next) {
      if (prev?.valueOrNull == null && next.valueOrNull != null) _poll();
    });
    return AppShell(
      title: 'Weekly planning',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          Expanded(
            child: state.when(
              loading: () => _bare(const Loading()),
              error: (e, _) => _bare(Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(apiErrorMessage(e), key: const Key('load-error')),
                  TextButton(
                    key: const Key('reload-button'),
                    onPressed: () =>
                        ref.read(weeklyStateProvider(_key).notifier).load(),
                    child: const Text('Try again'),
                  ),
                ],
              )),
              data: _content,
            ),
          ),
        ],
      ),
    );
  }

  /// The week switcher above [child], for the states without a plan to show.
  Widget _bare(Widget child) => Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _weekSwitcher(),
            Expanded(child: Center(child: child)),
          ],
        ),
      );

  Widget _content(WeeklyState s) {
    final step = _step ??= firstOpenStep(s);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 860;
      final body = SingleChildScrollView(
        padding: EdgeInsets.all(wide ? Space.xl : Space.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _weekSwitcher(),
                const SizedBox(height: Space.lg),
                if (s.plan?.committed ?? false)
                  if (step == WeeklyStep.projects || step == WeeklyStep.tasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.lg),
                      child: Notice(
                        icon: Icons.lock_outline,
                        message: 'This plan is committed. To change it, '
                            'open it for editing again.',
                        actions: [
                          OutlinedButton(
                            key: const Key('change-plan'),
                            onPressed: _actions.changePlan,
                            child: const Text('Change the plan'),
                          ),
                        ],
                      ),
                    ),
                _stepBody(s, step),
              ],
            ),
          ),
        ),
      );
      if (!wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CompactChecklist(state: s, step: step, onSelect: _go),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: _SideChecklist(state: s, step: step, onSelect: _go),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      );
    });
  }

  Widget _weekSwitcher() {
    final text = Theme.of(context).textTheme;
    final thisMonday = weekStartOf(DateTime.now());
    final diff = _week.difference(thisMonday).inDays ~/ 7;
    final relative = switch (diff) {
      0 => 'this week',
      1 => 'next week',
      -1 => 'last week',
      _ => null,
    };
    return Row(
      children: [
        IconButton(
          key: const Key('prev-period'),
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shiftWeek(-1),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(weekTitle(_week),
                  key: const Key('period-label'),
                  style: text.titleLarge,
                  overflow: TextOverflow.ellipsis),
              if (relative != null)
                Text('Planning $relative', style: text.bodySmall),
            ],
          ),
        ),
        IconButton(
          key: const Key('next-period'),
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _shiftWeek(1),
        ),
        const Spacer(),
        _RefreshNote(week: _key),
      ],
    );
  }

  Widget _stepBody(WeeklyState s, WeeklyStep step) {
    switch (step) {
      case WeeklyStep.lookBack:
        return LookBackStep(
          key: ValueKey('look-back-${s.lookBack?.planId}'),
          state: s,
          actions: _actions,
          onNext: () => _go(WeeklyStep.projects),
        );
      case WeeklyStep.projects:
        return ProjectsStep(
          state: s,
          actions: _actions,
          onBack: () => _go(WeeklyStep.lookBack),
          onNext: () => _go(WeeklyStep.tasks),
        );
      case WeeklyStep.tasks:
        return TasksStep(
          state: s,
          actions: _actions,
          onBack: () => _go(WeeklyStep.projects),
          onNext: () => _go(WeeklyStep.finish),
        );
      case WeeklyStep.finish:
        return FinishStep(
          state: s,
          actions: _actions,
          onBack: () => _go(WeeklyStep.tasks),
        );
    }
  }
}

/// "Checked 12:03" and a button that checks now.
class _RefreshNote extends ConsumerWidget {
  const _RefreshNote({required this.week});

  final String week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild with every new state: each poll sets one.
    ref.watch(weeklyStateProvider(week));
    final at = ref.read(weeklyStateProvider(week).notifier).refreshedAt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (at != null && MediaQuery.sizeOf(context).width >= 600)
          Text('Checked ${hhmm(at)}',
              key: const Key('checked-at'),
              style: Theme.of(context).textTheme.bodySmall),
        IconButton(
          key: const Key('refresh-now'),
          tooltip: 'Check the task app now',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(weeklyStateProvider(week).notifier).poll(),
        ),
      ],
    );
  }
}

String _detail(WeeklyStep step, WeeklyState s) {
  final plan = s.plan;
  switch (step) {
    case WeeklyStep.lookBack:
      if (s.lookBack == null) return 'Nothing to look back on';
      if (s.lookBack!.reviewed) return 'Done';
      if (plan?.retroSkipped ?? false) return 'Skipped';
      return step.hint;
    case WeeklyStep.projects:
      final n = plan?.projects.length ?? 0;
      return n == 0 ? step.hint : '$n of ${plan?.maxProjects ?? 3} chosen';
    case WeeklyStep.tasks:
      if (plan == null || plan.projects.isEmpty) return step.hint;
      return '${plan.plannedTasks} of ${plan.openTasks} have a day';
    case WeeklyStep.finish:
      return (plan?.committed ?? false) ? 'Committed' : step.hint;
  }
}

class _SideChecklist extends StatelessWidget {
  const _SideChecklist(
      {required this.state, required this.step, required this.onSelect});

  final WeeklyState state;
  final WeeklyStep step;
  final void Function(WeeklyStep) onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = WeeklyStep.values.where((s) => stepDone(s, state)).length;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        key: const Key('checklist'),
        padding: const EdgeInsets.all(Space.lg),
        children: [
          Text('Checklist', style: text.titleMedium),
          const SizedBox(height: Space.xs),
          Text('$done of ${WeeklyStep.values.length} done',
              key: const Key('checklist-progress'), style: text.bodySmall),
          const SizedBox(height: Space.md),
          for (final st in WeeklyStep.values)
            _ChecklistRow(
              step: st,
              current: st == step,
              done: stepDone(st, state),
              detail: _detail(st, state),
              onTap: () => onSelect(st),
            ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.step,
    required this.current,
    required this.done,
    required this.detail,
    required this.onTap,
  });

  final WeeklyStep step;
  final bool current;
  final bool done;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: current,
      child: InkWell(
        key: Key('check-${step.name}'),
        borderRadius: BorderRadius.circular(Corner.md),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: Space.xs),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: current ? scheme.surfaceContainer : null,
            borderRadius: BorderRadius.circular(Corner.md),
            border:
                Border.all(color: current ? colors.rule : Colors.transparent),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                key: Key(done ? 'done-${step.name}' : 'open-${step.name}'),
                size: 22,
                color: done ? colors.done : scheme.onSurfaceVariant,
                semanticLabel: done ? 'Done' : 'Not done',
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title,
                        style: text.titleSmall?.copyWith(
                            fontWeight:
                                current ? FontWeight.w600 : FontWeight.w500)),
                    Text(detail, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The checklist on a narrow screen: a progress bar of four segments and the
/// name of the step; the chips below jump to any step.
class _CompactChecklist extends StatelessWidget {
  const _CompactChecklist(
      {required this.state, required this.step, required this.onSelect});

  final WeeklyState state;
  final WeeklyStep step;
  final void Function(WeeklyStep) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final index = WeeklyStep.values.indexOf(step);
    return Container(
      key: const Key('checklist'),
      color: scheme.surface,
      padding:
          const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Step ${index + 1} of ${WeeklyStep.values.length}: ${step.title}',
              key: const Key('checklist-progress'),
              style: text.titleSmall),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              for (final st in WeeklyStep.values)
                Expanded(
                  child: InkWell(
                    key: Key('check-${st.name}'),
                    onTap: () => onSelect(st),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: Space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: stepDone(st, state)
                                  ? colors.done
                                  : st == step
                                      ? scheme.primary
                                      : colors.rule,
                              borderRadius: BorderRadius.circular(Corner.pill),
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          Icon(
                            stepDone(st, state)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            key: Key(stepDone(st, state)
                                ? 'done-${st.name}'
                                : 'open-${st.name}'),
                            size: 16,
                            color: stepDone(st, state)
                                ? colors.done
                                : scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows the weekly planning page from other screens.
void openWeeklyPlanning(BuildContext context, {DateTime? week}) {
  final q = week == null ? '' : '?date=${dateKey(week)}';
  context.go('/week/plan$q');
}

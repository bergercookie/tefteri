import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/project_chip.dart';
import 'package:tefteri/features/weekly/weekly_models.dart';
import 'package:tefteri/theme/theme.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: tefteriLight, home: Scaffold(body: child));

Color _dot(WidgetTester tester) => ((tester
        .widget<Container>(find.descendant(
            of: find.byType(ProjectDot), matching: find.byType(Container)))
        .decoration!) as BoxDecoration)
    .color!;

void main() {
  testWidgets('a project with a color in its task app uses it', (tester) async {
    await tester
        .pumpWidget(_app(const ProjectDot(name: 'Website', color: '#d50000')));
    expect(_dot(tester), const Color.fromARGB(255, 213, 0, 0));
  });

  testWidgets('a project without one gets the same palette accent each time',
      (tester) async {
    await tester.pumpWidget(_app(const ProjectDot(name: 'Website')));
    final a = _dot(tester);
    await tester
        .pumpWidget(_app(const ProjectDot(name: 'Website', color: 'red')));
    expect(_dot(tester), a); // not a color: the palette accent
    expect(a, TefteriColors.light.projectColor('Website'));
  });

  testWidgets('the card of a project has a stripe in its color',
      (tester) async {
    await tester.pumpWidget(_app(const ProjectCard(
        name: 'Website', color: '#33b679', child: SizedBox(height: 40))));
    final stripe = tester
        .widgetList<ColoredBox>(find.descendant(
            of: find.byType(ProjectCard), matching: find.byType(ColoredBox)))
        .map((b) => b.color);
    expect(stripe, contains(const Color.fromARGB(255, 51, 182, 121)));
  });

  test('the weekly models keep the color of a project', () {
    final plan = WeeklyProject.fromJson(const {
      'id': 'p',
      'name': 'Website',
      'color': '#d50000',
      'created_here': false,
    });
    expect(plan.color, '#d50000');
    final back = LookBackProject.fromJson(const {
      'id': 'b',
      'name': 'Website',
      'color': '#33b679',
      'committed': 1,
      'done': 0,
      'completed': false,
    });
    expect(back.color, '#33b679');
  });
}

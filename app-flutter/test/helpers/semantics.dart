import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Performs [action] the way TalkBack does: on the semantics node of
/// [finder], not via a pointer. Fails if the node doesn't offer the action.
void semanticsAction(WidgetTester tester, Finder finder, [SemanticsAction action = SemanticsAction.tap]) {
  final node = tester.getSemantics(finder);
  expect(node.getSemanticsData().hasAction(action), isTrue, reason: '$action on ${node.label}');
  node.owner!.performAction(node.id, action);
}

/// Runs the custom accessibility action [label] (TalkBack "Aktionen" menu)
/// on the first semantics node offering it. Fails if none does.
void semanticsCustomAction(WidgetTester tester, String label) {
  final id = CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label));
  var root = tester.getSemantics(find.byType(Scaffold).first);
  while (root.parent != null) {
    root = root.parent!;
  }
  final owner = root.owner!;
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    if (node.getSemanticsData().customSemanticsActionIds?.contains(id) ?? false) {
      found = node;
      return false;
    }
    node.visitChildren(visit);
    return found == null;
  }

  visit(root);
  expect(found, isNotNull, reason: 'no node offers "$label"');
  owner.performAction(found!.id, SemanticsAction.customAction, id);
}

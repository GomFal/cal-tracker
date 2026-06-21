import 'package:flutter/material.dart';

import 'design_system.dart';

class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.subtitle,
    this.leading,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return FreshPage(
      title: title,
      subtitle: subtitle,
      actions: actions ?? const [],
      leading: leading,
      child: child,
    );
  }
}

class ContentSliverFrame extends StatelessWidget {
  const ContentSliverFrame({
    super.key,
    required this.title,
    required this.slivers,
    this.actions,
    this.subtitle,
    this.leading,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget>? actions;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return FreshSliverPage(
      title: title,
      subtitle: subtitle,
      actions: actions ?? const [],
      leading: leading,
      slivers: slivers,
    );
  }
}

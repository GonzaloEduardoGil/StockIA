import 'package:flutter/material.dart';

import '../app.dart';

class OperationFrame extends StatelessWidget {
  const OperationFrame({
    required this.embedded,
    required this.title,
    required this.content,
    required this.actions,
    this.backgroundColor,
    this.constraints,
    this.actionsPadding,
    super.key,
  });
  final bool embedded;
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final Color? backgroundColor;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? actionsPadding;
  @override
  Widget build(BuildContext context) => embedded
      ? Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 20),
              content,
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ),
            ],
          ),
        )
      : AlertDialog(
          title: title,
          content: content,
          actions: actions,
          backgroundColor: backgroundColor,
          constraints: constraints,
          actionsPadding: actionsPadding,
        );
}

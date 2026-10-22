import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobileBody;
  final Widget webBody;

  const ResponsiveLayout({
    Key? key,
    required this.mobileBody,
    required this.webBody,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // If the screen width is less than 800px, display the mobile UI
        if (constraints.maxWidth < 800) {
          return mobileBody;
        } 
        // Otherwise, display the desktop web UI
        else {
          return webBody;
        }
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'responsive/responsive_layout.dart';
import 'screens/web/web_dashboard_screen.dart';
import 'screens/mobile/mobile_home_screen.dart';

void main() {
  runApp(const AutoRepairApp());
}

class AutoRepairApp extends StatelessWidget {
  const AutoRepairApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Repair System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // This is the magic! It automatically switches the UI based on the device width.
      home: const ResponsiveLayout(
        mobileBody: MobileHomeScreen(),
        webBody: WebDashboardScreen(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/theme.dart';
import 'router.dart';

class OrdoApp extends StatelessWidget {
  const OrdoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ordo',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens.dart';
import 'state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final state = AppState();
  runApp(PedalPonteApp(state: state));
  state.init();
}

class PedalPonteApp extends StatelessWidget {
  const PedalPonteApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pedal Ponte',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeShell(state: state),
    );
  }
}

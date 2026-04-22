import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/simf_controller.dart';
import '../screens/player_list_screen.dart';
import '../theme/simf_theme.dart';

class SimfApp extends StatelessWidget {
  const SimfApp({super.key, required this.controller});

  final SimfController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        title: 'SIMF',
        debugShowCheckedModeBanner: false,
        theme: SimfTheme.dark(),
        home: const PlayerListScreen(),
      ),
    );
  }
}

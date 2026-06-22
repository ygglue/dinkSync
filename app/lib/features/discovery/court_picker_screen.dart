import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/court.dart';
import 'court_list_screen.dart';

class CourtPickerScreen extends StatelessWidget {
  const CourtPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select a court')),
      body: CourtListScreen(
        onSelect: (Court court) => context.pop(court),
      ),
    );
  }
}

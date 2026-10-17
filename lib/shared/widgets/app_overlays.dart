import 'package:flutter/material.dart';

import 'snackbar.dart';

class AppOverlays extends StatelessWidget {
  const AppOverlays({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(child: AppSnackBarOverlay(child: child));
  }
}

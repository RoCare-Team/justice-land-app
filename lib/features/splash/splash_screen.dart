import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shown while the session is being read.
///
/// The router waits for that answer before deciding anything, so this is the
/// one moment where "we do not know yet" is the honest state — better than
/// flashing the signed-out home screen at someone who is signed in.
///
/// Where it goes next is not decided here. This screen used to ask whether the
/// intro was still owed, after its own first frame, and lost that race to the
/// session resolving — a fresh install went straight to the home screen. main()
/// now answers the question before the app starts and the router reads it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The scales in a gold ring — the site's own mark, in the two
            // colours the whole product is built from.
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent.withOpacity(0.55), width: 2),
              ),
              child: Icon(Icons.balance_rounded, size: 44, color: AppColors.accent),
            ),
            const SizedBox(height: 22),
            const Text(
              'JUSTICELAND',
              style: TextStyle(
                fontFamily: AppText.display,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: 3.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Anonymous Legal Help',
              style: TextStyle(
                fontSize: 12.5,
                letterSpacing: 0.4,
                color: AppColors.accent.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'Get legal help privately from verified advocates',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.white.withOpacity(0.72),
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

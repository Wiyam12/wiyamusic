import 'package:animated_icon/animated_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/widgets/wiya_animated_icon.dart';

/// Branded cold-start splash matching WiyaDesign (dark glass + neon blue).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;
  late final Animation<double> _glowPulse;
  late final Animation<Offset> _titleSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.55, curve: Curves.easeOut),
    );
    _scaleIn = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.65, curve: Curves.easeOutBack),
      ),
    );
    _glowPulse = Tween<double>(begin: 0.18, end: 0.38).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 1, curve: Curves.easeInOut),
      ),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.28, 0.85, curve: Curves.easeOutCubic),
          ),
        );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: WiyaDesign.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _SplashAtmosphere(),
            SafeArea(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Column(
                    children: [
                      const Spacer(flex: 5),
                      FadeTransition(
                        opacity: _fadeIn,
                        child: ScaleTransition(
                          scale: _scaleIn,
                          child: _SplashMark(glowOpacity: _glowPulse.value),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeTransition(
                        opacity: _fadeIn,
                        child: SlideTransition(
                          position: _titleSlide,
                          child: const Column(
                            children: [
                              Text(
                                'WiyaMusic',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: WiyaDesign.onSurface,
                                  fontFamily: 'paytoneOne',
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.9,
                                  height: 1.05,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Listen without noise',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: WiyaDesign.onSurfaceVariant,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(flex: 4),
                      FadeTransition(
                        opacity: _fadeIn,
                        child: const Padding(
                          padding: EdgeInsets.only(bottom: 36),
                          child: WiyaAnimatedIcon(
                            icon: AnimateIcons.loading4,
                            size: 36,
                            color: WiyaDesign.primary,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashAtmosphere extends StatelessWidget {
  const _SplashAtmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WiyaDesign.background,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            WiyaDesign.primaryDeep.withValues(alpha: 0.34),
            WiyaDesign.background,
            WiyaDesign.primary.withValues(alpha: 0.12),
          ],
          stops: const [0, 0.48, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: const Alignment(0, -0.55),
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    WiyaDesign.primaryBright.withValues(alpha: 0.22),
                    WiyaDesign.primaryBright.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0.85, 0.75),
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    WiyaDesign.primaryDeep.withValues(alpha: 0.28),
                    WiyaDesign.primaryDeep.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashMark extends StatelessWidget {
  const _SplashMark({required this.glowOpacity});

  final double glowOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      height: 118,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WiyaDesign.cornerRadius),
        boxShadow: WiyaDesign.softGlow(
          color: WiyaDesign.primary,
          blur: 34,
          opacity: glowOpacity,
        ),
        border: Border.all(
          color: WiyaDesign.primaryBright.withValues(alpha: 0.28),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            WiyaDesign.surfaceHighest.withValues(alpha: 0.9),
            WiyaDesign.surfaceContainer.withValues(alpha: 0.95),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: const WiyaAnimatedIcon(
        icon: AnimateIcons.activity,
        size: 72,
        color: WiyaDesign.primaryBright,
      ),
    );
  }
}

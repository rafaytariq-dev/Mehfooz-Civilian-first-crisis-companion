/// App Router — centralized routing for all 8 screens.
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/report_screen.dart';
import 'screens/situation_detail_screen.dart';
import 'screens/safe_route_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/agent_trace_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/heatwave_screen.dart';
import 'screens/first_aid_screen.dart';
import 'screens/broadcast_compose_screen.dart';
import 'screens/broadcast_feed_screen.dart';

class AppRouter {
  static const home = '/';
  static const onboarding = '/onboarding';
  static const report = '/report';
  static const situationDetail = '/situation';
  static const safeRoute = '/safe-route';
  static const sos = '/sos';
  static const agentTrace = '/trace';
  static const profile = '/profile';
  static const heatwave = '/heatwave';
  static const firstAid = '/first-aid';
  static const broadcastCompose = '/broadcast/compose';
  static const broadcastFeed = '/broadcast/feed';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return _slide(const HomeScreen());

      case onboarding:
        return _fade(const OnboardingScreen());

      case report:
        return _slide(const ReportScreen());

      case situationDetail:
        final eventId = settings.arguments as String? ?? '';
        return _slide(SituationDetailScreen(eventId: eventId));

      case safeRoute:
        return _slide(const SafeRouteScreen());

      case sos:
        return _fade(const SosScreen());

      case agentTrace:
        final eventId = settings.arguments as String? ?? '';
        return _slide(AgentTraceScreen(eventId: eventId));

      case profile:
        return _slide(const ProfileScreen());

      case heatwave:
        final city = settings.arguments as String? ?? 'Karachi';
        return _slide(HeatwaveScreen(city: city));

      case firstAid:
        return _slide(const FirstAidScreen());

      case broadcastCompose:
        return _slide(const BroadcastComposeScreen());

      case broadcastFeed:
        return _slide(const BroadcastFeedScreen());

      default:
        return _fade(const HomeScreen());
    }
  }

  static PageRouteBuilder _slide(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  static PageRouteBuilder _fade(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 250),
    );
  }
}

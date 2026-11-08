import 'package:flutter/material.dart';
import '../features/session_flow/home_screen.dart';
import '../features/session_flow/create_gathering_screen.dart';
import '../features/session_flow/menu_selection_screen.dart';
import '../features/session_flow/participant_name_screen.dart';
import '../features/session_flow/participant_order_screen.dart';
import '../features/session_flow/pass_phone_screen.dart';
import '../features/session_flow/review_orders_screen.dart';
import '../features/session_flow/waiter_mode_screen.dart';
import '../features/session_flow/session_summary_screen.dart';
import '../features/session_flow/bill_summary_screen.dart';
import '../features/session_flow/edit_menu_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/create_gathering':
        return MaterialPageRoute(builder: (_) => const CreateGatheringScreen());
      case '/menu_selection':
        final gatheringData = settings.arguments as Map<String, String>;
        return MaterialPageRoute(
          builder: (_) => MenuSelectionScreen(gatheringData: gatheringData),
        );
      case '/edit_menu':
        return MaterialPageRoute(builder: (_) => const EditMenuScreen());
      case '/participant_name':
        return MaterialPageRoute(builder: (_) => const ParticipantNameScreen());
      case '/participant_order':
        final args = settings.arguments as ParticipantOrderArgs;
        return MaterialPageRoute(
          builder: (_) => ParticipantOrderScreen(args: args),
        );
      case '/pass_phone':
        return MaterialPageRoute(builder: (_) => const PassPhoneScreen());
      case '/review_orders':
        return MaterialPageRoute(builder: (_) => const ReviewOrdersScreen());
      case '/waiter_mode':
        return MaterialPageRoute(builder: (_) => const WaiterModeScreen());
      case '/session_summary':
        return MaterialPageRoute(builder: (_) => const SessionSummaryScreen());
      case '/bill_summary':
        return MaterialPageRoute(builder: (_) => const BillSummaryScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}

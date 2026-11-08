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
import '../shared/models/models.dart';
class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/create_gathering':
        return MaterialPageRoute(builder: (_) => const CreateGatheringScreen());
      case '/menu_selection':
        final gatheringData = settings.arguments as Map<String, String>;
        return MaterialPageRoute(builder: (_) => MenuSelectionScreen(gatheringData: gatheringData));
      case '/edit_menu':
        final session = settings.arguments as Session;
        return MaterialPageRoute(builder: (_) => EditMenuScreen(session: session));
      case '/participant_name':
        final session = settings.arguments as Session;
        return MaterialPageRoute(builder: (_) => ParticipantNameScreen(session: session));
      case '/participant_order':
        final args = settings.arguments as Map<String, dynamic>;
        final session = args['session'] as Session;
        final participant = args['participant'] as Participant;
        final isEditing = args['isEditing'] as bool? ?? false;
        return MaterialPageRoute(
            builder: (_) => ParticipantOrderScreen(session: session, participant: participant, isEditing: isEditing));
      case '/pass_phone':
        final session = settings.arguments as Session;
        return MaterialPageRoute(builder: (_) => PassPhoneScreen(session: session));
      case '/review_orders':
        final session = settings.arguments as Session;
        return MaterialPageRoute(builder: (_) => ReviewOrdersScreen(session: session));
      case '/waiter_mode':
        final session = settings.arguments as Session;
        return MaterialPageRoute(builder: (_) => WaiterModeScreen(session: session));
      case '/session_summary':
        final session = settings.arguments as Session;
        return MaterialPageRoute(builder: (_) => SessionSummaryScreen(session: session));
      case '/bill_summary':
        final session = settings.arguments as Session;
        return MaterialPageRoute(builder: (_) => BillSummaryScreen(session: session));
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}

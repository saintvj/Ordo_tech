import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import 'gathering_menu_button.dart';

class PassPhoneScreen extends StatelessWidget {
  const PassPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Reached via go from the order screen, so there is nothing beneath
    // this screen in history to go back to.
    return PopScope(
      canPop: false,
      child: Scaffold(
        // No title: just room for the "More options" menu, in the same
        // ivory as the page.
        appBar: AppBar(
          automaticallyImplyLeading: false,
          actions: const [GatheringMenuButton()],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 32),
                Text('Order Saved', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 16),
                Text(
                  'Please pass the phone to the next person or finish ordering.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      // go (not push): keeps the back stack at one entry
                      // per cycle instead of growing with each participant.
                      // See participant_name_screen.dart.
                      context.go(Routes.participantName);
                    },
                    child: const Text('Next Person'),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      // push (not go): back from Review Orders returns
                      // here, so a late arrival can still be added with
                      // "Next Person". The stack is at most two deep.
                      context.push(Routes.reviewOrders);
                    },
                    child: const Text('Finish Ordering'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'participant_order_screen.dart';
import 'gathering_menu_button.dart';

class ParticipantNameScreen extends StatefulWidget {
  const ParticipantNameScreen({super.key});

  @override
  State<ParticipantNameScreen> createState() => _ParticipantNameScreenState();
}

class _ParticipantNameScreenState extends State<ParticipantNameScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _next() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      // go (not push): each participant's turn replaces the previous one
      // in history, so the back stack does not grow with the number of
      // participants. See pass_phone_screen.dart for the matching half of
      // this cycle.
      context.go(ParticipantOrderArgs.newParticipant(name).location);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // This screen is only ever reached via context.go, which replaces
    // history rather than pushing, so there is no previous ordering-flow
    // screen left to pop back into; see the comment in _next() and in
    // pass_phone_screen.dart. canPop is false regardless of participant
    // count, and the app bar shows no back button to match.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Join Gathering'),
          automaticallyImplyLeading: false,
          actions: const [GatheringMenuButton()],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Who is ordering?',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your name to browse the menu and place your order.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Your Name',
                      hintText: 'e.g., Jane',
                    ),
                    onSubmitted: (_) => _next(),
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _next,
                    child: const Text('Continue to Menu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

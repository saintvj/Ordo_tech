import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/gathering_controller.dart';
import 'participant_order_screen.dart';

class ParticipantNameScreen extends ConsumerStatefulWidget {
  const ParticipantNameScreen({super.key});

  @override
  ConsumerState<ParticipantNameScreen> createState() =>
      _ParticipantNameScreenState();
}

class _ParticipantNameScreenState extends ConsumerState<ParticipantNameScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _next() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/participant_order',
        arguments: ParticipantOrderArgs.newParticipant(name),
      );
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
    // The menu is locked once ordering starts, so the first participant
    // cannot go back to the menu editor.
    final hasParticipants = ref.watch(
      gatheringProvider.select((g) => g?.participants.isNotEmpty ?? false),
    );
    return PopScope(
      canPop: hasParticipants,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Join Gathering'),
          automaticallyImplyLeading: hasParticipants,
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
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
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

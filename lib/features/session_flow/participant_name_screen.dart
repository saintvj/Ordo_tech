import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class ParticipantNameScreen extends StatefulWidget {
  final Session session;
  const ParticipantNameScreen({super.key, required this.session});

  @override
  State<ParticipantNameScreen> createState() => _ParticipantNameScreenState();
}

class _ParticipantNameScreenState extends State<ParticipantNameScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _next() {
    if (_nameController.text.trim().isNotEmpty) {
      final participant = Participant(
        id: DateTime.now().toString(),
        name: _nameController.text.trim(),
      );
      widget.session.participants.add(participant);
      Navigator.pushNamed(
        context,
        '/participant_order',
        arguments: {
          'session': widget.session,
          'participant': participant,
        },
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Gathering'),
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
    );
  }
}

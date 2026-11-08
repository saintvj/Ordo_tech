import 'package:flutter/material.dart';
import '../../shared/models/models.dart';

class PassPhoneScreen extends StatelessWidget {
  final Session session;
  const PassPhoneScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
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
              Text(
                'Order Saved',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Please pass the phone to the next person or finish ordering.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/participant_name',
                      arguments: session,
                    );
                  },
                  child: const Text('Next Person'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/review_orders',
                      arguments: session,
                    );
                  },
                  child: const Text('Finish Ordering'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

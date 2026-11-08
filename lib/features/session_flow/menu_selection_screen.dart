import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../application/gathering_controller.dart';
import '../../domain/temporary_menu.dart';

class MenuSelectionScreen extends ConsumerWidget {
  final GatheringDetailsArgs details;

  const MenuSelectionScreen({super.key, required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('The Menu')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How are we ordering?',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),

              // Scan Menu Card
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          "Coming Soon: AI-powered menu scanning will automatically build today's menu.",
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: theme.colorScheme.secondary,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.document_scanner_outlined,
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Scan Menu',
                              style: theme.textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Coming Soon',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "AI-powered menu scanning will automatically build today's menu.",
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),

              // Use Temporary Menu Button
              FilledButton.icon(
                onPressed: () {
                  ref
                      .read(gatheringProvider.notifier)
                      .startGathering(
                        name: details.gatheringName,
                        restaurantName: details.restaurantName,
                        hostName: details.hostName,
                        menu: temporaryMenu,
                      );
                  // Starting the gathering moves its lifecycle to
                  // menuDraft; the router's redirect now sends every
                  // pre-gathering route here, so clear them from the
                  // stack rather than pushing on top of them.
                  context.go(Routes.editMenu);
                },
                icon: const Icon(Icons.list_alt),
                label: const Text('Use Temporary Menu'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(
                    color: theme.colorScheme.onSurface.withOpacity(0.1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

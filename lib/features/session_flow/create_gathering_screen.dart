import 'package:flutter/material.dart';

class CreateGatheringScreen extends StatefulWidget {
  const CreateGatheringScreen({super.key});

  @override
  State<CreateGatheringScreen> createState() => _CreateGatheringScreenState();
}

class _CreateGatheringScreenState extends State<CreateGatheringScreen> {
  final _formKey = GlobalKey<FormState>();
  final _gatheringNameController = TextEditingController();
  final _restaurantNameController = TextEditingController();
  final _hostNameController = TextEditingController();

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final gatheringData = {
        'gatheringName': _gatheringNameController.text.trim(),
        'restaurantName': _restaurantNameController.text.trim(),
        'hostName': _hostNameController.text.trim(),
      };
      Navigator.pushNamed(context, '/menu_selection', arguments: gatheringData);
    }
  }

  @override
  void dispose() {
    _gatheringNameController.dispose();
    _restaurantNameController.dispose();
    _hostNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New Gathering')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              Text('Set the stage.', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Enter the details for your dining session.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _gatheringNameController,
                decoration: const InputDecoration(
                  labelText: 'Gathering Name',
                  hintText: 'e.g., Sunday Brunch',
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _restaurantNameController,
                decoration: const InputDecoration(
                  labelText: 'Restaurant Name',
                  hintText: 'e.g., The French Laundry',
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _hostNameController,
                decoration: const InputDecoration(
                  labelText: 'Host Name',
                  hintText: 'Your name',
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 48),
              FilledButton(onPressed: _submit, child: const Text('Continue')),
            ],
          ),
        ),
      ),
    );
  }
}

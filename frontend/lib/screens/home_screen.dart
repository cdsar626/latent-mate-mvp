import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/pet_widget.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final gameProvider = Provider.of<GameProvider>(context);

    if (gameProvider.gameState == GameState.inGame) {
        return const GameScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('LatentMate')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PetWidget(size: 150),
              const SizedBox(height: 32),
              if (gameProvider.gameState == GameState.connecting)
                Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Enter Name'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (_nameController.text.isNotEmpty) {
                          gameProvider.init(_nameController.text);
                        }
                      },
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              if (gameProvider.gameState == GameState.lobby)
                ElevatedButton(
                  onPressed: () {
                    gameProvider.findMatch();
                  },
                  child: const Text('Find Match'),
                ),
              if (gameProvider.gameState == GameState.matching)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Looking for a match...'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

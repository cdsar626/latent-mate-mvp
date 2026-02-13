import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import 'chat_screen.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gameProvider = Provider.of<GameProvider>(context);
    final question = gameProvider.currentQuestion;

    return Scaffold(
      appBar: AppBar(
        title: Text('Match with ${gameProvider.currentMatch?.opponentUsername ?? "Unknown"}'),
        actions: [
            Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text("Affinity: ${gameProvider.affinity}"))
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: question == null
                ? const Center(child: Text("Waiting for question..."))
                : Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          question.text,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        if (gameProvider.hasAnswered)
                           const Text("Waiting for opponent...")
                        else
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => gameProvider.answerQuestion(question.optionA),
                                  child: Text(question.optionA),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => gameProvider.answerQuestion(question.optionB),
                                  child: Text(question.optionB),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          const Divider(),
          const Expanded(
            flex: 3,
            child: ChatScreen(),
          ),
        ],
      ),
    );
  }
}

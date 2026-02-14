import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/pet_widget.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String username;
  const ProfileSetupScreen({super.key, required this.username});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // Simple "Pet" configuration
  Color _petColor = Colors.grey;
  final TextEditingController _bioController = TextEditingController();
  final List<String> _selectedTags = [];
  final List<String> _availableTags = ["Movies", "Music", "Tech", "Travel", "Food", "Art"];

  void _finishSetup() {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);

    // Initialize connection first
    gameProvider.init(widget.username);

    // Send profile update (a bit racy if connection isn't ready, but loop handles queue in robust apps)
    // For MVP, we hope the connect happens fast enough or we delay slightly
    Future.delayed(const Duration(seconds: 1), () {
        gameProvider.updateProfile(
            _bioController.text,
            _selectedTags,
            // ignore: deprecated_member_use
            _petColor.value.toString()
        );
    });

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text("Customize your Avatar", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            PetWidget(size: 150, color: _petColor), // Need to update PetWidget to accept color
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Colors.grey, Colors.blue, Colors.pink, Colors.green, Colors.orange].map((color) {
                return GestureDetector(
                  onTap: () => setState(() => _petColor = color),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(width: 2, color: Colors.white)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: "Bio",
                border: OutlineInputBorder(),
                hintText: "Tell us a bit about yourself...",
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            Text("Interests", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: _availableTags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(tag);
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _finishSetup,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text("Complete Profile"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

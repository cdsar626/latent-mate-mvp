import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/pet_widget.dart';
import '../services/auth_service.dart';

/// Allows the user to view and edit their own profile
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  Color _selectedColor = Colors.blue;
  bool _isSaving = false;

  final List<Color> _colorOptions = [
    Colors.blue, Colors.red, Colors.green, Colors.orange,
    Colors.purple, Colors.teal, Colors.pink, Colors.amber,
  ];

  @override
  Widget build(BuildContext context) {
    final gp = Provider.of<GameProvider>(context);
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: Text("Edit Profile", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar preview
            PetWidget(size: 80, color: _selectedColor)
                .animate()
                .scale(duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 12),
            Text(
              gp.currentUser?.username ?? authService.currentUsername ?? "User",
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              authService.currentUserEmail ?? "",
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Color picker
            Text("Avatar Color", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: _colorOptions.map((color) {
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _selectedColor == color
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Bio
            TextField(
              controller: _bioController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Bio",
                hintText: "Tell others about yourself...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 16),

            // Tags
            TextField(
              controller: _tagsController,
              decoration: InputDecoration(
                labelText: "Interests",
                hintText: "music, gaming, hiking...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 24),

            // Save
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : () {
                  setState(() => _isSaving = true);
                  final tags = _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
                  gp.updateProfile(
                    _bioController.text,
                    tags,
                    _selectedColor.value.toString(),
                  );
                  // Give it a moment, then pop back with a success message
                  Future.delayed(const Duration(milliseconds: 800), () {
                    if (mounted) {
                      setState(() => _isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Profile updated!")),
                      );
                      Navigator.of(context).pop();
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text("Save Profile", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ).animate().fadeIn(delay: 300.ms),

            if (gp.profileUpdated) ...[
              const SizedBox(height: 12),
              const Icon(Icons.check_circle, color: Colors.green),
            ],
          ],
        ),
      ),
    );
  }
}

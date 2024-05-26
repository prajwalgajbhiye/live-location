import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../consts.dart';

class AvtarContainer extends StatefulWidget {
  final Function(String) onAvatarSelected;

  const AvtarContainer({required this.onAvatarSelected, Key? key}) : super(key: key);

  @override
  _AvtarContainerState createState() => _AvtarContainerState();
}

class _AvtarContainerState extends State<AvtarContainer> {
  Future<void> _setAvatar(String imageUrl) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'avatarUrl': imageUrl,
      });
      await FirebaseFirestore.instance.collection('locations').doc(user.uid).update({
        'avatarUrl': imageUrl,
      });
      _saveAvatarToPreferences(imageUrl);
      widget.onAvatarSelected(imageUrl);
    }
  }

  Future<void> _saveAvatarToPreferences(String imageUrl) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatarUrl', imageUrl);
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(child: Image.asset(imageUrl)),
              const SizedBox(height: 10),
              const Text('Set image as avatar?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _setAvatar(imageUrl);
                Navigator.of(context).pop();
              },
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('No'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Example image URLs, replace with actual URLs

    return Container(
      padding: const EdgeInsets.all(2),
      height: 50,
      width: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Avtar(
              onTap: () => _showImageDialog(context, boy1),
              image: boy1,
            ),
            Avtar(
              onTap: () => _showImageDialog(context, boy2),
              image: boy2,
            ),
            Avtar(
              onTap: () => _showImageDialog(context, boy3),
              image: boy3,
            ),
            Avtar(
              onTap: () => _showImageDialog(context, girl2),
              image: girl2,
            ),
            Avtar(
              onTap: () => _showImageDialog(context, boy4),
              image: boy4,
            ),
            Avtar(
              onTap: () => _showImageDialog(context, boy1),
              image: boy1,
            ),
          ],
        ),
      ),
    );
  }
}

class Avtar extends StatelessWidget {
  final VoidCallback onTap;
  final String image;

  const Avtar({required this.onTap, required this.image, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Image.asset(image, width: 50, height: 50),
    );
  }
}

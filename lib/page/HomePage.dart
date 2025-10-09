import 'package:flutter/material.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Bienvenue sur la page d\'accueil !',
        style: TextStyle(fontSize: 24, color: Colors.white),
      ),
    );
  }
}

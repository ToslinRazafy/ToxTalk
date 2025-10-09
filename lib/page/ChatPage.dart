import 'package:flutter/material.dart';
import 'package:toxtalk/models/user.dart';

class ChatPage extends StatelessWidget {
  final User user;

  const ChatPage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${user.firstName} ${user.lastName}')),
      body: Center(child: Text('Chat avec ${user.firstName}')),
    );
  }
}

import 'package:flutter/material.dart';

class ActiveTeam {
  final String id;
  final String name;
  final String task;
  final Color color;
  final List<String> members;
  final DateTime createdAt;

  const ActiveTeam({
    required this.id,
    required this.name,
    required this.task,
    required this.color,
    required this.members,
    required this.createdAt,
  });
}
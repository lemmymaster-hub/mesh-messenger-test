import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'planner_engine.dart';

class PlannerStore {
  static const key = 'nrn.offlinePlanner.v1';

  Future<Json?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    return PlannerEngine.object(jsonDecode(raw));
  }

  Future<void> save(Json state) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, jsonEncode(state))) {
      throw StateError('Lokalno snimanje nije uspjelo.');
    }
  }
}

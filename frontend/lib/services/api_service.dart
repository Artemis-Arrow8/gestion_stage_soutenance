import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Adresse de votre API Django
  // Utilisez 'http://10.0.2.2:8000/api' si vous testez sur un émulateur Android
  // Utilisez 'http://127.0.0.1:8000/api' pour le Web ou Windows
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  // Exemple de méthode générique pour une requête GET sécurisée
  static Future<http.Response> get(String endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final url = Uri.parse('$baseUrl/$endpoint');
    return await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
  }

  // Exemple de méthode générique pour une requête POST
  static Future<http.Response> post(String endpoint, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final url = Uri.parse('$baseUrl/$endpoint');
    return await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(data),
    );
  }
}
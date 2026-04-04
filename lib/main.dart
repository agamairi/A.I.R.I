import 'package:flutter/material.dart';
import 'package:local_ai_chat/app.dart';
import 'package:local_ai_chat/core/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  runApp(AiriApp(services: services));
}

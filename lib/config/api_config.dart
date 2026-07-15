import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  ApiConfig._();

  static String get openAiApiKey => dotenv.maybeGet('OPENAI_API_KEY') ?? '';
}

class Environment {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ntuqdyhnzppntjqnsbcv.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im50dXFkeWhuenBwbnRqcW5zYmN2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNjE4NTIsImV4cCI6MjA5NDczNzg1Mn0.SyfNnQ4OhD33iaw51FJ5i2T-tlmDPZe-aYK0HS-5tEQ',
  );

  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
}

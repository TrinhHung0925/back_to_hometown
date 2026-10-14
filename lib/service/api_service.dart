class ApiService {
  static final ApiService shared = ApiService._internal();

  factory ApiService() => shared;

  ApiService._internal();
}

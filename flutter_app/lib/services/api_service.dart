import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../config/constants.dart';

class ApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    headers: {
      'Content-Type': 'application/json',
    },
  ));
  
  final Logger _logger = Logger();
  
  ApiService() {
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ));
  }
  
  Future<void> registerDevice(String fcmToken) async {
    try {
      await _dio.post('/devices', data: {
        'fcm_token': fcmToken,
        'platform': 'android',
      });
      _logger.i('Device registered successfully');
    } catch (e) {
      _logger.e('Failed to register device: $e');
    }
  }
  
  Future<Map<String, dynamic>?> getSipCredentials(String userId) async {
    try {
      final response = await _dio.get('/users/$userId/sip-credentials');
      return response.data;
    } catch (e) {
      _logger.e('Failed to get SIP credentials: $e');
      return null;
    }
  }
  
  Future<void> logCall({
    required String callId,
    required String from,
    required String to,
    required String status,
    required int duration,
  }) async {
    try {
      await _dio.post('/call-logs', data: {
        'call_id': callId,
        'from': from,
        'to': to,
        'status': status,
        'duration': duration,
      });
    } catch (e) {
      _logger.e('Failed to log call: $e');
    }
  }
}

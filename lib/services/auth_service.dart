import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import '../amplifyconfiguration.dart';

class AuthService {
  static Future<void> configure() async {
    if (!Amplify.isConfigured) {
      await Amplify.addPlugin(AmplifyAuthCognito());
      await Amplify.configure(amplifyconfig);
    }
  }

  static Future<bool> isSignedIn() async {
    final session = await Amplify.Auth.fetchAuthSession();
    return session.isSignedIn;
  }

  static Future<void> signUp(String email, String password) async {
    await Amplify.Auth.signUp(
      username: email,
      password: password,
      options: SignUpOptions(
        userAttributes: {AuthUserAttributeKey.email: email},
      ),
    );
  }

  static Future<bool> signIn(String email, String password) async {
    final res = await Amplify.Auth.signIn(username: email, password: password);
    if (res.isSignedIn) return true;

    final nextStep = res.nextStep.signInStep;
    if (nextStep == AuthSignInStep.confirmSignInWithNewPassword) {
      await Amplify.Auth.confirmSignIn(confirmationValue: password);
      return true;
    }
    return false;
  }

  static Future<void> signOut() async {
    await Amplify.Auth.signOut();
  }

  // Cognitoのsub（一意のユーザーID）を取得
  static Future<String?> getUserId() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      final cognitoSession = session as CognitoAuthSession;
      return cognitoSession.userSubResult.value;
    } catch (e) {
      print('getUserId エラー: $e');
      return null;
    }
  }
}

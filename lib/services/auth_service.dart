// ============================================================
// AuthService
// AWS Cognitoを使った認証機能を担当するサービスクラス。
//
// 担当する処理：
// ・Amplifyの初期化（configure）
// ・ログイン状態の確認（isSignedIn）
// ・新規登録（signUp）
// ・ログイン（signIn）
// ・ログアウト（signOut）
// ・ユーザーIDの取得（getUserId）
//
// Amplify Auth Cognitoを使用しており、
// ユーザー情報はAWS Cognitoのユーザープールで管理される。
// ユーザーIDはCognitoの「sub」（Subject）を使用する。
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import '../amplifyconfiguration.dart';

class AuthService {
  // ============================================================
  // 初期化
  // ============================================================

  /// Amplifyを初期化する
  ///
  /// main.dartの起動時に一度だけ呼ぶ。
  /// すでに設定済みの場合は何もしない（二重初期化を防ぐ）。
  static Future<void> configure() async {
    if (!Amplify.isConfigured) {
      await Amplify.addPlugin(AmplifyAuthCognito());
      await Amplify.configure(amplifyconfig);
    }
  }

  // ============================================================
  // ログイン状態確認
  // ============================================================

  /// 現在ログイン済みかどうかを確認する
  ///
  /// アプリ起動時にLoginScreen/HomeScreenの分岐に使用する。
  /// 返り値：ログイン済みならtrue、未ログインならfalse
  static Future<bool> isSignedIn() async {
    final session = await Amplify.Auth.fetchAuthSession();
    return session.isSignedIn;
  }

  // ============================================================
  // 新規登録
  // ============================================================

  /// メールアドレスとパスワードで新規登録する
  ///
  /// 登録後はCognitoからメール認証コードが送信される。
  /// 認証コードの確認はLoginScreenで行う。
  ///
  /// [email]    登録するメールアドレス
  /// [password] 登録するパスワード（Cognitoのポリシーに従う）
  static Future<void> signUp(String email, String password) async {
    await Amplify.Auth.signUp(
      username: email,
      password: password,
      options: SignUpOptions(
        // メールアドレスをCognitoのユーザー属性として登録
        userAttributes: {AuthUserAttributeKey.email: email},
      ),
    );
  }

  // ============================================================
  // ログイン
  // ============================================================

  /// メールアドレスとパスワードでログインする
  ///
  /// 通常のログインに加えて、管理者が仮パスワードを設定した場合の
  /// 「新しいパスワードの設定」フローにも対応している。
  ///
  /// [email]    ログインするメールアドレス
  /// [password] パスワード
  /// 返り値：ログイン成功ならtrue、失敗ならfalse
  static Future<bool> signIn(String email, String password) async {
    final res = await Amplify.Auth.signIn(username: email, password: password);

    // 通常のログイン成功
    if (res.isSignedIn) return true;

    // 管理者が仮パスワードを設定した場合の追加ステップ
    // 仮パスワードをそのまま新しいパスワードとして確定する
    final nextStep = res.nextStep.signInStep;
    if (nextStep == AuthSignInStep.confirmSignInWithNewPassword) {
      await Amplify.Auth.confirmSignIn(confirmationValue: password);
      return true;
    }

    return false;
  }

  // ============================================================
  // ログアウト
  // ============================================================

  /// ログアウトする
  ///
  /// Cognitoのセッションを破棄する。
  /// ログアウト後はLoginScreenに遷移する（呼び出し側で処理）。
  static Future<void> signOut() async {
    await Amplify.Auth.signOut();
  }

  // ============================================================
  // ユーザーID取得
  // ============================================================

  /// CognitoのユーザーID（sub）を取得する
  ///
  /// subはCognitoが発行する一意のUUID形式のユーザー識別子。
  /// DynamoDBのプライマリキー（userId）として使用している。
  ///
  /// 返り値：ユーザーID文字列、未ログインまたはエラーの場合はnull
  static Future<String?> getUserId() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();

      // CognitoAuthSessionにキャストしてsubを取得
      final cognitoSession = session as CognitoAuthSession;
      return cognitoSession.userSubResult.value;
    } catch (e) {
      // 未ログイン時はSignedOutExceptionがthrowされる
      debugPrint('getUserId エラー: $e');
      return null;
    }
  }
}

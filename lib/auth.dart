import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:phone_auth/general_utils.dart';
import 'package:phone_auth/google_sign_in_btn.dart';
import 'package:phone_auth/main_screen.dart';
import 'package:phone_auth/masked_text.dart';
import 'package:phone_auth/reactive_refresh_indicator.dart';

enum AuthStatus { SOCIAL_AUTH, PHONE_AUTH, SMS_AUTH, PROFILE_AUTH }

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const String TAG = "AUTH";
  AuthStatus status = AuthStatus.SOCIAL_AUTH;

  // Keys
  final GlobalKey<ReactiveRefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<ReactiveRefreshIndicatorState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<MaskedTextFieldState> _maskedPhoneKey =
      GlobalKey<MaskedTextFieldState>();

  // Controllers
  TextEditingController smsCodeController = TextEditingController();
  TextEditingController phoneNumberController = TextEditingController();

  // Variables
  String _errorMessage;
  String verificationId;
  Timer _codeTimer;

  bool _codeTimedOut = false;
  bool _isRefreshing = false;
  Duration _timeOut = const Duration(minutes: 1);

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  GoogleSignInAccount _googleUser;

  // PhoneVerificationCompleted
  verificationCompleted(FirebaseUser user) async {
    Utils.log(TAG, message: "onVerificationCompleted, user: $user");
    final result = await _onCodeVerified(user);
    if (result) {
      await _finishSignIn(user);
    } else {
      setState(() {
        this.status = AuthStatus.SMS_AUTH;
        Utils.log(TAG, message: "Changed status to $status");
      });
    }
  }

  // PhoneVerificationFailed
  verificationFailed(AuthException authException) {
    _updateRefreshing(false);
    Utils.log(TAG,
        message:
            'onVerificationFailed, code: ${authException.code}, message: ${authException.message}');
  }

  // PhoneCodeSent
  codeSent(String verificationId, [int forceResendingToken]) async {
    Utils.log(TAG,
        message:
            "Verification code sent to number ${phoneNumberController.text}");
    _codeTimer = Timer(_timeOut, () {
      setState(() {
        _codeTimedOut = true;
      });
    });
    _updateRefreshing(false);
    setState(() {
      this.verificationId = verificationId;
      this.status = AuthStatus.SMS_AUTH;
      Utils.log(TAG, message: "Changed status to $status");
    });
  }

  // PhoneCodeAutoRetrievalTimeout
  codeAutoRetrievalTimeout(String verificationId) {
    Utils.log(TAG, message: "onCodeTimeout");
    setState(() {
      this.verificationId = verificationId;
      this._codeTimedOut = true;
    });
  }

  // Styling

  final decorationStyle = TextStyle(
    color: Colors.grey[50],
    fontSize: 16.0,
    fontFamily: 'Overlock',
  );
  final hintStyle = TextStyle(
    color: Colors.white24,
    fontFamily: 'Overlock',
  );

  //

  @override
  void dispose() {
    _codeTimer?.cancel();
    super.dispose();
  }

  // async

  Future<Null> _updateRefreshing(bool isRefreshing) async {
    Utils.log(TAG,
        message: "Setting _isRefreshing ($_isRefreshing) to $isRefreshing");
    if (_isRefreshing) {
      setState(() {
        this._isRefreshing = false;
      });
    }
    setState(() {
      this._isRefreshing = isRefreshing;
    });
  }

  Future<Null> _signIn() async {
    GoogleSignInAccount user = _googleSignIn.currentUser;
    Utils.log(TAG, message: "Just got user as: $user");

    if (user == null) {
      user = await _googleSignIn.signIn();
    }

    if (user != null) {
      _updateRefreshing(false);
      this._googleUser = user;
      setState(() {
        this.status = AuthStatus.PHONE_AUTH;
        Utils.log(TAG, message: "Changed status to $status");
      });
      return null;
    }
    return null;
  }

  Future<Null> _submitPhoneNumber() async {
    final error = _phoneInputValidator();
    if (error != null) {
      setState(() {
        _errorMessage = error;
      });
      return null;
    } else {
      setState(() {
        _errorMessage = null;
      });
      final result = await _verifyPhoneNumber();
      Utils.log(TAG, message: "Returning $result from _submitPhoneNumber");
      return result;
    }
  }

  String get phoneNumber {
    String unmaskedText = _maskedPhoneKey.currentState.unmaskedText;
    String formatted = "+55$unmaskedText".trim();
    return formatted;
  }

  Future<Null> _verifyPhoneNumber() async {
    Utils.log(TAG, message: "Got phone number as: ${this.phoneNumber}");
    await _auth.verifyPhoneNumber(
        phoneNumber: this.phoneNumber,
        timeout: _timeOut,
        codeSent: codeSent,
        codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
        verificationCompleted: verificationCompleted,
        verificationFailed: verificationFailed);
    Utils.log(TAG, message: "Returning null from _verifyPhoneNumber");
    return null;
  }

  Future<Null> _submitSmsCode() async {
    final error = _smsInputValidator();
    if (error != null) {
      setState(() {
        _errorMessage = error;
      });
      return null;
    } else {
      setState(() {
        _errorMessage = null;
      });
      Utils.log(TAG, message: "signInWithPhoneNumber called");
      final user = await _auth.signInWithPhoneNumber(
          verificationId: verificationId, smsCode: smsCodeController.text);
      final result = await _onCodeVerified(user);
      Utils.log(TAG, message: "Returning $result from _onCodeVerified");
      return null;
    }
  }

  Future<bool> _onCodeVerified(FirebaseUser user) async {
    if (user != null) {
      setState(() {
        this.status = AuthStatus.PROFILE_AUTH;
        Utils.log(TAG, message: "Changed status to $status");
      });
      // Here, instead of _finishSignIn, you should do whatever you want
      // as the user is already verified with Firebase from both
      // Google and phone number methods
      // Example: authenticate with your API, use the data gathered
      // to post your profile/user, etc.
      await _finishSignIn(user);
      return true;
    } else {
      _scaffoldKey.currentState.showSnackBar(
        SnackBar(
          content: Text(
              "We couldn't create your profile for now, please try again with the button below!"),
        ),
      );
    }
    return false;
  }

  _finishSignIn(FirebaseUser user) async {
    Navigator.of(context).pushReplacement(CupertinoPageRoute(
          builder: (context) => MainScreen(
                googleUser: _googleUser,
                firebaseUser: user,
              ),
        ));
  }

  // Widgets

  Widget _buildSocialLoginBody() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(height: 24.0),
          GoogleSignInButton(
            onPressed: () => _updateRefreshing(true),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmInputButton() {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(Icons.check),
      color: theme.accentColor,
      disabledColor: theme.buttonColor,
      onPressed: (this.status == AuthStatus.PROFILE_AUTH)
          ? null
          : () => _updateRefreshing(true),
    );
  }

  Widget _buildPhoneNumberInput() {
    return MaskedTextField(
      key: _maskedPhoneKey,
      mask: "(xx) xxxxx-xxxx",
      keyboardType: TextInputType.number,
      maskedTextFieldController: phoneNumberController,
      maxLength: 15,
      onSubmitted: (text) => _updateRefreshing(true),
      style: Theme.of(context).textTheme.subhead.copyWith(
            fontSize: 18.0,
            color: Colors.white,
            fontFamily: 'Overlock',
          ),
      inputDecoration: InputDecoration(
        isDense: false,
        enabled: this.status == AuthStatus.PHONE_AUTH,
        counterText: "",
        icon: const Icon(
          Icons.phone,
          color: Colors.white,
        ),
        labelText: "Phone",
        labelStyle: decorationStyle,
        hintText: "(99) 99999-9999",
        hintStyle: hintStyle,
        errorText: _errorMessage,
      ),
    );
  }

  Widget _buildPhoneAuthBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
          child: Text(
            "We'll send an SMS message to verify your identity, please enter your number right below!",
            style: decorationStyle,
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
          child: Flex(
            direction: Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(flex: 5, child: _buildPhoneNumberInput()),
              Flexible(flex: 1, child: _buildConfirmInputButton())
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmsCodeInput() {
    final enabled = this.status == AuthStatus.SMS_AUTH;
    return TextField(
      keyboardType: TextInputType.number,
      enabled: enabled,
      textAlign: TextAlign.center,
      controller: smsCodeController,
      maxLength: 6,
      onSubmitted: (text) => _updateRefreshing(true),
      style: Theme.of(context).textTheme.subhead.copyWith(
            fontSize: 32.0,
            color: enabled ? Colors.white : Theme.of(context).buttonColor,
            fontFamily: 'Overlock',
          ),
      decoration: InputDecoration(
        counterText: "",
        enabled: enabled,
        errorText: _errorMessage,
        hintText: "--- ---",
        hintStyle: hintStyle.copyWith(fontSize: 42.0),
      ),
    );
  }

  Widget _buildResendSmsWidget() {
    return InkWell(
      onTap: () async {
        if (_codeTimedOut) {
          await _verifyPhoneNumber();
        } else {
          _scaffoldKey.currentState.showSnackBar(
            SnackBar(
              content: Text(
                "You can't retry yet!",
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            text: "If your code does not arrive in 1 minute, touch",
            style: decorationStyle,
            children: <TextSpan>[
              TextSpan(
                text: " here",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmsAuthBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
          child: Text(
            "Verification code",
            style: decorationStyle,
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 64.0),
          child: Flex(
            direction: Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(flex: 5, child: _buildSmsCodeInput()),
              Flexible(flex: 2, child: _buildConfirmInputButton())
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: _buildResendSmsWidget(),
        )
      ],
    );
  }

  String _phoneInputValidator() {
    if (phoneNumberController.text.isEmpty) {
      return "Your phone number can't be empty!";
    } else if (phoneNumberController.text.length < 15) {
      return "This phone number is invalid!";
    }
    return null;
  }

  String _smsInputValidator() {
    if (smsCodeController.text.isEmpty) {
      return "Your verification code can't be empty!";
    } else if (smsCodeController.text.length < 6) {
      return "This verification code is invalid!";
    }
    return null;
  }

  Widget _buildBody() {
    Widget body;
    switch (status) {
      case AuthStatus.SOCIAL_AUTH:
        body = _buildSocialLoginBody();
        break;
      case AuthStatus.PHONE_AUTH:
        body = _buildPhoneAuthBody();
        break;
      case AuthStatus.SMS_AUTH:
      case AuthStatus.PROFILE_AUTH:
        body = _buildSmsAuthBody();
        break;
    }
    return body;
  }

  Future<Null> _onRefresh() async {
    switch (this.status) {
      case AuthStatus.SOCIAL_AUTH:
        return await _signIn();
        break;
      case AuthStatus.PHONE_AUTH:
        return await _submitPhoneNumber();
        break;
      case AuthStatus.SMS_AUTH:
        return await _submitSmsCode();
        break;
      case AuthStatus.PROFILE_AUTH:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(elevation: 0.0),
      backgroundColor: Theme.of(context).primaryColor,
      body: Container(
        child: ReactiveRefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _onRefresh,
          isRefreshing: _isRefreshing,
          child: Container(child: _buildBody()),
        ),
      ),
    );
  }
}
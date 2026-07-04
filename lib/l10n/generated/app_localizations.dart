import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Dreaming Polar'**
  String get appName;

  /// No description provided for @appSlogan.
  ///
  /// In en, this message translates to:
  /// **'Born to create'**
  String get appSlogan;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get passwordHint;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @noAccountRegister.
  ///
  /// In en, this message translates to:
  /// **'No account? Register'**
  String get noAccountRegister;

  /// No description provided for @loginErrorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password'**
  String get loginErrorInvalidCredentials;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join Dreaming Polar and start your data journey'**
  String get registerSubtitle;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @usernameHint.
  ///
  /// In en, this message translates to:
  /// **'Your username'**
  String get usernameHint;

  /// No description provided for @passwordMinHint.
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters'**
  String get passwordMinHint;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @confirmPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get confirmPasswordHint;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @registerErrorFillAll.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields'**
  String get registerErrorFillAll;

  /// No description provided for @registerErrorUsernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 2 characters'**
  String get registerErrorUsernameTooShort;

  /// No description provided for @registerErrorInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get registerErrorInvalidEmail;

  /// No description provided for @registerErrorPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get registerErrorPasswordTooShort;

  /// No description provided for @registerErrorPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get registerErrorPasswordMismatch;

  /// No description provided for @loginExpiredPleaseRelogin.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please log in again.'**
  String get loginExpiredPleaseRelogin;

  /// No description provided for @switchAccount.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get switchAccount;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @addOtherAccount.
  ///
  /// In en, this message translates to:
  /// **'Add another account'**
  String get addOtherAccount;

  /// No description provided for @maxAccountsSupported.
  ///
  /// In en, this message translates to:
  /// **'Supports switching between up to 3 accounts'**
  String get maxAccountsSupported;

  /// No description provided for @currentlyLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentlyLoggedIn;

  /// No description provided for @switchToThisAccount.
  ///
  /// In en, this message translates to:
  /// **'Switch to this account'**
  String get switchToThisAccount;

  /// No description provided for @statusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get statusLive;

  /// No description provided for @statusComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get statusComingSoon;

  /// No description provided for @statusStayTuned.
  ///
  /// In en, this message translates to:
  /// **'Stay tuned'**
  String get statusStayTuned;

  /// No description provided for @appAriaAssistant.
  ///
  /// In en, this message translates to:
  /// **'ARIA Assistant'**
  String get appAriaAssistant;

  /// No description provided for @appDataGrid.
  ///
  /// In en, this message translates to:
  /// **'Data Grid'**
  String get appDataGrid;

  /// No description provided for @appVisualizationFactory.
  ///
  /// In en, this message translates to:
  /// **'Visualization Factory'**
  String get appVisualizationFactory;

  /// No description provided for @appMathModeling.
  ///
  /// In en, this message translates to:
  /// **'Math Modeling'**
  String get appMathModeling;

  /// No description provided for @appMoreComingSoon.
  ///
  /// In en, this message translates to:
  /// **'More coming soon'**
  String get appMoreComingSoon;

  /// No description provided for @comingSoonStayTuned.
  ///
  /// In en, this message translates to:
  /// **'Coming soon, stay tuned'**
  String get comingSoonStayTuned;

  /// No description provided for @recentTutorials.
  ///
  /// In en, this message translates to:
  /// **'Recent tutorials'**
  String get recentTutorials;

  /// No description provided for @greetingGoodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingGoodMorning;

  /// No description provided for @greetingGoodNoon.
  ///
  /// In en, this message translates to:
  /// **'Good midday'**
  String get greetingGoodNoon;

  /// No description provided for @greetingGoodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingGoodAfternoon;

  /// No description provided for @greetingGoodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingGoodEvening;

  /// No description provided for @greetingLateNight.
  ///
  /// In en, this message translates to:
  /// **'It\'s getting late'**
  String get greetingLateNight;

  /// No description provided for @greetingSubMorning.
  ///
  /// In en, this message translates to:
  /// **'A new day, take it easy.'**
  String get greetingSubMorning;

  /// No description provided for @greetingSubNoon.
  ///
  /// In en, this message translates to:
  /// **'Midday hours, take your time.'**
  String get greetingSubNoon;

  /// No description provided for @greetingSubAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, how are you doing?'**
  String get greetingSubAfternoon;

  /// No description provided for @greetingSubEvening.
  ///
  /// In en, this message translates to:
  /// **'A long day — well done.'**
  String get greetingSubEvening;

  /// No description provided for @greetingSubNight.
  ///
  /// In en, this message translates to:
  /// **'Get some rest soon.'**
  String get greetingSubNight;

  /// No description provided for @tagAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tagAll;

  /// No description provided for @tagDataAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Data Analysis'**
  String get tagDataAnalysis;

  /// No description provided for @tagMachineLearning.
  ///
  /// In en, this message translates to:
  /// **'Machine Learning'**
  String get tagMachineLearning;

  /// No description provided for @tagVisualization.
  ///
  /// In en, this message translates to:
  /// **'Visualization'**
  String get tagVisualization;

  /// No description provided for @tagStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get tagStatistics;

  /// No description provided for @tagMathModeling.
  ///
  /// In en, this message translates to:
  /// **'Math Modeling'**
  String get tagMathModeling;

  /// No description provided for @searchTutorialsHint.
  ///
  /// In en, this message translates to:
  /// **'Search tutorials, authors...'**
  String get searchTutorialsHint;

  /// No description provided for @noTutorialsYet.
  ///
  /// In en, this message translates to:
  /// **'No tutorials yet'**
  String get noTutorialsYet;

  /// No description provided for @loadFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {reason}'**
  String loadFailedWithReason(String reason);

  /// No description provided for @actionFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Action failed: {reason}'**
  String actionFailedWithReason(String reason);

  /// No description provided for @sendFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Failed to send: {reason}'**
  String sendFailedWithReason(String reason);

  /// No description provided for @uploadFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {reason}'**
  String uploadFailedWithReason(String reason);

  /// No description provided for @sendImageFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Failed to send image: {reason}'**
  String sendImageFailedWithReason(String reason);

  /// No description provided for @usernameNotUpdatedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Username not updated: {reason}'**
  String usernameNotUpdatedWithReason(String reason);

  /// No description provided for @chartRenderFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Failed to render chart: {error}'**
  String chartRenderFailedWithReason(String error);

  /// No description provided for @tutorial.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get tutorial;

  /// No description provided for @tutorialNotFound.
  ///
  /// In en, this message translates to:
  /// **'Tutorial not found'**
  String get tutorialNotFound;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @tapToChangeAvatar.
  ///
  /// In en, this message translates to:
  /// **'Tap to change avatar'**
  String get tapToChangeAvatar;

  /// No description provided for @nicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nicknameLabel;

  /// No description provided for @nicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Your nickname'**
  String get nicknameHint;

  /// No description provided for @usernameAtHint.
  ///
  /// In en, this message translates to:
  /// **'@Set your username'**
  String get usernameAtHint;

  /// No description provided for @genderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// No description provided for @genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// No description provided for @genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// No description provided for @genderPrivate.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get genderPrivate;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @locationHint.
  ///
  /// In en, this message translates to:
  /// **'City or region'**
  String get locationHint;

  /// No description provided for @birthdayLabel.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthdayLabel;

  /// No description provided for @selectBirthdayPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectBirthdayPlaceholder;

  /// No description provided for @addLink.
  ///
  /// In en, this message translates to:
  /// **'Add link'**
  String get addLink;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @nicknameRequired.
  ///
  /// In en, this message translates to:
  /// **'Nickname cannot be empty'**
  String get nicknameRequired;

  /// No description provided for @saveFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Save failed, please try again'**
  String get saveFailedRetry;

  /// No description provided for @avatarUpdated.
  ///
  /// In en, this message translates to:
  /// **'Avatar updated'**
  String get avatarUpdated;

  /// No description provided for @maxLinksReached.
  ///
  /// In en, this message translates to:
  /// **'You can add up to 3 links'**
  String get maxLinksReached;

  /// No description provided for @selectBirthdaySheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Select birthday'**
  String get selectBirthdaySheetTitle;

  /// No description provided for @bioLabel.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bioLabel;

  /// No description provided for @bioHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself'**
  String get bioHint;

  /// No description provided for @selectFromAlbum.
  ///
  /// In en, this message translates to:
  /// **'Choose from album'**
  String get selectFromAlbum;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @pleaseTryAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Please try again later'**
  String get pleaseTryAgainLater;

  /// No description provided for @zodiacAries.
  ///
  /// In en, this message translates to:
  /// **'Aries'**
  String get zodiacAries;

  /// No description provided for @zodiacTaurus.
  ///
  /// In en, this message translates to:
  /// **'Taurus'**
  String get zodiacTaurus;

  /// No description provided for @zodiacGemini.
  ///
  /// In en, this message translates to:
  /// **'Gemini'**
  String get zodiacGemini;

  /// No description provided for @zodiacCancer.
  ///
  /// In en, this message translates to:
  /// **'Cancer'**
  String get zodiacCancer;

  /// No description provided for @zodiacLeo.
  ///
  /// In en, this message translates to:
  /// **'Leo'**
  String get zodiacLeo;

  /// No description provided for @zodiacVirgo.
  ///
  /// In en, this message translates to:
  /// **'Virgo'**
  String get zodiacVirgo;

  /// No description provided for @zodiacLibra.
  ///
  /// In en, this message translates to:
  /// **'Libra'**
  String get zodiacLibra;

  /// No description provided for @zodiacScorpio.
  ///
  /// In en, this message translates to:
  /// **'Scorpio'**
  String get zodiacScorpio;

  /// No description provided for @zodiacSagittarius.
  ///
  /// In en, this message translates to:
  /// **'Sagittarius'**
  String get zodiacSagittarius;

  /// No description provided for @zodiacCapricorn.
  ///
  /// In en, this message translates to:
  /// **'Capricorn'**
  String get zodiacCapricorn;

  /// No description provided for @zodiacAquarius.
  ///
  /// In en, this message translates to:
  /// **'Aquarius'**
  String get zodiacAquarius;

  /// No description provided for @zodiacPisces.
  ///
  /// In en, this message translates to:
  /// **'Pisces'**
  String get zodiacPisces;

  /// No description provided for @coverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Cover updated'**
  String get coverUpdated;

  /// No description provided for @defaultGreetingMessage.
  ///
  /// In en, this message translates to:
  /// **'Hello!'**
  String get defaultGreetingMessage;

  /// No description provided for @cannotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this link'**
  String get cannotOpenLink;

  /// No description provided for @allSettings.
  ///
  /// In en, this message translates to:
  /// **'All settings'**
  String get allSettings;

  /// No description provided for @allSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Account security / Notifications / Theme / Membership, etc.'**
  String get allSettingsSubtitle;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// No description provided for @profileIsPrivate.
  ///
  /// In en, this message translates to:
  /// **'This user has set their profile to private'**
  String get profileIsPrivate;

  /// No description provided for @sendMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get sendMessageAction;

  /// No description provided for @followingAction.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get followingAction;

  /// No description provided for @followAction.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get followAction;

  /// No description provided for @followingCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get followingCountLabel;

  /// No description provided for @likesCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get likesCountLabel;

  /// No description provided for @followersCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followersCountLabel;

  /// No description provided for @creatorCenter.
  ///
  /// In en, this message translates to:
  /// **'Creator Center'**
  String get creatorCenter;

  /// No description provided for @creatorCenterComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Creator Center coming soon, stay tuned'**
  String get creatorCenterComingSoon;

  /// No description provided for @readCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get readCountLabel;

  /// No description provided for @bookmarksCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarksCountLabel;

  /// No description provided for @commentsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get commentsCountLabel;

  /// No description provided for @noTutorialsPublished.
  ///
  /// In en, this message translates to:
  /// **'No tutorials published yet'**
  String get noTutorialsPublished;

  /// No description provided for @noNotebooksYet.
  ///
  /// In en, this message translates to:
  /// **'No notebooks yet'**
  String get noNotebooksYet;

  /// No description provided for @bookmarksComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks coming soon'**
  String get bookmarksComingSoon;

  /// No description provided for @likesListComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Likes list coming soon'**
  String get likesListComingSoon;

  /// No description provided for @uploadFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Upload failed, please try again'**
  String get uploadFailedRetry;

  /// No description provided for @noFollowersYet.
  ///
  /// In en, this message translates to:
  /// **'No followers yet'**
  String get noFollowersYet;

  /// No description provided for @noFollowingYet.
  ///
  /// In en, this message translates to:
  /// **'Not following anyone yet'**
  String get noFollowingYet;

  /// No description provided for @messagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messagesTitle;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @tabNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get tabNotifications;

  /// No description provided for @tabDirectMessages.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get tabDirectMessages;

  /// No description provided for @tabGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get tabGroups;

  /// No description provided for @addFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get addFriend;

  /// No description provided for @addFriendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search users by @handle'**
  String get addFriendSubtitle;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get createGroup;

  /// No description provided for @createGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a discussion group'**
  String get createGroupSubtitle;

  /// No description provided for @createForum.
  ///
  /// In en, this message translates to:
  /// **'Create Forum'**
  String get createForum;

  /// No description provided for @createForumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a technical discussion forum'**
  String get createForumSubtitle;

  /// No description provided for @createGroupComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Group creation coming soon'**
  String get createGroupComingSoon;

  /// No description provided for @createForumComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Forum creation coming soon'**
  String get createForumComingSoon;

  /// No description provided for @searchUserHandleHint.
  ///
  /// In en, this message translates to:
  /// **'Enter @handle, without the @ symbol'**
  String get searchUserHandleHint;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchUserPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search a user\'s @handle'**
  String get searchUserPlaceholder;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @noNotificationsYet.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsYet;

  /// No description provided for @noDirectMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noDirectMessagesYet;

  /// No description provided for @goMeetNewFriends.
  ///
  /// In en, this message translates to:
  /// **'Go meet new friends in the community'**
  String get goMeetNewFriends;

  /// No description provided for @groupFeature.
  ///
  /// In en, this message translates to:
  /// **'Group feature'**
  String get groupFeature;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String timeMinutesAgo(int n);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String timeHoursAgo(int n);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String timeDaysAgo(int n);

  /// No description provided for @timeMonthsAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}mo ago'**
  String timeMonthsAgo(int n);

  /// No description provided for @systemNotificationInitial.
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get systemNotificationInitial;

  /// No description provided for @attachCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get attachCode;

  /// No description provided for @attachFormula.
  ///
  /// In en, this message translates to:
  /// **'Formula'**
  String get attachFormula;

  /// No description provided for @attachImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get attachImage;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get sendCode;

  /// No description provided for @codeInputHint.
  ///
  /// In en, this message translates to:
  /// **'# Enter code...'**
  String get codeInputHint;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendFormula.
  ///
  /// In en, this message translates to:
  /// **'Send Formula'**
  String get sendFormula;

  /// No description provided for @sendingImage.
  ///
  /// In en, this message translates to:
  /// **'Sending image...'**
  String get sendingImage;

  /// No description provided for @messageInputHint.
  ///
  /// In en, this message translates to:
  /// **'Message...'**
  String get messageInputHint;

  /// No description provided for @defaultUserName.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get defaultUserName;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @appNotebookTitle.
  ///
  /// In en, this message translates to:
  /// **'Dreaming Polar Notebook'**
  String get appNotebookTitle;

  /// No description provided for @newNotebook.
  ///
  /// In en, this message translates to:
  /// **'New Notebook'**
  String get newNotebook;

  /// No description provided for @chooseTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a type to start your analysis journey'**
  String get chooseTypeSubtitle;

  /// No description provided for @notebookNameHint.
  ///
  /// In en, this message translates to:
  /// **'Notebook name'**
  String get notebookNameHint;

  /// No description provided for @langMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get langMixed;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @whereToStart.
  ///
  /// In en, this message translates to:
  /// **'Where do you want to start?'**
  String get whereToStart;

  /// No description provided for @recentlyOpened.
  ///
  /// In en, this message translates to:
  /// **'Recently opened'**
  String get recentlyOpened;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get viewAll;

  /// No description provided for @templates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templates;

  /// No description provided for @templateMathDerivation.
  ///
  /// In en, this message translates to:
  /// **'Math Derivation'**
  String get templateMathDerivation;

  /// No description provided for @envInitializing.
  ///
  /// In en, this message translates to:
  /// **'Runtime environment initializing, please wait...'**
  String get envInitializing;

  /// No description provided for @pythonEnvLoading.
  ///
  /// In en, this message translates to:
  /// **'⏳ Python environment loading, please wait...'**
  String get pythonEnvLoading;

  /// No description provided for @loadTimeoutRestart.
  ///
  /// In en, this message translates to:
  /// **'❌ Loading timed out, please restart the app'**
  String get loadTimeoutRestart;

  /// No description provided for @langSupportComingSoon.
  ///
  /// In en, this message translates to:
  /// **'⏳ {lang} support coming soon'**
  String langSupportComingSoon(String lang);

  /// No description provided for @unsupportedCellType.
  ///
  /// In en, this message translates to:
  /// **'Running this cell type isn\'t supported yet'**
  String get unsupportedCellType;

  /// No description provided for @compilerNotReady.
  ///
  /// In en, this message translates to:
  /// **'Compiler not ready, please try again'**
  String get compilerNotReady;

  /// No description provided for @execTimeout.
  ///
  /// In en, this message translates to:
  /// **'Execution timed out'**
  String get execTimeout;

  /// No description provided for @runCompleteNoOutputChecked.
  ///
  /// In en, this message translates to:
  /// **'✓ Run complete (no output)'**
  String get runCompleteNoOutputChecked;

  /// No description provided for @runCompleteNoOutput.
  ///
  /// In en, this message translates to:
  /// **'Run complete (no output)'**
  String get runCompleteNoOutput;

  /// No description provided for @runErrorWithReason.
  ///
  /// In en, this message translates to:
  /// **'Run error: {error}'**
  String runErrorWithReason(String error);

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @inputPromptDefault.
  ///
  /// In en, this message translates to:
  /// **'Enter input'**
  String get inputPromptDefault;

  /// No description provided for @inputFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Input {n}'**
  String inputFieldLabel(int n);

  /// No description provided for @codeNeedsInput.
  ///
  /// In en, this message translates to:
  /// **'Code needs input'**
  String get codeNeedsInput;

  /// No description provided for @fillAllInputsFirst.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all input values first:'**
  String get fillAllInputsFirst;

  /// No description provided for @run.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get run;

  /// No description provided for @importJupyterNotebook.
  ///
  /// In en, this message translates to:
  /// **'Import Jupyter Notebook'**
  String get importJupyterNotebook;

  /// No description provided for @foundCellsImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Found {n} cells. Import them?'**
  String foundCellsImportConfirm(int n);

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @fileImportedTapToRun.
  ///
  /// In en, this message translates to:
  /// **'{filename} imported — tap Run to load the data'**
  String fileImportedTapToRun(String filename);

  /// No description provided for @exportedToPath.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String exportedToPath(String path);

  /// No description provided for @runAll.
  ///
  /// In en, this message translates to:
  /// **'Run All'**
  String get runAll;

  /// No description provided for @exportIpynb.
  ///
  /// In en, this message translates to:
  /// **'Export .ipynb'**
  String get exportIpynb;

  /// No description provided for @clearOutputs.
  ///
  /// In en, this message translates to:
  /// **'Clear Outputs'**
  String get clearOutputs;

  /// No description provided for @pythonCodeHint.
  ///
  /// In en, this message translates to:
  /// **'# Python code...'**
  String get pythonCodeHint;

  /// No description provided for @sqlQueryHint.
  ///
  /// In en, this message translates to:
  /// **'-- SQL query...'**
  String get sqlQueryHint;

  /// No description provided for @jsCodeHint.
  ///
  /// In en, this message translates to:
  /// **'// JavaScript code...'**
  String get jsCodeHint;

  /// No description provided for @rCodeHint.
  ///
  /// In en, this message translates to:
  /// **'# R code...'**
  String get rCodeHint;

  /// No description provided for @juliaCodeHint.
  ///
  /// In en, this message translates to:
  /// **'# Julia code...'**
  String get juliaCodeHint;

  /// No description provided for @latexFormulaHint.
  ///
  /// In en, this message translates to:
  /// **'Enter LaTeX formula...'**
  String get latexFormulaHint;

  /// No description provided for @markdownTextHint.
  ///
  /// In en, this message translates to:
  /// **'# Markdown text...'**
  String get markdownTextHint;

  /// No description provided for @htmlContentHint.
  ///
  /// In en, this message translates to:
  /// **'<p>HTML content...</p>'**
  String get htmlContentHint;

  /// No description provided for @genericCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Code...'**
  String get genericCodeHint;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get sectionAccount;

  /// No description provided for @accountSecurity.
  ///
  /// In en, this message translates to:
  /// **'Account Security'**
  String get accountSecurity;

  /// No description provided for @accountSecuritySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Password, login history'**
  String get accountSecuritySubtitle;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettings;

  /// No description provided for @notificationSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Likes, comments, follows'**
  String get notificationSettingsSubtitle;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Who can see my content'**
  String get privacySubtitle;

  /// No description provided for @sectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get sectionGeneral;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fontSizeStandard;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizeExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get fontSizeExtraLarge;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @cloudStorage.
  ///
  /// In en, this message translates to:
  /// **'Cloud Storage'**
  String get cloudStorage;

  /// No description provided for @storageUsedOfQuota.
  ///
  /// In en, this message translates to:
  /// **'Used {used} / {quota}'**
  String storageUsedOfQuota(String used, String quota);

  /// No description provided for @loadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingEllipsis;

  /// No description provided for @tapToViewDetails.
  ///
  /// In en, this message translates to:
  /// **'Tap to view details'**
  String get tapToViewDetails;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clearCache;

  /// No description provided for @sectionMembership.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get sectionMembership;

  /// No description provided for @myMembership.
  ///
  /// In en, this message translates to:
  /// **'My Membership'**
  String get myMembership;

  /// No description provided for @currentFreeVersion.
  ///
  /// In en, this message translates to:
  /// **'Current: Free'**
  String get currentFreeVersion;

  /// No description provided for @upgradePro.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get upgradePro;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethod;

  /// No description provided for @paymentMethodSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage linked payment methods'**
  String get paymentMethodSubtitle;

  /// No description provided for @subscriptionManagement.
  ///
  /// In en, this message translates to:
  /// **'Subscription Management'**
  String get subscriptionManagement;

  /// No description provided for @subscriptionManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View subscription history'**
  String get subscriptionManagementSubtitle;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About Dreaming Polar'**
  String get aboutApp;

  /// No description provided for @userAgreement.
  ///
  /// In en, this message translates to:
  /// **'User Agreement'**
  String get userAgreement;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get cacheCleared;

  /// No description provided for @likeNotifications.
  ///
  /// In en, this message translates to:
  /// **'Like Notifications'**
  String get likeNotifications;

  /// No description provided for @commentNotifications.
  ///
  /// In en, this message translates to:
  /// **'Comment Notifications'**
  String get commentNotifications;

  /// No description provided for @followNotifications.
  ///
  /// In en, this message translates to:
  /// **'Follow Notifications'**
  String get followNotifications;

  /// No description provided for @systemNotifications.
  ///
  /// In en, this message translates to:
  /// **'System Notifications'**
  String get systemNotifications;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @changePasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Change your password periodically to keep your account secure'**
  String get changePasswordSubtitle;

  /// No description provided for @loginHistory.
  ///
  /// In en, this message translates to:
  /// **'Login History'**
  String get loginHistory;

  /// No description provided for @loginHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View recent login devices and times'**
  String get loginHistorySubtitle;

  /// No description provided for @deleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all data'**
  String get deleteAccountSubtitle;

  /// No description provided for @fillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields'**
  String get fillAllFields;

  /// No description provided for @newPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The new passwords you entered don\'t match'**
  String get newPasswordMismatch;

  /// No description provided for @passwordChangeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get passwordChangeSuccess;

  /// No description provided for @changePasswordComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Password change is coming soon, stay tuned'**
  String get changePasswordComingSoon;

  /// No description provided for @changeFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Update failed, please try again'**
  String get changeFailedRetry;

  /// No description provided for @currentPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPasswordLabel;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPasswordLabel;

  /// No description provided for @confirmNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPasswordLabel;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'All your data will be permanently deleted, including tutorials, Notebooks, and messages.\\n\\nThis action cannot be undone.'**
  String get deleteAccountWarning;

  /// No description provided for @confirmDeletion.
  ///
  /// In en, this message translates to:
  /// **'Confirm Deletion'**
  String get confirmDeletion;

  /// No description provided for @deleteAccountComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Account deletion is coming soon, stay tuned'**
  String get deleteAccountComingSoon;

  /// No description provided for @deleteFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Deletion failed, please try again later'**
  String get deleteFailedRetry;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get accountDeleted;

  /// No description provided for @noLoginHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No login history yet'**
  String get noLoginHistoryYet;

  /// No description provided for @unknownLocation.
  ///
  /// In en, this message translates to:
  /// **'Unknown location'**
  String get unknownLocation;

  /// No description provided for @currentDeviceLabel.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentDeviceLabel;

  /// No description provided for @paymentMethodComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Payment method management is coming soon, stay tuned'**
  String get paymentMethodComingSoon;

  /// No description provided for @privacySettings.
  ///
  /// In en, this message translates to:
  /// **'Privacy Settings'**
  String get privacySettings;

  /// No description provided for @publicProfile.
  ///
  /// In en, this message translates to:
  /// **'Public Profile'**
  String get publicProfile;

  /// No description provided for @publicProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When off, only mutual followers can view your profile — other users will see \"This profile is private\"'**
  String get publicProfileSubtitle;

  /// No description provided for @publicFavorites.
  ///
  /// In en, this message translates to:
  /// **'Public Favorites List'**
  String get publicFavorites;

  /// No description provided for @publicFavoritesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow other users to see what you\'ve favorited'**
  String get publicFavoritesSubtitle;

  /// No description provided for @allowComments.
  ///
  /// In en, this message translates to:
  /// **'Allow Comments'**
  String get allowComments;

  /// No description provided for @allowCommentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When off, other users can\'t comment on your tutorials'**
  String get allowCommentsSubtitle;

  /// No description provided for @allowMessages.
  ///
  /// In en, this message translates to:
  /// **'Allow Direct Messages'**
  String get allowMessages;

  /// No description provided for @allowMessagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When off, other users can\'t send you direct messages'**
  String get allowMessagesSubtitle;

  /// No description provided for @storageSpace.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageSpace;

  /// No description provided for @membershipFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get membershipFree;

  /// No description provided for @remainingSpace.
  ///
  /// In en, this message translates to:
  /// **'{remaining} remaining'**
  String remainingSpace(String remaining);

  /// No description provided for @fileCategories.
  ///
  /// In en, this message translates to:
  /// **'File Categories'**
  String get fileCategories;

  /// No description provided for @folderNotebooks.
  ///
  /// In en, this message translates to:
  /// **'Notebook Files'**
  String get folderNotebooks;

  /// No description provided for @folderTutorials.
  ///
  /// In en, this message translates to:
  /// **'Tutorials / Notes'**
  String get folderTutorials;

  /// No description provided for @folderMedia.
  ///
  /// In en, this message translates to:
  /// **'Images / Videos / Audio'**
  String get folderMedia;

  /// No description provided for @folderDocs.
  ///
  /// In en, this message translates to:
  /// **'Documents / Data Files'**
  String get folderDocs;

  /// No description provided for @fileCountWithSize.
  ///
  /// In en, this message translates to:
  /// **'{count} files · {size}'**
  String fileCountWithSize(int count, String size);

  /// No description provided for @noFilesYet.
  ///
  /// In en, this message translates to:
  /// **'No files yet'**
  String get noFilesYet;

  /// No description provided for @unknownFile.
  ///
  /// In en, this message translates to:
  /// **'Unknown file'**
  String get unknownFile;

  /// No description provided for @desktopPlatformTag.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get desktopPlatformTag;

  /// No description provided for @filesCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String filesCountLabel(int count);

  /// No description provided for @clearCategory.
  ///
  /// In en, this message translates to:
  /// **'Clear category'**
  String get clearCategory;

  /// No description provided for @deleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete file'**
  String get deleteFile;

  /// No description provided for @confirmDeleteFileMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String confirmDeleteFileMessage(String name);

  /// No description provided for @willFreeSpace.
  ///
  /// In en, this message translates to:
  /// **'This will free up {size} of storage'**
  String willFreeSpace(String size);

  /// No description provided for @actionCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone'**
  String get actionCannotBeUndone;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @deletedFreedSpace.
  ///
  /// In en, this message translates to:
  /// **'Deleted, freed up {size}'**
  String deletedFreedSpace(String size);

  /// No description provided for @fileDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed'**
  String get fileDeleteFailed;

  /// No description provided for @fileDeleteFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Delete failed, please try again'**
  String get fileDeleteFailedRetry;

  /// No description provided for @confirmClearCategoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete all {count} files in this category?'**
  String confirmClearCategoryMessage(int count);

  /// No description provided for @deleteAllAction.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAllAction;

  /// No description provided for @deletedCountFreedSpace.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} files, freed up {size}'**
  String deletedCountFreedSpace(int count, String size);

  /// No description provided for @deleteTutorial.
  ///
  /// In en, this message translates to:
  /// **'Delete tutorial'**
  String get deleteTutorial;

  /// No description provided for @tutorialContentAndCommentsWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'The tutorial content and comments will be deleted too'**
  String get tutorialContentAndCommentsWillBeDeleted;

  /// No description provided for @tutorialDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" deleted'**
  String tutorialDeletedMessage(String name);

  /// No description provided for @proMembershipComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Pro membership coming soon, stay tuned'**
  String get proMembershipComingSoon;

  /// No description provided for @noSubscriptionHistory.
  ///
  /// In en, this message translates to:
  /// **'No subscription history yet'**
  String get noSubscriptionHistory;

  /// No description provided for @versionNumber.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionNumber;

  /// No description provided for @devTeam.
  ///
  /// In en, this message translates to:
  /// **'Development Team'**
  String get devTeam;

  /// No description provided for @officialWebsite.
  ///
  /// In en, this message translates to:
  /// **'Official Website'**
  String get officialWebsite;

  /// No description provided for @copyrightFooter.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Dreaming Polar\\nBorn to create'**
  String get copyrightFooter;

  /// No description provided for @storageFull.
  ///
  /// In en, this message translates to:
  /// **'Storage Full'**
  String get storageFull;

  /// No description provided for @storageFullMessage.
  ///
  /// In en, this message translates to:
  /// **'Used {used} / {quota}.\\n\\nUpgrade your membership for more space, or clear old files before sending.'**
  String storageFullMessage(String used, String quota);

  /// No description provided for @manageStorage.
  ///
  /// In en, this message translates to:
  /// **'Manage Storage'**
  String get manageStorage;

  /// No description provided for @upgradeMembership.
  ///
  /// In en, this message translates to:
  /// **'Upgrade Membership'**
  String get upgradeMembership;

  /// No description provided for @storageUsedPercentWarning.
  ///
  /// In en, this message translates to:
  /// **'Storage is {pct}% full — manage your files in Settings'**
  String storageUsedPercentWarning(int pct);

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get navCommunity;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @pageUnderDevelopment.
  ///
  /// In en, this message translates to:
  /// **'{page} page is under development'**
  String pageUnderDevelopment(String page);

  /// No description provided for @networkTimeout.
  ///
  /// In en, this message translates to:
  /// **'Network connection timed out'**
  String get networkTimeout;

  /// No description provided for @networkConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Network connection failed'**
  String get networkConnectionFailed;

  /// No description provided for @requestFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get requestFailed;

  /// No description provided for @registerFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Registration failed, please try again'**
  String get registerFailedRetry;

  /// No description provided for @registerSuccessAutoLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration succeeded, but automatic login failed — please log in manually'**
  String get registerSuccessAutoLoginFailed;

  /// No description provided for @latexFormulaExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. \\\\frac｛1｝｛2｝'**
  String get latexFormulaExample;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

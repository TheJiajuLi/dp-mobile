// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Dreaming Polar';

  @override
  String get appSlogan => 'Born to create';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordHint => 'Enter your password';

  @override
  String get login => 'Log in';

  @override
  String get noAccountRegister => 'No account? Register';

  @override
  String get loginErrorInvalidCredentials => 'Incorrect email or password';

  @override
  String get createAccount => 'Create account';

  @override
  String get registerSubtitle =>
      'Join Dreaming Polar and start your data journey';

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameHint => 'Your username';

  @override
  String get passwordMinHint => 'At least 6 characters';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get confirmPasswordHint => 'Re-enter your password';

  @override
  String get register => 'Register';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get registerErrorFillAll => 'Please fill in all fields';

  @override
  String get registerErrorUsernameTooShort =>
      'Username must be at least 2 characters';

  @override
  String get registerErrorInvalidEmail => 'Please enter a valid email';

  @override
  String get registerErrorPasswordTooShort =>
      'Password must be at least 6 characters';

  @override
  String get registerErrorPasswordMismatch => 'Passwords do not match';

  @override
  String get loginExpiredPleaseRelogin =>
      'Your session has expired. Please log in again.';

  @override
  String get switchAccount => 'Switch account';

  @override
  String get manage => 'Manage';

  @override
  String get done => 'Done';

  @override
  String get addOtherAccount => 'Add another account';

  @override
  String get maxAccountsSupported =>
      'Supports switching between up to 3 accounts';

  @override
  String get currentlyLoggedIn => 'Current';

  @override
  String get switchToThisAccount => 'Switch to this account';

  @override
  String get statusLive => 'Live';

  @override
  String get statusComingSoon => 'Coming soon';

  @override
  String get statusStayTuned => 'Stay tuned';

  @override
  String get appAriaAssistant => 'ARIA Assistant';

  @override
  String get appDataGrid => 'Data Grid';

  @override
  String get appVisualizationFactory => 'Visualization Factory';

  @override
  String get appMathModeling => 'Math Modeling';

  @override
  String get appMoreComingSoon => 'More coming soon';

  @override
  String get comingSoonStayTuned => 'Coming soon, stay tuned';

  @override
  String get recentTutorials => 'Recent tutorials';

  @override
  String get greetingGoodMorning => 'Good morning';

  @override
  String get greetingGoodNoon => 'Good midday';

  @override
  String get greetingGoodAfternoon => 'Good afternoon';

  @override
  String get greetingGoodEvening => 'Good evening';

  @override
  String get greetingLateNight => 'It\'s getting late';

  @override
  String get greetingSubMorning => 'A new day, take it easy.';

  @override
  String get greetingSubNoon => 'Midday hours, take your time.';

  @override
  String get greetingSubAfternoon => 'Good afternoon, how are you doing?';

  @override
  String get greetingSubEvening => 'A long day — well done.';

  @override
  String get greetingSubNight => 'Get some rest soon.';

  @override
  String get tagAll => 'All';

  @override
  String get tagDataAnalysis => 'Data Analysis';

  @override
  String get tagMachineLearning => 'Machine Learning';

  @override
  String get tagVisualization => 'Visualization';

  @override
  String get tagStatistics => 'Statistics';

  @override
  String get tagMathModeling => 'Math Modeling';

  @override
  String get searchTutorialsHint => 'Search tutorials, authors...';

  @override
  String get noTutorialsYet => 'No tutorials yet';

  @override
  String loadFailedWithReason(String reason) {
    return 'Failed to load: $reason';
  }

  @override
  String actionFailedWithReason(String reason) {
    return 'Action failed: $reason';
  }

  @override
  String sendFailedWithReason(String reason) {
    return 'Failed to send: $reason';
  }

  @override
  String uploadFailedWithReason(String reason) {
    return 'Upload failed: $reason';
  }

  @override
  String sendImageFailedWithReason(String reason) {
    return 'Failed to send image: $reason';
  }

  @override
  String usernameNotUpdatedWithReason(String reason) {
    return 'Username not updated: $reason';
  }

  @override
  String chartRenderFailedWithReason(String error) {
    return 'Failed to render chart: $error';
  }

  @override
  String get tutorial => 'Tutorial';

  @override
  String get tutorialNotFound => 'Tutorial not found';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get tapToChangeAvatar => 'Tap to change avatar';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String get nicknameHint => 'Your nickname';

  @override
  String get usernameAtHint => '@Set your username';

  @override
  String get genderLabel => 'Gender';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderPrivate => 'Prefer not to say';

  @override
  String get locationLabel => 'Location';

  @override
  String get locationHint => 'City or region';

  @override
  String get birthdayLabel => 'Birthday';

  @override
  String get selectBirthdayPlaceholder => 'Select';

  @override
  String get addLink => 'Add link';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get nicknameRequired => 'Nickname cannot be empty';

  @override
  String get saveFailedRetry => 'Save failed, please try again';

  @override
  String get avatarUpdated => 'Avatar updated';

  @override
  String get maxLinksReached => 'You can add up to 3 links';

  @override
  String get selectBirthdaySheetTitle => 'Select birthday';

  @override
  String get bioLabel => 'Bio';

  @override
  String get bioHint => 'Tell us about yourself';

  @override
  String get selectFromAlbum => 'Choose from album';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get pleaseTryAgainLater => 'Please try again later';

  @override
  String get zodiacAries => 'Aries';

  @override
  String get zodiacTaurus => 'Taurus';

  @override
  String get zodiacGemini => 'Gemini';

  @override
  String get zodiacCancer => 'Cancer';

  @override
  String get zodiacLeo => 'Leo';

  @override
  String get zodiacVirgo => 'Virgo';

  @override
  String get zodiacLibra => 'Libra';

  @override
  String get zodiacScorpio => 'Scorpio';

  @override
  String get zodiacSagittarius => 'Sagittarius';

  @override
  String get zodiacCapricorn => 'Capricorn';

  @override
  String get zodiacAquarius => 'Aquarius';

  @override
  String get zodiacPisces => 'Pisces';

  @override
  String get coverUpdated => 'Cover updated';

  @override
  String get defaultGreetingMessage => 'Hello!';

  @override
  String get cannotOpenLink => 'Couldn\'t open this link';

  @override
  String get allSettings => 'All settings';

  @override
  String get allSettingsSubtitle =>
      'Account security / Notifications / Theme / Membership, etc.';

  @override
  String get logout => 'Log out';

  @override
  String get userNotFound => 'User not found';

  @override
  String get profileIsPrivate => 'This user has set their profile to private';

  @override
  String get profileIsPrivateSubtitle =>
      'Published content and favorites aren\'t visible';

  @override
  String get sendMessageAction => 'Message';

  @override
  String get followingAction => 'Following';

  @override
  String get followAction => 'Follow';

  @override
  String get followingCountLabel => 'Following';

  @override
  String get likesCountLabel => 'Likes';

  @override
  String get followersCountLabel => 'Followers';

  @override
  String get creatorCenter => 'Creator Center';

  @override
  String get creatorCenterComingSoon =>
      'Creator Center coming soon, stay tuned';

  @override
  String get readCountLabel => 'Views';

  @override
  String get bookmarksCountLabel => 'Bookmarks';

  @override
  String get commentsCountLabel => 'Comments';

  @override
  String get noTutorialsPublished => 'No tutorials published yet';

  @override
  String get noNotebooksYet => 'No notebooks yet';

  @override
  String get bookmarksComingSoon => 'Bookmarks coming soon';

  @override
  String get likesListComingSoon => 'Likes list coming soon';

  @override
  String get uploadFailedRetry => 'Upload failed, please try again';

  @override
  String get noFollowersYet => 'No followers yet';

  @override
  String get noFollowingYet => 'Not following anyone yet';

  @override
  String get messagesTitle => 'Messages';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get tabNotifications => 'Notifications';

  @override
  String get tabDirectMessages => 'Chats';

  @override
  String get tabGroups => 'Groups';

  @override
  String get addFriend => 'Add Friend';

  @override
  String get addFriendSubtitle => 'Search users by @handle';

  @override
  String get createGroup => 'Create Group';

  @override
  String get createGroupSubtitle => 'Create a discussion group';

  @override
  String get createForum => 'Create Forum';

  @override
  String get createForumSubtitle => 'Create a technical discussion forum';

  @override
  String get createGroupComingSoon => 'Group creation coming soon';

  @override
  String get createForumComingSoon => 'Forum creation coming soon';

  @override
  String get searchUserHandleHint => 'Enter @handle, without the @ symbol';

  @override
  String get search => 'Search';

  @override
  String get searchUserPlaceholder => 'Search a user\'s @handle';

  @override
  String get view => 'View';

  @override
  String get noNotificationsYet => 'No notifications yet';

  @override
  String get noDirectMessagesYet => 'No messages yet';

  @override
  String get goMeetNewFriends => 'Go meet new friends in the community';

  @override
  String get groupFeature => 'Group feature';

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(int n) {
    return '${n}m ago';
  }

  @override
  String timeHoursAgo(int n) {
    return '${n}h ago';
  }

  @override
  String timeDaysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String timeMonthsAgo(int n) {
    return '${n}mo ago';
  }

  @override
  String get systemNotificationInitial => 'S';

  @override
  String get attachCode => 'Code';

  @override
  String get attachFormula => 'Formula';

  @override
  String get attachImage => 'Image';

  @override
  String get sendCode => 'Send Code';

  @override
  String get codeInputHint => '# Enter code...';

  @override
  String get send => 'Send';

  @override
  String get sendFormula => 'Send Formula';

  @override
  String get sendingImage => 'Sending image...';

  @override
  String get messageInputHint => 'Message...';

  @override
  String get defaultUserName => 'User';

  @override
  String get back => 'Back';

  @override
  String get appNotebookTitle => 'Dreaming Polar Notebook';

  @override
  String get newNotebook => 'New Notebook';

  @override
  String get chooseTypeSubtitle =>
      'Choose a type to start your analysis journey';

  @override
  String get notebookNameHint => 'Notebook name';

  @override
  String get langMixed => 'Mixed';

  @override
  String get create => 'Create';

  @override
  String get whereToStart => 'Where do you want to start?';

  @override
  String get recentlyOpened => 'Recently opened';

  @override
  String get viewAll => 'All';

  @override
  String get templates => 'Templates';

  @override
  String get templateMathDerivation => 'Math Derivation';

  @override
  String get envInitializing =>
      'Runtime environment initializing, please wait...';

  @override
  String get pythonEnvLoading => '⏳ Python environment loading, please wait...';

  @override
  String get loadTimeoutRestart =>
      '❌ Loading timed out, please restart the app';

  @override
  String langSupportComingSoon(String lang) {
    return '⏳ $lang support coming soon';
  }

  @override
  String get unsupportedCellType =>
      'Running this cell type isn\'t supported yet';

  @override
  String get compilerNotReady => 'Compiler not ready, please try again';

  @override
  String get execTimeout => 'Execution timed out';

  @override
  String get runCompleteNoOutputChecked => '✓ Run complete (no output)';

  @override
  String get runCompleteNoOutput => 'Run complete (no output)';

  @override
  String runErrorWithReason(String error) {
    return 'Run error: $error';
  }

  @override
  String get unknownError => 'Unknown error';

  @override
  String get inputPromptDefault => 'Enter input';

  @override
  String inputFieldLabel(int n) {
    return 'Input $n';
  }

  @override
  String get codeNeedsInput => 'Code needs input';

  @override
  String get fillAllInputsFirst => 'Please fill in all input values first:';

  @override
  String get run => 'Run';

  @override
  String get importJupyterNotebook => 'Import Jupyter Notebook';

  @override
  String foundCellsImportConfirm(int n) {
    return 'Found $n cells. Import them?';
  }

  @override
  String get import => 'Import';

  @override
  String fileImportedTapToRun(String filename) {
    return '$filename imported — tap Run to load the data';
  }

  @override
  String exportedToPath(String path) {
    return 'Exported to $path';
  }

  @override
  String get runAll => 'Run All';

  @override
  String get exportIpynb => 'Export .ipynb';

  @override
  String get clearOutputs => 'Clear Outputs';

  @override
  String get pythonCodeHint => '# Python code...';

  @override
  String get sqlQueryHint => '-- SQL query...';

  @override
  String get jsCodeHint => '// JavaScript code...';

  @override
  String get rCodeHint => '# R code...';

  @override
  String get juliaCodeHint => '# Julia code...';

  @override
  String get latexFormulaHint => 'Enter LaTeX formula...';

  @override
  String get markdownTextHint => '# Markdown text...';

  @override
  String get htmlContentHint => '<p>HTML content...</p>';

  @override
  String get genericCodeHint => 'Code...';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionAccount => 'Account';

  @override
  String get accountSecurity => 'Account Security';

  @override
  String get accountSecuritySubtitle => 'Password, login history';

  @override
  String get notificationSettings => 'Notification Settings';

  @override
  String get notificationSettingsSubtitle => 'Likes, comments, follows';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacySubtitle => 'Who can see my content';

  @override
  String get sectionGeneral => 'General';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get fontSize => 'Font Size';

  @override
  String get fontSizeSmall => 'Small';

  @override
  String get fontSizeStandard => 'Standard';

  @override
  String get fontSizeLarge => 'Large';

  @override
  String get fontSizeExtraLarge => 'Extra Large';

  @override
  String get language => 'Language';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get cloudStorage => 'Cloud Storage';

  @override
  String storageUsedOfQuota(String used, String quota) {
    return 'Used $used / $quota';
  }

  @override
  String get loadingEllipsis => 'Loading...';

  @override
  String get tapToViewDetails => 'Tap to view details';

  @override
  String get clearCache => 'Clear Cache';

  @override
  String get sectionMembership => 'Membership';

  @override
  String get myMembership => 'My Membership';

  @override
  String get currentFreeVersion => 'Current: Free';

  @override
  String get upgradePro => 'Upgrade to Pro';

  @override
  String get paymentMethod => 'Payment Method';

  @override
  String get paymentMethodSubtitle => 'Manage linked payment methods';

  @override
  String get subscriptionManagement => 'Subscription Management';

  @override
  String get subscriptionManagementSubtitle => 'View subscription history';

  @override
  String get sectionAbout => 'About';

  @override
  String get aboutApp => 'About Dreaming Polar';

  @override
  String get userAgreement => 'User Agreement';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get cacheCleared => 'Cache cleared';

  @override
  String get confirmLogoutMessage => 'Are you sure you want to log out?';

  @override
  String get exit => 'Log Out';

  @override
  String get switchAccountConfirm =>
      'Log out of the current account and go to the login page?';

  @override
  String get confirm => 'Confirm';

  @override
  String get likeNotifications => 'Like Notifications';

  @override
  String get commentNotifications => 'Comment Notifications';

  @override
  String get followNotifications => 'Follow Notifications';

  @override
  String get systemNotifications => 'System Notifications';

  @override
  String get changePassword => 'Change Password';

  @override
  String get changePasswordSubtitle =>
      'Change your password periodically to keep your account secure';

  @override
  String get loginHistory => 'Login History';

  @override
  String get loginHistorySubtitle => 'View recent login devices and times';

  @override
  String get deleteAccountSubtitle =>
      'Permanently delete your account and all data';

  @override
  String get fillAllFields => 'Please fill in all fields';

  @override
  String get newPasswordMismatch =>
      'The new passwords you entered don\'t match';

  @override
  String get passwordChangeSuccess => 'Password changed successfully';

  @override
  String get changePasswordComingSoon =>
      'Password change is coming soon, stay tuned';

  @override
  String get changeFailedRetry => 'Update failed, please try again';

  @override
  String get currentPasswordLabel => 'Current Password';

  @override
  String get newPasswordLabel => 'New Password';

  @override
  String get confirmNewPasswordLabel => 'Confirm New Password';

  @override
  String get deleteAccountWarning =>
      'All your data will be permanently deleted, including tutorials, Notebooks, and messages.\\n\\nThis action cannot be undone.';

  @override
  String get confirmDeletion => 'Confirm Deletion';

  @override
  String get deleteAccountComingSoon =>
      'Account deletion is coming soon, stay tuned';

  @override
  String get deleteFailedRetry => 'Deletion failed, please try again later';

  @override
  String get accountDeleted => 'Account deleted';

  @override
  String get noLoginHistoryYet => 'No login history yet';

  @override
  String get unknownLocation => 'Unknown location';

  @override
  String get currentDeviceLabel => 'Current';

  @override
  String get paymentMethodComingSoon =>
      'Payment method management is coming soon, stay tuned';

  @override
  String get privacySettings => 'Privacy Settings';

  @override
  String get publicProfile => 'Public Profile';

  @override
  String get publicProfileSubtitle =>
      'When off, other users can\'t view your profile';

  @override
  String get publicFavorites => 'Public Favorites List';

  @override
  String get publicFavoritesSubtitle =>
      'Allow other users to see what you\'ve favorited';

  @override
  String get allowComments => 'Allow Comments';

  @override
  String get allowCommentsSubtitle =>
      'When off, other users can\'t comment on your tutorials';

  @override
  String get allowMessages => 'Allow Direct Messages';

  @override
  String get allowMessagesSubtitle =>
      'When off, other users can\'t send you direct messages';

  @override
  String get storageSpace => 'Storage';

  @override
  String get membershipFree => 'Free';

  @override
  String remainingSpace(String remaining) {
    return '$remaining remaining';
  }

  @override
  String get fileCategories => 'File Categories';

  @override
  String get folderNotebooks => 'Notebook Files';

  @override
  String get folderTutorials => 'Tutorials / Notes';

  @override
  String get folderMedia => 'Images / Videos / Audio';

  @override
  String get folderDocs => 'Documents / Data Files';

  @override
  String fileCountWithSize(int count, String size) {
    return '$count files · $size';
  }

  @override
  String get noFilesYet => 'No files yet';

  @override
  String get unknownFile => 'Unknown file';

  @override
  String get proMembershipComingSoon =>
      'Pro membership coming soon, stay tuned';

  @override
  String get noSubscriptionHistory => 'No subscription history yet';

  @override
  String get versionNumber => 'Version';

  @override
  String get devTeam => 'Development Team';

  @override
  String get officialWebsite => 'Official Website';

  @override
  String get copyrightFooter => '© 2026 Dreaming Polar\\nBorn to create';

  @override
  String get storageFull => 'Storage Full';

  @override
  String storageFullMessage(String used, String quota) {
    return 'Used $used / $quota.\\n\\nUpgrade your membership for more space, or clear old files before sending.';
  }

  @override
  String get manageStorage => 'Manage Storage';

  @override
  String get upgradeMembership => 'Upgrade Membership';

  @override
  String storageUsedPercentWarning(int pct) {
    return 'Storage is $pct% full — manage your files in Settings';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navCommunity => 'Community';

  @override
  String get navProfile => 'Profile';

  @override
  String get publish => 'Publish';

  @override
  String pageUnderDevelopment(String page) {
    return '$page page is under development';
  }

  @override
  String get networkTimeout => 'Network connection timed out';

  @override
  String get networkConnectionFailed => 'Network connection failed';

  @override
  String get requestFailed => 'Request failed';

  @override
  String get registerFailedRetry => 'Registration failed, please try again';

  @override
  String get registerSuccessAutoLoginFailed =>
      'Registration succeeded, but automatic login failed — please log in manually';

  @override
  String get latexFormulaExample => 'e.g. \\\\frac｛1｝｛2｝';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '极梦';

  @override
  String get appSlogan => '为创造而生';

  @override
  String get emailLabel => '邮箱';

  @override
  String get passwordLabel => '密码';

  @override
  String get passwordHint => '请输入密码';

  @override
  String get login => '登录';

  @override
  String get noAccountRegister => '还没有账号？注册';

  @override
  String get loginErrorInvalidCredentials => '邮箱或密码不正确';

  @override
  String get createAccount => '创建账号';

  @override
  String get registerSubtitle => '加入极梦，开启数据分析之旅';

  @override
  String get usernameLabel => '用户名';

  @override
  String get usernameHint => '你的用户名';

  @override
  String get passwordMinHint => '至少6位';

  @override
  String get confirmPasswordLabel => '确认密码';

  @override
  String get confirmPasswordHint => '再次输入密码';

  @override
  String get register => '注册';

  @override
  String get alreadyHaveAccount => '已有账号？';

  @override
  String get registerErrorFillAll => '请填写所有字段';

  @override
  String get registerErrorUsernameTooShort => '用户名至少2个字符';

  @override
  String get registerErrorInvalidEmail => '请输入正确的邮箱';

  @override
  String get registerErrorPasswordTooShort => '密码至少6位';

  @override
  String get registerErrorPasswordMismatch => '两次密码不一致';

  @override
  String get loginExpiredPleaseRelogin => '登录状态已过期，请重新登录';

  @override
  String get switchAccount => '切换账号';

  @override
  String get manage => '管理';

  @override
  String get done => '完成';

  @override
  String get addOtherAccount => '添加其他账号';

  @override
  String get maxAccountsSupported => '支持至多3个账号切换';

  @override
  String get currentlyLoggedIn => '当前登录';

  @override
  String get switchToThisAccount => '切换到此账号';

  @override
  String get statusLive => '已上线';

  @override
  String get statusComingSoon => '即将上线';

  @override
  String get statusStayTuned => '敬请期待';

  @override
  String get appAriaAssistant => 'ARIA 分析助手';

  @override
  String get appDataGrid => '数据网格 Grid';

  @override
  String get appVisualizationFactory => '可视化工厂';

  @override
  String get appMathModeling => '数学建模';

  @override
  String get appMoreComingSoon => '更多敬请期待';

  @override
  String get comingSoonStayTuned => '即将上线，敬请期待';

  @override
  String get recentTutorials => '最近教程';

  @override
  String get greetingGoodMorning => '早上好';

  @override
  String get greetingGoodNoon => '中午好';

  @override
  String get greetingGoodAfternoon => '下午好';

  @override
  String get greetingGoodEvening => '晚上好';

  @override
  String get greetingLateNight => '夜深了';

  @override
  String get greetingSubMorning => '新的一天，从容开始。';

  @override
  String get greetingSubNoon => '午后时光，慢慢来。';

  @override
  String get greetingSubAfternoon => '下午好，状态怎么样？';

  @override
  String get greetingSubEvening => '忙了一天，辛苦了。';

  @override
  String get greetingSubNight => '早点睡吧。';

  @override
  String get tagAll => '全部';

  @override
  String get tagDataAnalysis => '数据分析';

  @override
  String get tagMachineLearning => '机器学习';

  @override
  String get tagVisualization => '可视化';

  @override
  String get tagStatistics => '统计学';

  @override
  String get tagMathModeling => '数学建模';

  @override
  String get searchTutorialsHint => '搜索教程、作者...';

  @override
  String get noTutorialsYet => '暂无教程';

  @override
  String loadFailedWithReason(String reason) {
    return '加载失败：$reason';
  }

  @override
  String actionFailedWithReason(String reason) {
    return '操作失败：$reason';
  }

  @override
  String sendFailedWithReason(String reason) {
    return '发送失败：$reason';
  }

  @override
  String uploadFailedWithReason(String reason) {
    return '上传失败：$reason';
  }

  @override
  String sendImageFailedWithReason(String reason) {
    return '发图失败：$reason';
  }

  @override
  String usernameNotUpdatedWithReason(String reason) {
    return '用户名未更新：$reason';
  }

  @override
  String chartRenderFailedWithReason(String error) {
    return '图表渲染失败：$error';
  }

  @override
  String get tutorial => '教程';

  @override
  String get tutorialNotFound => '教程不存在';

  @override
  String get editProfile => '编辑资料';

  @override
  String get save => '保存';

  @override
  String get cancel => '取消';

  @override
  String get tapToChangeAvatar => '点击更换头像';

  @override
  String get nicknameLabel => '昵称';

  @override
  String get nicknameHint => '你的昵称';

  @override
  String get usernameAtHint => '@设置你的用户名';

  @override
  String get genderLabel => '性别';

  @override
  String get genderMale => '男';

  @override
  String get genderFemale => '女';

  @override
  String get genderPrivate => '保密';

  @override
  String get locationLabel => '所在地';

  @override
  String get locationHint => '城市或地区';

  @override
  String get birthdayLabel => '生日';

  @override
  String get selectBirthdayPlaceholder => '请选择';

  @override
  String get addLink => '添加链接';

  @override
  String get deleteAccount => '注销账号';

  @override
  String get nicknameRequired => '昵称不能为空';

  @override
  String get saveFailedRetry => '保存失败，请重试';

  @override
  String get avatarUpdated => '头像已更新';

  @override
  String get maxLinksReached => '最多添加3条链接';

  @override
  String get selectBirthdaySheetTitle => '选择生日';

  @override
  String get bioLabel => '简介';

  @override
  String get bioHint => '介绍一下自己';

  @override
  String get selectFromAlbum => '从相册选择';

  @override
  String get takePhoto => '拍照';

  @override
  String get pleaseTryAgainLater => '请稍后再试';

  @override
  String get zodiacAries => '白羊座';

  @override
  String get zodiacTaurus => '金牛座';

  @override
  String get zodiacGemini => '双子座';

  @override
  String get zodiacCancer => '巨蟹座';

  @override
  String get zodiacLeo => '狮子座';

  @override
  String get zodiacVirgo => '处女座';

  @override
  String get zodiacLibra => '天秤座';

  @override
  String get zodiacScorpio => '天蝎座';

  @override
  String get zodiacSagittarius => '射手座';

  @override
  String get zodiacCapricorn => '摩羯座';

  @override
  String get zodiacAquarius => '水瓶座';

  @override
  String get zodiacPisces => '双鱼座';

  @override
  String get coverUpdated => '背景已更新';

  @override
  String get defaultGreetingMessage => '你好！';

  @override
  String get cannotOpenLink => '无法打开该链接';

  @override
  String get allSettings => '全部设置';

  @override
  String get allSettingsSubtitle => '账号安全 / 通知 / 主题 / 会员中心等';

  @override
  String get logout => '退出登录';

  @override
  String get userNotFound => '用户不存在';

  @override
  String get profileIsPrivate => '该用户已设置主页不公开';

  @override
  String get sendMessageAction => '发消息';

  @override
  String get followingAction => '已关注';

  @override
  String get followAction => '关注';

  @override
  String get followingCountLabel => '关注';

  @override
  String get likesCountLabel => '获赞';

  @override
  String get followersCountLabel => '粉丝';

  @override
  String get creatorCenter => '创作者中心';

  @override
  String get creatorCenterComingSoon => '创作中心即将上线，敬请期待';

  @override
  String get readCountLabel => '阅读量';

  @override
  String get bookmarksCountLabel => '收藏数';

  @override
  String get commentsCountLabel => '评论数';

  @override
  String get noTutorialsPublished => '还没有发布的教程';

  @override
  String get noNotebooksYet => '还没有 Notebook';

  @override
  String get bookmarksComingSoon => '收藏功能即将上线';

  @override
  String get likesListComingSoon => '点赞列表即将上线';

  @override
  String get uploadFailedRetry => '上传失败，请重试';

  @override
  String get noFollowersYet => '暂无粉丝';

  @override
  String get noFollowingYet => '暂无关注';

  @override
  String get messagesTitle => '消息';

  @override
  String get markAllRead => '全部已读';

  @override
  String get tabNotifications => '通知';

  @override
  String get tabDirectMessages => '私信';

  @override
  String get tabGroups => '群组';

  @override
  String get addFriend => '添加好友';

  @override
  String get addFriendSubtitle => '通过 @handle 搜索用户';

  @override
  String get createGroup => '建群';

  @override
  String get createGroupSubtitle => '创建讨论群组';

  @override
  String get createForum => '建论坛';

  @override
  String get createForumSubtitle => '创建技术交流论坛';

  @override
  String get createGroupComingSoon => '建群功能即将上线';

  @override
  String get createForumComingSoon => '论坛功能即将上线';

  @override
  String get searchUserHandleHint => '输入 @handle，不含@符号';

  @override
  String get search => '搜索';

  @override
  String get searchUserPlaceholder => '搜索用户的 @handle';

  @override
  String get view => '查看';

  @override
  String get noNotificationsYet => '暂无通知';

  @override
  String get noDirectMessagesYet => '还没有私信';

  @override
  String get goMeetNewFriends => '去社区认识新朋友';

  @override
  String get groupFeature => '群组功能';

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(int n) {
    return '$n分钟前';
  }

  @override
  String timeHoursAgo(int n) {
    return '$n小时前';
  }

  @override
  String timeDaysAgo(int n) {
    return '$n天前';
  }

  @override
  String timeMonthsAgo(int n) {
    return '$n个月前';
  }

  @override
  String get systemNotificationInitial => '系';

  @override
  String get attachCode => '代码';

  @override
  String get attachFormula => '公式';

  @override
  String get attachImage => '图片';

  @override
  String get sendCode => '发送代码';

  @override
  String get codeInputHint => '# 输入代码...';

  @override
  String get send => '发送';

  @override
  String get sendFormula => '发送公式';

  @override
  String get sendingImage => '发送图片中...';

  @override
  String get messageInputHint => '发消息...';

  @override
  String get messageLimitTitle => '消息限制';

  @override
  String get messageLimitBody =>
      '你已向对方发送了一条消息。\n\n在对方回复之前，你暂时无法继续发送消息。\n\n互相关注后可不受此限制。';

  @override
  String get gotIt => '我知道了';

  @override
  String get followThisUser => '关注对方';

  @override
  String get waitingForReplyHint => '等待对方回复后可继续发消息';

  @override
  String get goFollow => '去关注';

  @override
  String get defaultUserName => '用户';

  @override
  String get back => '返回';

  @override
  String get appNotebookTitle => '极梦 Notebook';

  @override
  String get newNotebook => '新建 Notebook';

  @override
  String get chooseTypeSubtitle => '选择类型，开始你的分析之旅';

  @override
  String get notebookNameHint => 'Notebook 名称';

  @override
  String get langMixed => '混合';

  @override
  String get create => '创建';

  @override
  String get whereToStart => '从哪里开始？';

  @override
  String get recentlyOpened => '最近打开';

  @override
  String get viewAll => '全部';

  @override
  String get templates => '模板';

  @override
  String get templateMathDerivation => '数学推导';

  @override
  String get envInitializing => '运行环境初始化中，请稍候...';

  @override
  String get pythonEnvLoading => '⏳ Python环境加载中，请稍候...';

  @override
  String get loadTimeoutRestart => '❌ 加载超时，请重启App重试';

  @override
  String langSupportComingSoon(String lang) {
    return '⏳ $lang 支持即将上线';
  }

  @override
  String get unsupportedCellType => '暂不支持该类型的运行';

  @override
  String get compilerNotReady => 'compiler未就绪，请重试';

  @override
  String get execTimeout => '执行超时';

  @override
  String get runCompleteNoOutputChecked => '✓ 运行完成（无输出）';

  @override
  String get runCompleteNoOutput => '运行完成（无输出）';

  @override
  String runErrorWithReason(String error) {
    return '运行出错：$error';
  }

  @override
  String get unknownError => '未知错误';

  @override
  String get inputPromptDefault => '请输入';

  @override
  String inputFieldLabel(int n) {
    return '输入 $n';
  }

  @override
  String get codeNeedsInput => '代码需要输入';

  @override
  String get fillAllInputsFirst => '请提前填写所有输入值：';

  @override
  String get run => '运行';

  @override
  String get importJupyterNotebook => '导入 Jupyter Notebook';

  @override
  String foundCellsImportConfirm(int n) {
    return '发现 $n 个 cell，是否导入？';
  }

  @override
  String get import => '导入';

  @override
  String fileImportedTapToRun(String filename) {
    return '$filename 已导入，点击运行加载数据';
  }

  @override
  String exportedToPath(String path) {
    return '已导出到 $path';
  }

  @override
  String get runAll => '全部运行';

  @override
  String get exportIpynb => '导出 .ipynb';

  @override
  String get clearOutputs => '清空输出';

  @override
  String get pythonCodeHint => '# Python 代码...';

  @override
  String get sqlQueryHint => '-- SQL 查询...';

  @override
  String get jsCodeHint => '// JavaScript 代码...';

  @override
  String get rCodeHint => '# R 代码...';

  @override
  String get juliaCodeHint => '# Julia 代码...';

  @override
  String get latexFormulaHint => '输入 LaTeX 公式...';

  @override
  String get markdownTextHint => '# Markdown 文本...';

  @override
  String get htmlContentHint => '<p>HTML 内容...</p>';

  @override
  String get genericCodeHint => '代码...';

  @override
  String get settingsTitle => '设置';

  @override
  String get sectionAccount => '账号';

  @override
  String get accountSecurity => '账号安全';

  @override
  String get accountSecuritySubtitle => '密码、登录记录';

  @override
  String get notificationSettings => '通知设置';

  @override
  String get notificationSettingsSubtitle => '点赞、评论、关注';

  @override
  String get privacy => '隐私';

  @override
  String get privacySubtitle => '谁可以看我的内容';

  @override
  String get sectionGeneral => '通用';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get fontSize => '字体大小';

  @override
  String get fontSizeSmall => '小';

  @override
  String get fontSizeStandard => '标准';

  @override
  String get fontSizeLarge => '大';

  @override
  String get fontSizeExtraLarge => '超大';

  @override
  String get language => '语言';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get selectLanguage => '选择语言';

  @override
  String get cloudStorage => '云端存储';

  @override
  String storageUsedOfQuota(String used, String quota) {
    return '已用 $used / $quota';
  }

  @override
  String get loadingEllipsis => '加载中...';

  @override
  String get tapToViewDetails => '点击查看详情';

  @override
  String get clearCache => '清除缓存';

  @override
  String get sectionMembership => '会员中心';

  @override
  String get myMembership => '我的会员';

  @override
  String get currentFreeVersion => '当前：免费版';

  @override
  String get upgradePro => '升级 Pro';

  @override
  String get paymentMethod => '支付方式';

  @override
  String get paymentMethodSubtitle => '管理绑定的支付方式';

  @override
  String get subscriptionManagement => '订阅管理';

  @override
  String get subscriptionManagementSubtitle => '查看订阅记录';

  @override
  String get sectionAbout => '关于';

  @override
  String get aboutApp => '关于极梦';

  @override
  String get userAgreement => '用户协议';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get cacheCleared => '缓存已清除';

  @override
  String get likeNotifications => '点赞通知';

  @override
  String get commentNotifications => '评论通知';

  @override
  String get followNotifications => '关注通知';

  @override
  String get systemNotifications => '系统通知';

  @override
  String get changePassword => '修改密码';

  @override
  String get changePasswordSubtitle => '定期更换密码保护账号安全';

  @override
  String get loginHistory => '登录记录';

  @override
  String get loginHistorySubtitle => '查看最近的登录设备和时间';

  @override
  String get deleteAccountSubtitle => '永久删除账号和所有数据';

  @override
  String get fillAllFields => '请填写完整';

  @override
  String get newPasswordMismatch => '两次输入的新密码不一致';

  @override
  String get passwordChangeSuccess => '密码修改成功';

  @override
  String get changePasswordComingSoon => '修改密码功能即将上线，敬请期待';

  @override
  String get changeFailedRetry => '修改失败，请重试';

  @override
  String get currentPasswordLabel => '当前密码';

  @override
  String get newPasswordLabel => '新密码';

  @override
  String get confirmNewPasswordLabel => '确认新密码';

  @override
  String get deleteAccountWarning =>
      '注销后所有数据将永久删除，包括教程、Notebook、消息记录。\\n\\n此操作不可撤销。';

  @override
  String get confirmDeletion => '确认注销';

  @override
  String get deleteAccountComingSoon => '注销账号功能即将上线，敬请期待';

  @override
  String get deleteFailedRetry => '注销失败，请稍后重试';

  @override
  String get accountDeleted => '账号已注销';

  @override
  String get noLoginHistoryYet => '暂无登录记录';

  @override
  String get unknownLocation => '未知位置';

  @override
  String get currentDeviceLabel => '当前';

  @override
  String get paymentMethodComingSoon => '支付方式管理即将上线，敬请期待';

  @override
  String get privacySettings => '隐私设置';

  @override
  String get publicProfile => '公开个人主页';

  @override
  String get publicProfileSubtitle => '关闭后仅互相关注的好友可查看你的主页，其他用户将看到「该主页已设为私密」';

  @override
  String get publicFavorites => '公开收藏列表';

  @override
  String get publicFavoritesSubtitle => '允许其他用户查看你收藏的内容';

  @override
  String get allowComments => '允许评论';

  @override
  String get allowCommentsSubtitle => '关闭后其他用户无法评论你的教程';

  @override
  String get allowMessages => '允许私信';

  @override
  String get allowMessagesSubtitle => '关闭后其他用户无法给你发私信';

  @override
  String get storageSpace => '存储空间';

  @override
  String get membershipFree => '免费版';

  @override
  String remainingSpace(String remaining) {
    return '剩余 $remaining';
  }

  @override
  String get fileCategories => '文件分类';

  @override
  String get folderNotebooks => 'Notebook 文件';

  @override
  String get folderTutorials => '教程 / 笔记';

  @override
  String get folderMedia => '图片 / 视频 / 音频';

  @override
  String get folderDocs => '文档 / 数据文件';

  @override
  String fileCountWithSize(int count, String size) {
    return '$count 个文件 · $size';
  }

  @override
  String get noFilesYet => '暂无文件';

  @override
  String get unknownFile => '未知文件';

  @override
  String get desktopPlatformTag => '桌面端';

  @override
  String filesCountLabel(int count) {
    return '$count个文件';
  }

  @override
  String get clearCategory => '清空此分类';

  @override
  String get deleteFile => '删除文件';

  @override
  String confirmDeleteFileMessage(String name) {
    return '确定删除「$name」？';
  }

  @override
  String willFreeSpace(String size) {
    return '将释放 $size 存储空间';
  }

  @override
  String get actionCannotBeUndone => '此操作不可恢复';

  @override
  String get deleteAction => '删除';

  @override
  String deletedFreedSpace(String size) {
    return '已删除，释放 $size 空间';
  }

  @override
  String get fileDeleteFailed => '删除失败';

  @override
  String get fileDeleteFailedRetry => '删除失败，请重试';

  @override
  String confirmClearCategoryMessage(int count) {
    return '确定删除该分类下的 $count 个文件？';
  }

  @override
  String get deleteAllAction => '全部删除';

  @override
  String deletedCountFreedSpace(int count, String size) {
    return '已删除 $count 个文件，释放 $size 空间';
  }

  @override
  String get deleteTutorial => '删除教程';

  @override
  String get tutorialContentAndCommentsWillBeDeleted => '教程内容、评论将一并删除';

  @override
  String tutorialDeletedMessage(String name) {
    return '「$name」已删除';
  }

  @override
  String get proMembershipComingSoon => 'Pro 会员即将上线，敬请期待';

  @override
  String get noSubscriptionHistory => '暂无订阅记录';

  @override
  String get versionNumber => '版本号';

  @override
  String get devTeam => '开发团队';

  @override
  String get officialWebsite => '官网';

  @override
  String get copyrightFooter => '© 2026 Dreaming Polar\\n极梦，为创造而生';

  @override
  String get storageFull => '存储空间已满';

  @override
  String storageFullMessage(String used, String quota) {
    return '已用 $used / $quota。\\n\\n请升级会员获取更多空间，或清理旧文件后再发送。';
  }

  @override
  String get manageStorage => '管理存储';

  @override
  String get upgradeMembership => '升级会员';

  @override
  String storageUsedPercentWarning(int pct) {
    return '存储空间已用 $pct%，可前往设置管理文件';
  }

  @override
  String get navHome => '首页';

  @override
  String get navCommunity => '社区';

  @override
  String get navProfile => '我的';

  @override
  String get publish => '发布';

  @override
  String pageUnderDevelopment(String page) {
    return '$page 页面开发中';
  }

  @override
  String get networkTimeout => '网络连接超时';

  @override
  String get networkConnectionFailed => '网络连接失败';

  @override
  String get requestFailed => '请求失败';

  @override
  String get registerFailedRetry => '注册失败，请重试';

  @override
  String get registerSuccessAutoLoginFailed => '注册成功，但自动登录失败，请手动登录';

  @override
  String get latexFormulaExample => '例：\\\\frac｛1｝｛2｝';
}

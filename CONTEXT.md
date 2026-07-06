# 极梦 Flutter 开发上下文

## 产品定位
极梦（Dreaming Polar）— 全领域知识内容社区
覆盖：科学 / 经济 / 时事 / 生活 / 数据 / 编程 / 宇宙 / 生命科学
定位：知乎的深度 + 小红书的轻量 + Nature的专业质感
Slogan：极梦，为创造而生
品牌色：#6366F1（紫蓝，只做点缀）
主色调：#1A1A1A（近黑）+ #FAFAF8（米白底）

## 设计语言（必读）
- 底色：#FAFAF8（米白，不是纯白）
- 主文字：#1A1A1A，次要：#999，辅助：#6366F1
- 无阴影，无渐变，用 0.5px #F0F0F0 细线分区
- 卡片：白色 #FFF，border-radius:14px，border:0.5px solid #F0F0F0
- 发布/主操作按钮：#1A1A1A 黑色，不用紫色
- 紫色 #6366F1 只用于：链接/角标/选中态点缀
- **例外：个人主页头图区**（2026-07-05 起，用户明确要求的深色玻璃拟态
  方向）：深色渐变 #2A1F3D→#1A2A3D（无封面图时）+ 黑色蒙层、iOS原生
  BackdropFilter 毛玻璃按钮（白色 12% 透明度背景）、领域 badge 用同一套
  配色但改成半透明彩色底+浅色字。这个方向只用在个人主页头图区，是刻意
  的局部例外，不代表整个 app 转向深色/渐变/毛玻璃——其余页面（发布页、
  设置页、教程详情页等）继续遵守上面的米白/无渐变/无阴影规范，不要因为
  看到这条例外就顺手把别的页面也套上玻璃拟态

### Badge 配色规则
数据科学 → bg:#EEF0FF color:#6366F1
生命科学 → bg:#E8F8F0 color:#16A34A
经济     → bg:#FFF7E6 color:#D97706
宇宙天文 → bg:#FDF0F8 color:#C026D3
编程     → bg:#E6F0FF color:#2563EB
时事     → bg:#F5F5F5 color:#555555

## iOS HIG 交互设计原则（必读，组件/交互层面，区别于上面的配色规范）
这些是从发布页、消息页、个人主页等模块的迭代里沉淀下来的交互层规则——上面
「设计语言」管的是颜色/卡片这些静态视觉，这里管的是"东西怎么弹出来、怎么
关掉、危险操作长什么样"这类交互层面，新写弹层/菜单/操作面板一律照此收敛，
不要每个页面各发明一套：

1. **原生风格浮层菜单（Context Menu）替代常驻图标行**：多个次要操作（复制/
   移动/折叠/删除）不平铺成一排常驻图标，收进一个「...」触发的 `showMenu`
   浮层——圆角14px、`PopupMenuDivider` 细分割线分组、图标在左文字在右、
   破坏性操作（删除）用 `#EF4444` 标红且和其它项之间加分割线隔开、背景纯
   白无强投影。只有高频操作（AI入口、拖拽手柄）才常驻，低频操作一律收进
   菜单（参考：`block_card.dart` 的 `_showMoreMenu`）
2. **模态操作用 Bottom Sheet，不用 Dialog**：`showModalBottomSheet` +
   `backgroundColor: Colors.transparent` + 自己套白色 `Container`
   （`borderRadius: vertical top 20`），标题上方留一条灰色小圆角拖拽条
   （36×4，暗示可下滑关闭）。`AlertDialog` 只用于真正需要"确认/取消"
   二选一阻断的场景（应用AI优化结果这种），不用来做菜单
3. **Safe Area 自己管，不整体套一层**：自定义顶栏/底栏各自用
   `SafeArea(top:false)` 或 `SafeArea(bottom:false)` 包住并铺满自己的
   背景色，不在 Scaffold 外层统一留白——否则页面背景色和顶/底栏背景色
   刀切不齐，会露出一圈灰色缝隙（chat_screen.dart/publish_screen.dart
   都踩过，见"踩过的坑"#18）
4. **毛玻璃（BackdropFilter blur）只用在刻意选定的深色语境**：个人主页
   头图区、侧边栏、底部导航——不是全局默认，米白主题的普通页面（发布页/
   设置页/教程详情页）不套毛玻璃
5. **拖拽热区精确绑定到手柄图标**：用 `ReorderableDragStartListener`
   只包裹一个 `drag_handle` 图标，不是让整行/整卡片可长按拖拽——不然会
   跟卡片内部的文字输入框/按钮抢手势
6. **一次性反馈用 SnackBar，不打断操作**：复制成功这类"知道一下就行"的
   反馈用 1~2 秒的 SnackBar，不用 Dialog 硬打断；需要用户做选择的才用
   Dialog/Bottom Sheet
7. **图标统一用线性/outline 风格，不用 emoji**：贴近 SF Symbols 的观感，
   之前把发布页/侧边栏里的 emoji 全部换成了 Material Icons 的 outlined
   变体（"提高档次"）
8. **渐进式披露（Progressive Disclosure）**：内容多/占地方的区块默认给
   最少信息，需要时才展开——block 折叠功能是这条原则的具体实现，折叠态
   只显示类型标签+"已折叠"提示+单行内容预览，且折叠只是编辑器内的临时
   视觉状态，不写进数据模型/不随发布内容持久化
9. **测试规范**：验证任何新交互，必须能在测试完成后用 `git diff` 证明
   反复横跳的临时测试代码（splash 跳转/postFrameCallback 钩子）已经
   完全撤回，零残留（见"踩过的坑"#18）

## 技术栈
- Flutter + Dart（目标：iOS App Store + Android）
- 状态管理：Riverpod（currentUserProvider 存登录用户）
- 路由：GoRouter
- 网络：ApiClient（封装 Dio，自动注入 Bearer token，不抛异常返回 ApiResponse）
- 本地存储：flutter_secure_storage + shared_preferences
- 图片：cached_network_image + flutter_svg
- LaTeX：flutter_math_fork
- WebView（Notebook运行Python）：flutter_inappwebview

## 后端 API
base: https://api.dreamingpolar.com

### 认证
POST /auth/login → {accessToken, username}
POST /auth/refresh → {accessToken, user}（走 HttpOnly Cookie dp_refresh）
POST /auth/register → {message:'注册成功'}，不返回token，需再调一次 /auth/login
GET /auth/me → {id,username,email,avatar,bio,website,handle,gender,location,birthday,zodiac,ip_location,follower_count,following_count,privacy_public_profile,privacy_public_favorites,privacy_allow_comments,privacy_allow_messages,created_at}
PATCH /auth/me → 更新 username/bio/website/gender/location/birthday/zodiac，birthday 传裸 "YYYY-MM-DD"（传完整ISO会 400）
PUT /auth/users/privacy → body驼峰bool(publicProfile等)，GET /auth/me 回的是 privacy_* 蛇形int，两边字段命名不对称
POST /auth/change-password → {oldPassword, newPassword}
DELETE /auth/account → 注销账号
403 "Token 无效或已过期" = token过期(可重试刷新)；401 "未携带 Access Token" = 根本没带token(不可重试)

### 教程
GET /auth/tutorials?status=published&author=xxx&page=1&limit=12
→ {tutorials:[{id,title,cover_image,summary,tags,likes,views,created_at,username,avatar,user_id}], total,page,pages}
POST /auth/tutorials → {title,summary,cover_image,tags(array),blocks(JSON string),status}
PUT /auth/tutorials/:id
DELETE /auth/tutorials/:id
POST /auth/tutorials/:id/like
DELETE /auth/tutorials/:id/like
GET /auth/tutorials/:id/comments
POST /auth/tutorials/:id/comments → {content}

### 用户
GET /auth/users/search?handle=xxx —— 目前是坏的，永远404，不要以为是客户端bug
GET /auth/users/profile/:identifier → {id,username,handle,avatar,bio,website,follower_count,following_count,tutorial_count}，不含gender/location/zodiac；对方设了主页不公开时返回403
GET /auth/users/:identifier（旧接口）/ GET /auth/users/:id/follow-status —— 不受主页不公开影响，作为兜底展示有限信息
POST /auth/users/:targetId/follow
DELETE /auth/users/:targetId/follow
GET /auth/users/:targetId/follow-status → {isFollowing}
GET /auth/users/:userId/followers
GET /auth/users/:userId/following

### 文件 / 存储
POST /auth/files/upload (multipart, field='file') → {id,filename,file_type,size_bytes,created_at,updated_at,cos_key,url}
  file_type 永远是 "other"——后端不区分图片/视频/音频，客户端只能靠文件名后缀猜
DELETE /auth/files/:id → {message:'文件已删除'}
GET /auth/storage/usage → {quota,membership,categories:{notebooks,tutorials,media,docs,other,avatars},totalBytes}
  每个分类 {files:[...], totalBytes}；tutorials 的file自带id+status，cos_key已是完整URL；
  media/docs/notebooks 的file没有id(靠cos_key末段UUID反推)，cos_key是相对路径，需拼COS前缀
  图片/视频/音频没有独立分类，全部合并在 media 里
POST /auth/update-avatar (multipart, field='avatar') → {avatar:'COS URL'}

### 消息（后端待建，目前用 mock 数据）
GET /auth/notifications
GET /auth/conversations
GET /auth/conversations/:id/messages
POST /auth/messages → {toUserId,content,type}

### ARIA
POST /api/chat
headers: Authorization: Bearer token
body: {messages:[{role,content}], dataframe_context:{varName,columns,rowCount,sampleRows}}

## Block 格式（教程/发布内容）
blocks 是 JSON 字符串：
[{id, type(text|code|latex|heading|image|callout|quote|video|audio|link), content, language, executable, level, variant, imageUrl, caption}]

## 路由结构
/splash        → 启动页（自动登录检查）
/login         → 登录页
/register      → 注册页
/switch-account → 切换账号
/home          → 首页（Feed）
/discover      → 发现页（专题+领域地图+创作者）
/publish       → 发布页（Block 编辑器）
/aria          → ARIA 分析助手
/messages      → 消息中心
/messages/chat/:conversationId → 聊天页
/profile       → 我的（个人主页）
/edit-profile  → 编辑资料
/settings      → 设置
/settings/security         → 账号安全
/settings/security/history → 登录历史
/settings/payment          → 支付方式
/settings/subscription     → 订阅/会员
/settings/privacy          → 隐私设置
/settings/storage          → 云端存储（用量+分类文件管理，封面/缩略图见下）
/settings/about            → 关于
/notebook      → Power Notebook 首页
/notebook/:id  → Notebook 编辑器
/users/:identifier       → 他人主页
/users/:userId/followers → 粉丝列表
/users/:userId/following → 关注列表
/tutorial/:id  → 教程详情页

## 底部导航（5个）
首页 / 发现 / +发布（黑色方块按钮）/ 消息 / 我的

## 已实现模块

### 首页
- Feed 三种卡片混排：大图头条 / 文字+缩略图 / 双列小卡
- 话题标签横滑筛选（全部/科学/经济/时事/生活/数据/编程）
- 下拉刷新 + 上拉加载更多

### 发现页（待实现）
三层结构：
1. 本周专题：编辑精选大卡 + 专题文章横滑
2. 领域地图：6宫格（数学物理/生命科学/经济金融/宇宙天文/编程数据/时事）
3. 发现创作者：横滑卡片，按领域推荐

### 社区
- 2列瀑布流，搜索栏+标签筛选（本地过滤）
- 下拉刷新+分页加载

### 发布页（Block编辑器，视觉语言已深化）
- 顶部：标题输入 + 草稿/发布按钮，SafeArea(bottom:false)+自己的白色背景，不留灰色安全区缝隙
- 元信息卡：封面图缩成小方块塞进摘要卡片，加入专栏（bottom sheet选专栏，真实数据，GET /auth/columns/mine——2026-07-06 实测确认这个接口已经好了，不是之前记的404/mock，创作者中心的"我的专栏"页也是同一个接口）+ 标题植入（bottom sheet实时预览），两个功能2列并排放
- 编辑已有内容（2026-07-06）：PublishScreen 现在支持传入 tutorialId 进入编辑模式（路由 /publish/:id）——initState 里 GET /auth/tutorials/:id 回填 title/summary/tags/cover/blocks（EditorBlock.fromJson，是 toJson 的反函数），保存时走 PUT 更新原记录而不是再 POST 一篇新的；同一次编辑会话里第一次保存成功后会记下后端返回的 id，后续再保存也走 PUT，不会重复创建
- Block 列表：统一白色圆角卡片风格，代码块做成 macOS 风格（三个圆点header+语言下拉+运行按钮），编辑器和阅读态共用同一套语法高亮（HighlightingCodeController）
- Block 头部操作（2026-07-06 收进「...」菜单）：上移/下移/复制/复制代码（仅代码块）/折叠/删除 不再常驻平铺图标，收进一个 iOS 原生风格的浮层菜单（圆角、细分割线、删除项标红），AI 入口和拖拽手柄因为用得最频繁仍然常驻。折叠是编辑器内的临时视觉状态，不写进 EditorBlock、不随发布内容持久化——重进编辑页永远是展开的，折叠态显示"已折叠"标签+单行内容预览
- 拖拽排序：ReorderableListView + buildDefaultDragHandles:false，只有drag_handle图标本身可拖（用ReorderableDragStartListener包裹），不是长按任意位置
- 底部横排工具栏，选中的block类型高亮
- 抽屉式预览（不是全屏），预览抽屉作者行加了收藏/分享图标
- 空白引导态：无block时显示"今天想写点什么？"问候语 + 6个快速开始按钮 + 轮播"今日灵感"卡片
- Block 类型：文字/代码/LaTeX/图片/引用/视频(Pro)/音频(Pro)/链接

### 创作者中心 + 极光创作者计划（2026-07-06）
入口：个人主页侧边栏「创作者中心」，`lib/features/creator/` 下四个页面：
- `creator_center_screen.dart`：整体跟随 ThemePreference（浅色白底/深色 `#0A0A1A`）。
  顶部浏览量/获赞/新粉丝三格数据是真实累计值（GET /auth/tutorials
  ?author=username&status=published 求和 + currentUserProvider.followerCount），
  涨幅百分比（↑23%等）后端没有历史快照算不出真实环比，写死 mock，不要当真
  数据看。作品管理/我的专栏两个快捷入口 + 常驻的 AuroraEntryCard（极光计划
  入口卡，固定深色星空底，不跟随主题）+ 草稿箱行（点开直接跳作品管理的
  草稿 tab，不是跳去空白发布页）
- `aurora_screen.dart`：极光计划详情页，固定深色背景 `#0A0812`（不跟随
  ThemePreference，跟个人主页头图区一样是刻意保留的局部深色例外）。除了
  "我的申请进度"卡用真实数据，其余（加入权益/流量分成制度/结算规则/续期
  条件/为什么选极梦/早期创作者）都是纯静态文案，没有对应的真实计算逻辑
- `works_screen.dart`：作品管理，已发布/草稿/下架三个 tab，每个 tab 各自
  查一次 `GET /auth/tutorials?author=username&status=X`（X=published/
  draft/deleted）。**"下架"不是调 DELETE 硬删**——tutorials.status 是
  MySQL ENUM('draft','published','deleted') 三个合法值，下架实际是 GET
  完整教程内容后 PUT 回去把 status 改成 'deleted'，内容和评论/点赞都还在，
  可以在"下架"tab里"恢复上架"（PUT 改回 published）；只有草稿的"删除"
  和下架内容的"彻底删除"才是真正调 DELETE /auth/tutorials/:id（这两种
  情况原本就没公开过或已经不公开，删掉没有社交层面的连带损失）。
  updateTutorial 是整份覆盖语义，不传 blocks/tags 会被清空成默认值，所以
  改 status 前必须先 GET 一次拿完整内容再原样传回去
- `columns_screen.dart`：我的专栏，真实数据 `GET /auth/columns/mine`，
  "新建专栏"真的调 `POST /auth/columns` 创建（不是占位 SnackBar）——这个
  接口本来就在用（publish_screen 的加入专栏功能同一个接口），没有理由
  在这里假装它不存在
- 与最初给的任务描述有出入的地方（都是往更安全/更真实的方向改，不是
  抄近路）：草稿箱本地存储实际上不存在，草稿是 POST /auth/tutorials 时
  status='draft' 存在后端，不是 SharedPreferences；GET /auth/tutorials
  的 author 参数实测已经在服务端正确过滤（2026-07-06 用一次性测试账号
  curl 验证），不再是"传了也无效"的状态，但 Flutter 侧沿用了原有的
  client-side 二次过滤当保险；WorksScreen 的"编辑"按钮需要 PublishScreen
  真的支持编辑已有内容才有意义，为此把 PublishScreen 从"只能新建"扩展成
  能编辑（见上面"发布页"一节的记录）

### Power Notebook
- 首页：最近打开（左滑删除）+ 模板 + 新建底部弹窗
- 编辑器：Cell列表（Python/R/LaTeX/Markdown/SQL）
- Python：隐藏WebView跑 Pyodide（dreamingpolar.com/components/compiler/compiler.js）
- LaTeX：flutter_math_fork 渲染
- 导入：file_picker（csv/xlsx/json/py/ipynb/tex/md）
- 持久化：SharedPreferences，key带userId前缀

### 个人主页（2026-07-05 深色玻璃拟态重设计）
- 头图区固定高度（屏幕50%-Tab栏42-底部导航83，clamp在280~520之间），
  不再是"内容撑多高算多高"——顶部毛玻璃按钮行（汉堡/返回 + 链接 + 更多，
  BackdropFilter blur+白色12%透明度背景）和底部用户信息块都是 Positioned
  绝对定位叠在封面上，互不影响
- 无封面图时的占位渐变：#2A1F3D→#1A2A3D 深色渐变（不是米白系）
- 头像+用户名一行 → 兴趣标签（2026-07-06起：编辑资料页里用户自己选的最多3个
  标签，`lib/core/constants/tag_colors.dart` + `InterestTag` widget 渲染，
  跟发布/首页用的 `shared/utils/topic_badge.dart` 是两套独立配色表——
  topic_badge.dart 服务白色卡片上的浅底实色badge，tag_colors.dart 专门服务
  这里的深色毛玻璃场景（真·BackdropFilter模糊+半透明彩色底+浅色字+同色
  描边），不是重复维护，视觉语境完全不同。不再是"从发布过的教程tags统计
  频率最高3个"那套自动推断了，后端 users.tags 字段已上线（GET/PATCH
  /auth/me、GET /auth/users/profile/:identifier 都支持）
  → bio单行 → 位置+星座+网站压成一行（性别、IP属地这两项为了省空间已经从
  这里拿掉，不再单独占一行）→ 统计+按钮一行
- 统计行是内联文字（"3 文章"这种数字+小字标签紧挨着排成一行，横向可滚动
  防溢出），显示的是文章/获赞/粉丝/关注这种社交数据，不是tab计数；编辑
  资料(32px白底黑字)+分享(毛玻璃)/私信+关注 两个按钮跟统计同一行右侧
- Tab栏是独立的白底 SliverPersistentHeader(pinned:true, 42px高)，不是
  嵌进头图区的一部分：文章/专栏/Notebook/收藏/点赞五个（专栏在文章和
  Notebook中间），5个tab要用更紧凑的字号(12px)+labelPadding，不然
  "Notebook"这种比中文标签长的单词会被裁切显示不全
- 文章/专栏等Tab：3列九宫格或列表（GridView.count 记得手动
  padding:EdgeInsets.zero，否则安全区自动padding撑出大缝隙）
- 左上角汉堡 → 抽屉用 showGeneralDialog 强推到根Navigator（不是
  Scaffold.drawer，那个盖不住MainShell的底部导航栏和状态栏安全区）
- 侧边栏：header 渐变同步成头图区那套 #2A1F3D→#1A2A3D 深色玻璃拟态
  （不再是原来偏亮的 #6366F1→#7C3AED），右上角加了个纯用径向渐变做的
  柔光装饰点缀；会员卡加了一圈低透明度紫色描边呼应；菜单列表/底部三
  按钮维持原来的浅色 Theme 背景，没有跟着一起变深色
- 状态栏图标用 AnnotatedRegion<SystemUiOverlayStyle>(value: .light) 强制
  白色，因为头图区总是深色；已知取舍：滚动很远头图完全滚出视口后状态栏
  区域会露出白色Tab栏背景，白图标短暂不好辨认，没做滚动监听动态切换

### 设置 · 云端存储
- 用量卡片（进度条+已用/总量/剩余）+ 4个可展开分类：Notebook/教程笔记/图片视频音频(media)/文档数据(docs)
- 教程：封面缩略图(CachedNetworkImage)+已发布/草稿状态徽标
- media分类内按文件名后缀客户端猜图片/视频/音频（后端file_type恒为"other"，不可靠）：
  图片走CachedNetworkImage缩略图，视频用video_thumbnail截首帧+播放图标，音频紫色音符图标+模拟波形（非真实波形分析）
- 删除逻辑：教程用自带id走DELETE /auth/tutorials/:id；其余分类从cos_key末段UUID反推id走DELETE /auth/files/:id，反推失败就不显示删除按钮

### 编辑资料（网易云风格）
- 全白背景，分割线分区，无色块
- 生日选择 → 自动推断星座（ZodiacSignExt.fromBirthday）
- 星座：自研SVG icon（ZodiacIcon）+ 紫色文字，无背景

### 消息中心
- 三Tab：通知/私信/群组
- 私信支持：文字/代码/LaTeX/教程卡片/图片
- 目前 mock 数据，后端消息API待建

## 共享组件
lib/shared/widgets/
- main_shell.dart — 底部导航（首页/发现/+/消息/我的）
- zodiac_icon.dart — 十二星座SVG图标 + ZodiacPicker

lib/shared/models/
- user_model.dart — UserModel
- tutorial_model.dart — TutorialModel（含tags兼容解析）

## 踩过的坑（必读）

### 1. 账号数据隔离（最重要）
所有缓存key必须带userId前缀：'${userId}_tutorials'
退出登录只清当前用户缓存，不能 deleteAll()

### 2. 时间戳秒级
DateTime.fromMillisecondsSinceEpoch(created_at * 1000)

### 3. 教程列表格式
返回 {tutorials:[...], total, page, pages}，不是直接数组

### 4. tags 兼容
if (tags is String) jsonDecode(tags) else tags

### 5. cover_image 可能为空
无封面按标题首字符 hashCode 选色（紫/绿/橙/粉/蓝）

### 6. avatar 两种格式
avatar.startsWith('data:image')
  ? Image.memory(base64Decode(去掉前缀))
  : CachedNetworkImage(url)

### 7. ApiClient 不抛异常
内部 catch DioException，返回 ApiResponse.error()
调用方必须检查 res.success，不能用 try/catch

### 8. currentUserProvider
ref.watch(currentUserProvider) → UserModel?
不存在 authProvider 或 authProvider.userId

### 9. token 存储 key
AppConstants.tokenKey(userId) = 'user_${userId}_token'
不要用裸字符串 'access_token'

### 10. Cookie 自动管理
已配置 cookie_jar + dio_cookie_manager
refresh token 走 HttpOnly Cookie（dp_refresh），Dio 自动携带

### 11. ChatScreen 必须携带 conversation
context.push('/messages/chat/${id}', extra: conversation)
extra 为 null 时发送按钮静默失效

### 12. Scaffold drawer 做侧边栏
个人主页侧边栏用 Scaffold(drawer: ...) 实现
不要嵌入主页面 Column，否则变成页面内容而非抽屉

### 13. 全局 InputDecorationTheme 会漏灰色底
app_theme.dart 的亮/暗主题都设了 filled:true 的灰色fillColor
任何 TextField 不显式加 filled:false，都会透出一层灰底，跟自定义/透明背景很违和

### 14. GridView 会自动套安全区 padding
GridView / GridView.count 不传 padding 时，会默认套 MediaQuery.padding（安全区）
嵌在 Column/SingleChildScrollView 里的 GridView 必须显式 padding:EdgeInsets.zero，否则跟相邻元素之间会出现说不清的大缝隙（个人主页九宫格、发布页快速开始2列格都踩过）

### 15. ReorderableListView 的拖拽默认是"长按任意位置"
一个纯装饰性 Icon(Icons.drag_handle) 不会自动变成拖拽手柄
要让"只有这个图标能拖"：ReorderableListView 传 buildDefaultDragHandles:false，图标外面包 ReorderableDragStartListener(index:...)

### 16. GET /auth/storage/usage 里 cos_key 格式不统一
tutorials 分类的 cos_key 已经是完整 https:// URL；media/docs/notebooks 分类是相对路径，要拼COS前缀
无脑统一拼前缀会在tutorials上产出重复前缀的坏URL——渲染前必须判断 startsWith('http')

### 17. file_type 字段不可信
POST /auth/files/upload 返回的 file_type 不管传什么 contentType 上传，实测永远是 "other"
要分辨图片/视频/音频只能靠文件名后缀，不能指望后端字段

### 18. 测试路由跳转后必须用 git diff 验证复原
没有UI自动化点击手段时，临时改 splash_screen.dart 的 context.go(...) 目标路由来做可视化验证是可行的
但改完测试后必须 git diff 确认改动只有那一行、且改回原值后 diff 为空，否则容易在来回改的过程中误删周边代码
另外要注意 _restore() 里有两条成功跳转分支（首次登录成功 + 刷新token后登录成功），只改一条可能测不出效果——本机token若已过期会走第二条分支

### 19. ListView/SliverList 会把直接子项的 cross axis 撑成 tight constraint
垂直滚动的 ListView（包括其他基于 Sliver 的滚动容器）给每个直接子项的横向
约束是 min==max==视口宽度，一个明确写了 `width: 36` 的 Container 放进去，
自己的 width 会被这个 tight constraint 顶掉、被拉伸撑满全宽——不是 Container
的 bug，是 BoxConstraints.constrain() 的正常行为。踩过一次（aurora_screen.dart
的返回按钮被拉成了一条通栏），修法是给这个子项外面套一层 `Align`（或
`Row`/`Center`），不要指望子项自己的固定 width 能在 ListView 直接子项这一层
生效

## COS 存储
bucket: dp-1317483118，region: ap-hongkong
URL: https://dp-1317483118.cos.ap-hongkong.myqcloud.com/${cosKey}
公共读，图片 URL 可直接访问
头像目录：avatars/（不计入配额）

## 服务器
腾讯云香港，IP: 150.109.77.250
后端：/root/dp-auth-backend，pm2 服务名 dp-auth，端口 3001
数据库：MySQL，内网 10.5.0.6:3306，库名 dp_users

## 品牌破圈思路
用户发文章的动力来源
现有平台的问题
知乎：写了没人看，算法不扶持新人，大V垄断流量
小红书：适合生活类，数据科学/学术内容没有受众
微信公众号：封闭，没有发现机制，只能靠自己推广
CSDN/博客园：太技术向，没有社区感，排版差
极梦要填的空白：一个让知识型创作者觉得"值得写"的地方。

动力一：被看见
这是最基础的需求。极梦的优势是垂直受众精准——在极梦写一篇关于贝叶斯统计的文章，读者都是真正对这个感兴趣的人，点赞和评论的含金量远高于泛流量平台。
比在朋友圈发文章被10个人无聊点赞，更有价值的是被100个真正懂的人认真阅读。

动力二：Notebook 是天然的发布动机
这是极梦独有的。
用户在 Power Notebook 里做了一个分析，代码跑通了，图出来了——这个过程本身就是内容。发布只需要点一下"发布为文章"，Notebook 直接转成带可运行代码的教程。
其他平台没有这个路径。用户在极梦创作的过程本身就产生了发布动机，不需要额外激励。

动力三：变现预期
早期即使没有知识付费，也要让创作者看到路径：

公开粉丝数和阅读量，让创作者感受到积累
早期创作者标签（"极梦认证创作者"）
承诺未来开放付费专栏

人愿意投入的前提是相信未来有回报，不需要现在就兑现。

动力四：工具本身就值得用
即使没有读者，Power Notebook 本身也是一个好用的工具——比 Jupyter 更轻量，比 Colab 更私密，带 LaTeX 渲染，带 ARIA 辅助。
用户先因为工具来，然后自然而然地发布。这和 GitHub 的逻辑一样：开发者用 GitHub 管代码，不是为了涨粉，但代码公开之后自然形成了社区。

动力五：社区归属感
极梦的全领域定位创造了一个新的身份认同——"极梦创作者"，不是某个领域的专家，而是跨领域的知识探索者。
这个身份在其他平台没有对应位置。物理系学生在知乎写经济，没人看；在极梦，"用物理思维理解经济"恰恰是平台鼓励的。

冷启动的关键策略
光靠产品功能不够，还需要：
第一步：找50个种子创作者
不是泛泛招募，是主动找那些在知乎、公众号上已经有积累但觉得"怀才不遇"的人，给他们开白名单、给他们流量扶持，让他们第一批内容在极梦独家发布。
第二步：编辑团队主动约稿
早期不能完全依赖自然投稿，要像杂志编辑一样主动选题、约稿、帮作者打磨，保证首页内容质量。
第三步：让第一批内容破圈
把极梦上最好的文章推到微博、微信、知乎——不是推极梦这个平台，而是推文章本身，让读者追着内容来注册。

## 视觉风格（2026 风格，高质感）

### 主视觉方向
- 深色为主：主背景 `#0A0A1A` → `#1A0E2E` → `#0D1A3A` 渐变
- 极光光效：`radial-gradient` 紫蓝光晕叠加，营造深空感
- 毛玻璃层：`BackdropFilter blur(20-32px)` + `rgba(255,255,255,0.08-0.12)` 半透明
- 主色调：`#6366F1` 紫蓝，点缀 `#8B5CF6` 深紫

### 侧边栏（Drawer）视觉规范
- 背景：`rgba(15,10,30,0.82)` + `BackdropFilter blur(32px) saturate(1.8)`
- 右边框：`0.5px rgba(255,255,255,0.08)`
- Header：深紫极光渐变 `rgba(99,102,241,0.25) → rgba(139,92,246,0.15) → transparent`
- 菜单图标背景：各领域色 `.withOpacity(0.2)`，图标用浅色版本
- 菜单文字：`rgba(255,255,255,0.85)`
- 分割线：`rgba(255,255,255,0.06)`
- 底部按钮：`rgba(255,255,255,0.4)`，退出用 `#FF6B6B`

### 个人主页视觉规范
- 封面区：深色渐变背景 + `radial-gradient` 极光光晕
- 顶部按钮：毛玻璃 `rgba(255,255,255,0.10)` + `BackdropFilter blur(10px)`
- Badge：领域色 `.withOpacity(0.3)` 背景 + 浅色文字 + `0.5px` 领域色边框
- 统计行：`rgba(255,255,255,0.08)` 毛玻璃卡片
- Tab 选中：`#6366F1` 下划线（深色主题）
- 底部导航：`rgba(10,10,26,0.85)` + `BackdropFilter blur(20px)`

### 技术实现栈
- Flutter + Material 3 + 自定义 Design System
- `CustomPainter`：渐变背景、极光光效
- `BackdropFilter`：毛玻璃效果（侧边栏、顶部按钮、底部导航）
- `AnimationController` / `ImplicitAnimation`：页面微交互
- Lottie / Rive：局部动态效果（可选，后期）
- Skia 渲染引擎：保证复杂渐变在 iOS/Android 一致

  ### 颜色系统（深色主题）
  ```dart
  // 背景层
  bgDeep:    Color(0xFF0A0A1A)
  bgMid:     Color(0xFF1A0E2E)
  bgLight:   Color(0xFF0D1A3A)

  // 毛玻璃
  glassLight: Color(0x1AFFFFFF)  // rgba(255,255,255,0.10)
  glassMid:   Color(0x14FFFFFF)  // rgba(255,255,255,0.08)
  glassBorder: Color(0x0FFFFFFF) // rgba(255,255,255,0.06)

  // 主色
  primary:   Color(0xFF6366F1)
  primaryAlt: Color(0xFF8B5CF6)

  // 文字
  textPrimary:   Color(0xFFFFFFFF)
  textSecondary: Color(0xCCFFFFFF)  // 0.8
  textMuted:     Color(0x66FFFFFF)  // 0.4

  // 功能色
  danger: Color(0xFFFF6B6B)
  ```

  ### 注意事项
  - `BackdropFilter` 在 iOS 上性能优秀，Android 需注意层数不要过多
  - 渐变光晕用 `DecoratedBox` + `BoxDecoration` 叠加，不要用 `ShaderMask`（性能差）
  - 深色模式下所有边框用 `rgba白色` 而非 `rgba黑色`
  - 九宫格内容区卡片用深色渐变而非白色，保持整体调性一致

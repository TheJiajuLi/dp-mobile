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

### Badge 配色规则
数据科学 → bg:#EEF0FF color:#6366F1
生命科学 → bg:#E8F8F0 color:#16A34A
经济     → bg:#FFF7E6 color:#D97706
宇宙天文 → bg:#FDF0F8 color:#C026D3
编程     → bg:#E6F0FF color:#2563EB
时事     → bg:#F5F5F5 color:#555555

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
POST /auth/register → {message:'注册成功'}
GET /auth/me → {id, username, email, avatar, bio, created_at}
PATCH /auth/me → 更新 username/bio/website
POST /auth/change-password → {oldPassword, newPassword}
DELETE /auth/account → 注销账号

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
GET /auth/users/search?handle=xxx
GET /auth/users/profile/:identifier → {id,username,handle,avatar,bio,website,follower_count,following_count,tutorial_count}
POST /auth/users/:targetId/follow
DELETE /auth/users/:targetId/follow
GET /auth/users/:targetId/follow-status → {isFollowing}
GET /auth/users/:userId/followers
GET /auth/users/:userId/following

### 文件
POST /auth/files/upload (multipart, field='file') → {id,filename,url,cos_key}
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
/home          → 首页（Feed）
/discover      → 发现页（专题+领域地图+创作者）
/publish       → 发布页（Block 编辑器）
/messages      → 消息中心
/messages/chat/:conversationId → 聊天页
/profile       → 我的（个人主页）
/edit-profile  → 编辑资料
/settings      → 设置
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

### 发布页（Block编辑器）
- 顶部：标题输入 + 草稿/发布按钮
- 封面图 + 摘要 + 标签（前置在编辑区顶部）
- Block 列表（白色圆角卡片，右上角拖拽+删除）
- Block 类型：文字/代码/LaTeX/图片/引用/视频(Pro)/音频(Pro)/链接
- 底部横排工具栏（替代左侧竖排，更适合手机）

### Power Notebook
- 首页：最近打开（左滑删除）+ 模板 + 新建底部弹窗
- 编辑器：Cell列表（Python/R/LaTeX/Markdown/SQL）
- Python：隐藏WebView跑 Pyodide（dreamingpolar.com/components/compiler/compiler.js）
- LaTeX：flutter_math_fork 渲染
- 导入：file_picker（csv/xlsx/json/py/ipynb/tex/md）
- 持久化：SharedPreferences，key带userId前缀

### 个人主页（重设计中）
- 底色 #FAFAF8，封面160px，头像64px压底部
- 兴趣领域 badge（从tags解析，最多3个，各领域配色）
- 统计行：白色圆角卡片包裹，文章/获赞/粉丝/关注
- 四Tab：文章/Notebook/收藏/点赞
- 文章等三Tab：3列九宫格，Notebook：列表式
- 左上角汉堡 → Scaffold drawer 抽屉（不嵌入主页面）
- 侧边栏：紫色渐变header + 会员卡 + 菜单 + 底部三按钮

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

## COS 存储
bucket: dp-1317483118，region: ap-hongkong
URL: https://dp-1317483118.cos.ap-hongkong.myqcloud.com/${cosKey}
公共读，图片 URL 可直接访问
头像目录：avatars/（不计入配额）

## 服务器
腾讯云香港，IP: 150.109.77.250
后端：/root/dp-auth-backend，pm2 服务名 dp-auth，端口 3001
数据库：MySQL，内网 10.5.0.6:3306，库名 dp_users

# 极梦 Flutter 开发上下文

## 产品定位
极梦（Dreaming Polar）— 数据科学内容社区
定位：知乎 + 小红书 + Kaggle 的融合
Slogan：极梦，为创造而生
品牌色：#6366F1

## 技术栈
- Flutter + Dart
- 状态管理：Riverpod（currentUserProvider 存登录用户）
- 路由：GoRouter
- 网络：ApiClient（封装 Dio，自动注入 Bearer token）
- 本地存储：flutter_secure_storage + shared_preferences
- 图片：cached_network_image + flutter_svg

## 后端API完整列表
base: https://api.dreamingpolar.com

### 认证
POST /auth/login → {accessToken, username}
  注意：注册成功后自动调用login获取token
POST /auth/refresh → {accessToken, user}
  走HttpOnly Cookie（dp_refresh），不需要手动传token
POST /auth/register → {message:'注册成功'}
  成功后自动调用login
GET /auth/me → {id,username,email,avatar,bio,created_at}
PATCH /auth/me → 更新用户名/简介/website
  gender/location/birthday/zodiac 后端开发中（2026-07-04前端已先接上，
  实测目前PATCH会静默丢弃这4个字段、GET不返回，后端上线后自动生效）
POST /auth/change-password → {oldPassword,newPassword}
DELETE /auth/account → 注销账号

### 教程
GET /auth/tutorials?status=published&author=xxx&page=1&limit=12
→ {tutorials:[{id,title,cover_image,summary,tags,likes,views,created_at,username,avatar,user_id}], total,page,pages}
  注意：author支持username或user_id精确匹配
POST /auth/tutorials → {title,summary,cover_image,tags(array),blocks(JSON string),status}
PUT /auth/tutorials/:id → 同上
DELETE /auth/tutorials/:id → 同时删除COS封面图
POST /auth/tutorials/:id/like
DELETE /auth/tutorials/:id/like
GET /auth/tutorials/:id/comments
POST /auth/tutorials/:id/comments → {content}

### 用户
GET /auth/users/search?handle=xxx → {users:[...]}
GET /auth/users/profile/:identifier → {id,username,handle,avatar,bio,website,follower_count,following_count,tutorial_count}
PUT /auth/users/handle → 修改handle（30天一次）
POST /auth/users/:targetId/follow
DELETE /auth/users/:targetId/follow
GET /auth/users/:targetId/follow-status → {isFollowing}
GET /auth/users/:userId/followers → {followers:[...]}
GET /auth/users/:userId/following → {following:[...]}
PUT /auth/users/privacy → {publicProfile,publicFavorites,allowComments,allowMessages}

### 文件
GET /auth/files → {files:[{id,filename,file_type,size_bytes,cos_key,url,platform}]}
POST /auth/files/upload (multipart,field='file') → {id,filename,url,cos_key}
POST /auth/update-avatar (multipart,field='avatar') → {avatar:'COS URL'}
  注意：固定key avatars/${userId}.jpg，覆盖式上传
GET /auth/storage/usage → {quota,membership,totalBytes,categories:{notebooks,tutorials,media,docs}}

### 消息
GET /auth/notifications → {notifications:[...],unread}
POST /auth/notifications/read → {ids:[]} 空数组=全部已读
GET /auth/notifications/unread-count → {unread}
GET /auth/conversations → {conversations:[...]}
GET /auth/conversations/:id/messages → {messages:[...]}
POST /auth/messages → {toUserId,content,type,metadata}
  type: text/code/image/latex/tutorial

### ARIA
POST /api/chat
headers: Authorization: Bearer token
body: {messages:[{role,content}],dataframe_context:{varName,columns,rowCount,sampleRows}}

### 存储配额
免费版：200MB，Pro：5GB，Pro Max：20GB
头像不计入配额（avatars/目录排除）
删除教程时自动清理COS封面图

## Block格式（教程内容）
blocks是JSON字符串：
[{id, type(text|code|latex|heading|image|callout), content, language, executable, level, variant, imageUrl, caption}]

## 已实现的功能模块

### 路由结构
/splash → 启动页（自动登录检查）
/login → 登录页
/register → 注册页
/home → 首页（应用市场九宫格）
/community → 社区（瀑布流）
/publish → 发布（Block编辑器）
/messages → 消息中心
/messages/chat/:conversationId → 聊天页
/profile → 我的（个人主页）
/edit-profile → 编辑资料
/settings → 设置
/settings/security → 账号安全
/settings/security/history → 登录记录
/settings/privacy → 隐私设置
/settings/storage → 云端存储
/settings/about → 关于极梦
/settings/payment → 支付方式（占位）
/settings/subscription → 订阅管理（占位）
/notebook → Power Notebook首页
/notebook/:id → Notebook编辑器
/users/:identifier → 他人主页
/users/:userId/followers → 粉丝列表
/users/:userId/following → 关注列表
/tutorial/:id → 教程详情页

### 底部导航
首页 / 社区 / +发布 / 消息 / 我的

### 首页
应用市场九宫格，已上线：Power Notebook、ARIA分析助手
即将上线：数据网格Grid、可视化工厂、数学建模

### 社区
2列瀑布流，搜索栏+标签筛选（本地过滤）
下拉刷新+上拉加载更多（分页）
教程卡片：封面图/占位色+标题+作者+点赞/浏览数

### Power Notebook
- 首页：最近打开列表（可左滑删除）+模板+新建底部弹窗
- 编辑器：Cell列表，支持Python/LaTeX/Markdown/JS/SQL
- Python运行：隐藏WebView加载compiler.js（Pyodide）
- LaTeX渲染：flutter_math_fork
- input()支持：预收集弹窗
- 导入：file_picker，支持csv/xlsx/json/py/ipynb/tex/md
- 数据持久化：SharedPreferences，key带userId前缀

### 用户主页
- 小红书风格：封面图+头像+统计+四tab
- 星座badge（ZodiacBadge组件）
- 个人链接（最多3条，url_launcher跳转）
- 关注/取消关注（实时更新计数）
- 发消息按钮（跳转聊天页，携带conversation对象）
- 九宫格：教程/Notebook/收藏/点赞四tab

### 编辑资料
- 网易云风格：全白背景+Divider分区，无GridView星座选择器
- 昵称/简介/性别/所在地/生日/星座一起 PATCH /auth/me（gender/location/
  birthday/zodiac后端开发中，见上面API列表的备注）
- 星座由生日推断（ZodiacSignExt.fromBirthday），随生日一起提交给后端
- 用户名（@handle）单独接 PUT /auth/users/handle，30天限频，失败不影响其它字段的保存
- 生日/星座有本地legacy key兜底：${userId}_birthday / ${userId}_zodiac
  （上一版存的，读取时后端字段优先，保存成功后清掉本地legacy key）
- 个人链接（最多3条，存${userId}_links）
- 头像上传（相册→COS，覆盖式，key:avatars/${userId}.jpg）
- 封面图上传（相册→COS，存${userId}_cover_image）

### 消息中心
- 通知tab：点赞/评论/关注，30秒轮询
- 私信tab：会话列表，未读角标
- 聊天页：文字/代码/LaTeX/图片消息
- 5秒轮询更新消息
- 加号菜单：添加好友（搜索@handle）/建群/建论坛

### 设置页
- 账号安全：修改密码/登录记录（含地理位置）/注销账号
- 通用：主题（ThemePreference）/字体/通知开关/清缓存
- 隐私：公开主页/收藏/评论/消息开关（存后端）
- 云端存储：分类文件夹，API实时读取，存储检查机制
- 会员中心：订阅/支付（占位）
- 关于极梦：版本/官网/协议

### Token刷新
- 403时自动refresh，单飞去重（_refreshing Future）
- CookieJar持久化（PersistCookieJar）
- 强制登出走 appRouter.go('/login')
- App回到前台触发silentRefresh()

## 共享组件
lib/shared/widgets/
- main_shell.dart — 底部导航Shell
- zodiac_icon.dart — 十二星座SVG图标+ZodiacPicker
lib/shared/models/
- user_model.dart — UserModel
- tutorial_model.dart — TutorialModel（含tags兼容解析）

## 踩过的坑（必读）

### 1. 账号数据隔离（最重要）
所有缓存key必须带userId前缀：
'${userId}_tutorials'，'${userId}_nb_recent'
退出登录时只清当前用户缓存，不能deleteAll()

### 2. 时间戳秒级
DateTime.fromMillisecondsSinceEpoch(created_at * 1000)

### 3. 教程列表格式
返回{tutorials:[...],total,page,pages}，不是直接数组

### 4. tags兼容
if (tags is String) jsonDecode(tags) else tags

### 5. cover_image可能为空
无封面时按标题首字符hashCode选色（紫/绿/橙/粉/蓝）

### 6. avatar格式
新数据全是COS URL，老数据可能是base64
avatar.startsWith('data:image')
  ? Image.memory(base64Decode(去掉前缀))
  : CachedNetworkImage(url)

### 7. ApiClient不抛异常
ApiClient内部catch DioException，返回ApiResponse.error()
调用方必须检查res.success，不能用try/catch
包括ApiClient.delete()也一样

### 8. currentUserProvider
获取当前登录用户：ref.watch(currentUserProvider)→UserModel?
userId = ref.watch(currentUserProvider)?.id
不存在authProvider或authProvider.userId

### 9. token存储key
AppConstants.tokenKey(userId) = 'user_${userId}_token'
不要用裸字符串'access_token'

### 10. Cookie自动管理
已配置cookie_jar + dio_cookie_manager
refresh token走HttpOnly Cookie（dp_refresh）
Dio会自动携带，不需要手动处理

### 11. 主题Provider
用ThemePreference（不是AppTheme，有命名冲突）
themeProvider → ThemePreference.system/light/dark

### 12. ChatScreen必须携带conversation对象
context.push('/messages/chat/${convId}', extra: conversation)
_send()靠conversation.otherUserId发消息
extra为null时发送按钮静默失效

### 13. Avatar覆盖式上传
固定key：avatars/${userId}.jpg
每次上传覆盖同一文件，不累积

### 14. 存储检查
发送文件前调用StorageChecker.checkAndPrompt()
超过50%显示警告，100%阻断并提示升级

### 15. username ≠ handle
username（昵称，可重复）走PATCH /auth/me
handle（@唯一用户名，30天改一次）走PUT /auth/users/handle
currentUserProvider的UserModel不带handle字段
需要handle时单独GET /auth/users/profile/:username

## COS存储
bucket: dp-1317483118，region: ap-hongkong
URL: https://dp-1317483118.cos.ap-hongkong.myqcloud.com/${cosKey}
公共读，图片URL可直接访问
头像目录：avatars/（不计入配额）
封面图目录：covers/
用户文件目录：files/

## 品牌设计
主色：#6366F1（紫蓝）
Logo：方案C（极光数据——山脉剪影+数据折线+星点）
Slogan：极梦，为创造而生
风格：小红书+知乎+网易云，干净简洁

## 服务器信息
腾讯云香港，IP: 150.109.77.250
后端目录：/root/dp-auth-backend
进程管理：pm2，服务名dp-auth，端口3001
数据库：MySQL，内网10.5.0.6:3306，库名dp_users

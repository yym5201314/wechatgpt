# WeChatGPT（聊天助手）5.2.0

微信内手动使用 AI 的插件：在单聊文字气泡的长按菜单里追加「AI回复」「AI分析」，设置面板在微信内部打开，不注册到系统设置。

## 功能

- **AI 回复**：读取当前单聊最近 N 条双方消息，把生成的回复填入输入框，不自动发送。
- **AI 分析**：按日期或全部聊天统计双方消息、文字、图片、视频、红包、转账、小程序等类型。
- 只作用于私聊文字气泡；群聊、图片、语音、表情气泡不追加菜单。
- 服务商走 OpenAI 兼容接口，KEY 存在当前 App 的钥匙串，不写入 plist。

## 面板入口

- 微信「设置」→ 第一组「WeChatGPT」→ 打开面板。
- 装有插件管理器时，另外出现在插件列表（此时微信设置页不再重复出现）。

面板分两张卡片：

1. 功能面板：启用插件、长按菜单 AI 回复、读取条数（读取聊天记录始终开启）。
2. AI 接口：服务商与模型、回复消息前缀、提示词模板。

服务商页里点一行设为当前服务商（行首 ✓），点行尾按钮编辑，左滑删除；编辑页可「从接口拉取模型」「验证 API」。

## 工程结构

```text
WeChatGPT/
|-- AxsWeChatGPT.plist           注入过滤器（com.tencent.xin）
|-- AxsWeChatGPTBuild.mk         SDK / 部署版本 / 架构
|-- Makefile
|-- control                      包信息与中文说明
|-- tweak.json                   模块清单（供 doctor 检查）
|-- build.sh                     根证书方案打包（rootful/rootless/roothide）
|-- Hooks/
|   |-- AxsWeChatGPTMain.xm              %ctor 与菜单安装
|   |-- AxsWeChatGPTEntrySettings.xm     微信设置页入口
|   `-- AxsWeChatGPTEntryPlugins.xm      插件列表入口
|-- Headers/
|   `-- AxsWeChatGPTPrivate.h            共享提示框与配置引用
|-- Sources/
|   |-- AxsWeChatGPTConfig.h/.m          配置读写（域 com.axs.wechatgpt）
|   |-- AxsWeChatGPTClient.h/.m          OpenAI 兼容接口
|   |-- AxsWeChatGPTWeChatBridge.h/.m    微信私有接口只读封装
|   |-- AxsWeChatGPTMessageReply.h/.m    回复与分析流程
|   |-- AxsWeChatGPTMenuInjector.h/.m    原生长按菜单注入
|   `-- AxsWeChatGPTEntryRouter.h/.m     面板统一路由
`-- Controllers/
    |-- AxsWeChatGPTRootViewController.h/.m            卡片式主面板
    |-- AxsWeChatGPTSettingItem/SettingCell/CardCell   卡片行与卡片
    |-- AxsWeChatGPTCardTableViewController.h/.m       卡片列表基类
    |-- AxsWeChatGPTProvidersViewController.h/.m       服务商列表
    |-- AxsWeChatGPTProviderEditorViewController.h/.m  服务商编辑
    |-- AxsWeChatGPTModelPickerViewController.h/.m     模型选择
    |-- AxsWeChatGPTAnalysisViewController.h/.m        AI 分析页
    `-- AxsWeChatGPTPromptsViewController.h/.m         提示词模板
```

约定：自定义类、文件名用 `AxsWeChatGPT` 前缀，C 函数与自有 selector 用 `axs_wechatgpt_` 前缀；只有面板写配置，Hook 只读。

## 构建

```sh
export THEOS=~/theos
bash build.sh              # 默认 rootless
bash build.sh all          # rootful + rootless + roothide
```

静态检查用 axs-wechat-tweaks skill 的 `scripts/doctor.py <工程目录>`（不在本工程内）。

CI：`.github/workflows/build.yml`。

静态检查通过不代表 Theos 编译或真机验证通过；菜单注入与面板入口依赖微信私有类，换微信版本需要重新核对。

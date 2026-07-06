import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RivalRadarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "DeepSeek/兼容模型接口", systemImage: "sparkles") {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField("接口密钥", text: $store.apiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Button {
                            store.baseURL = "https://api.deepseek.com"
                            store.model = "deepseek-v4-flash"
                        } label: {
                            Label("DeepSeek 预设", systemImage: "sparkles")
                        }

                        Button {
                            store.baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
                            store.model = "qwen3.6-plus"
                        } label: {
                            Label("阿里云百炼 Qwen 预设", systemImage: "cloud")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveTextArea(placeholder: "接口地址", text: $store.baseURL, minLines: 1, maxLines: 4)
                        TextField("模型", text: $store.model)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }

                    Text("兼容 OpenAI 风格的 /chat/completions。阿里云百炼可使用 https://dashscope.aliyuncs.com/compatible-mode/v1 与模型 qwen3.6-plus。无接口密钥时仍会采集和去重，但只保存原文摘要。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard(title: "Tavily 搜索接口", systemImage: "sparkle.magnifyingglass") {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("Tavily 接口密钥", text: $store.tavilyAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Text("这里只需要配置一次。所有 Tavily 搜索数据源都会自动使用这个密钥；导入 JSON 时如果包含 tavily.apiKey，也会同步保存到这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard(title: "全局采集频率", systemImage: "clock.badge.checkmark") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("默认频率", selection: $store.globalFrequency) {
                        ForEach(SourceFrequency.globalOptions) { frequency in
                            Text(frequency.label).tag(frequency)
                        }
                    }
                    .pickerStyle(.segmented)

                    if store.globalFrequency == .custom {
                        HStack {
                            Stepper("自定义间隔 \(store.globalCustomFrequencyMinutes) 分钟", value: $store.globalCustomFrequencyMinutes, in: 1...43_200, step: 5)
                            TextField("分钟", value: $store.globalCustomFrequencyMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                    }

                    Text("新建数据源和 Tavily 批量导入默认“跟随全局”。如果某个数据源需要更高或更低频率，可以在“数据源配置”里单独覆盖。当前全局频率：\(store.globalFrequencyLabel)。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard(title: "通知", systemImage: "bell") {
                Toggle("发现新情报时发送 macOS 通知", isOn: $store.notificationsEnabled)
                    .toggleStyle(.switch)
            }

            SectionCard(title: "Chrome 登录来源", systemImage: "person.crop.circle.badge.checkmark") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可用 Chrome 用户资料")
                        .font(.subheadline)
                    if store.chromeProfiles.isEmpty {
                        Text("未发现可读取的 Chrome 用户资料。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.chromeProfiles) { profile in
                            HStack {
                                Image(systemName: "person.crop.circle")
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                    Text(profile.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("第一版会只读复制 Chrome Cookie 数据库，并用其中可解密的 Cookie 访问登录页面；无法处理验证码、二次验证或强反爬页面。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

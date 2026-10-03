import 'ai_provider.dart';

/// 供应商快速配置模板：选择后自动填充名称 / API 风格 / Base URL，
/// 用户只需填 API Key。也支持完全自定义。
class AiProviderTemplate {
  const AiProviderTemplate({
    required this.id,
    required this.name,
    required this.apiStyle,
    this.baseUrl,
    this.description = '',
  });

  final String id;

  /// 展示名。
  final String name;

  final ApiStyle apiStyle;

  /// 预填的 Base URL；`custom` 模板为空（用户自行填写）。
  final String? baseUrl;

  final String description;
}

const List<AiProviderTemplate> kAiProviderTemplates = [
  AiProviderTemplate(
    id: 'zhipu',
    name: '智谱官方（GLM）',
    apiStyle: ApiStyle.openaiCompatible,
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    description: '智谱 AI 开放平台，OpenAI 兼容',
  ),
  AiProviderTemplate(
    id: 'openai',
    name: 'OpenAI 官方',
    apiStyle: ApiStyle.openaiCompatible,
    baseUrl: 'https://api.openai.com/v1',
    description: 'GPT 系列，OpenAI 兼容',
  ),
  AiProviderTemplate(
    id: 'anthropic',
    name: 'Claude 官方（Anthropic）',
    apiStyle: ApiStyle.anthropic,
    baseUrl: 'https://api.anthropic.com',
    description: 'Claude 系列，Anthropic 协议',
  ),
  AiProviderTemplate(
    id: 'deepseek',
    name: 'DeepSeek 官方',
    apiStyle: ApiStyle.openaiCompatible,
    baseUrl: 'https://api.deepseek.com/v1',
    description: 'DeepSeek，OpenAI 兼容',
  ),
  AiProviderTemplate(
    id: 'moonshot',
    name: 'Kimi（月之暗面）',
    apiStyle: ApiStyle.openaiCompatible,
    baseUrl: 'https://api.moonshot.cn/v1',
    description: 'Kimi 系列，OpenAI 兼容',
  ),
  AiProviderTemplate(
    id: 'qwen',
    name: '通义千问（阿里）',
    apiStyle: ApiStyle.openaiCompatible,
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    description: '百炼兼容模式，OpenAI 兼容',
  ),
  AiProviderTemplate(
    id: 'custom',
    name: '自定义',
    apiStyle: ApiStyle.openaiCompatible,
    baseUrl: null,
    description: '任意 OpenAI 兼容 / Anthropic 兼容服务，自填地址与 Key',
  ),
];

#import "DGPTClient.h"
#import "DGPTConfig.h"

@implementation DGPTClient
+ (instancetype)shared {
    static DGPTClient *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [DGPTClient new]; });
    return shared;
}
- (instancetype)init {
    return [super init];
}
+ (NSError *)problem:(NSString *)message {
    return [NSError errorWithDomain:@"StandaloneGPT" code:-1
        userInfo:@{NSLocalizedDescriptionKey:message ?: @"未知错误"}];
}
+ (NSURLComponents *)validatedComponents:(NSString *)baseURL error:(NSError **)error {
    NSString *input = [baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *parts = [NSURLComponents componentsWithString:input];
    if (![parts.scheme.lowercaseString isEqualToString:@"https"] || !parts.host.length ||
        parts.user.length || parts.password.length || parts.fragment.length || parts.query.length) {
        if (error) *error = [self problem:@"请输入合法的 HTTPS API 地址，不要包含查询参数或账号密码。"];
        return nil;
    }
    NSString *path = parts.percentEncodedPath ?: @"";
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length-1];
    parts.percentEncodedPath = path;
    return parts;
}
+ (NSURL *)resolvedEndpointForBaseURL:(NSString *)baseURL error:(NSError **)error {
    NSURLComponents *parts = [self validatedComponents:baseURL error:error];
    if (!parts) return nil;
    NSString *path = parts.percentEncodedPath ?: @"";
    NSString *lower = path.lowercaseString;
    if ([lower hasSuffix:@"/messages"] && ![lower hasSuffix:@"/chat/completions"]) {
        if (error) *error = [self problem:@"当前仅支持 OpenAI Chat Completions，不支持 Anthropic Messages。"];
        return nil;
    }
    if (![lower hasSuffix:@"/chat/completions"]) {
        if (!path.length && [parts.host.lowercaseString isEqualToString:@"api.deepseek.com"])
            path = @"/chat/completions";
        else if (!path.length) path = @"/v1/chat/completions";
        else path = [path stringByAppendingString:@"/chat/completions"];
    }
    parts.percentEncodedPath = path;
    return parts.URL;
}
+ (NSURL *)resolvedModelsEndpointForBaseURL:(NSString *)baseURL error:(NSError **)error {
    NSURLComponents *parts = [self validatedComponents:baseURL error:error];
    if (!parts) return nil;
    NSString *path = parts.percentEncodedPath ?: @"";
    if ([path.lowercaseString hasSuffix:@"/chat/completions"]) {
        path = [path substringToIndex:path.length - @"/chat/completions".length];
    }
    if ([parts.host.lowercaseString isEqualToString:@"api.deepseek.com"] &&
        [path.lowercaseString isEqualToString:@"/v1"]) path = @"";
    if ([path.lowercaseString hasSuffix:@"/models"]) {
        parts.percentEncodedPath = path;
    } else if (path.length) {
        parts.percentEncodedPath = [path stringByAppendingString:@"/models"];
    } else if ([parts.host.lowercaseString isEqualToString:@"api.deepseek.com"]) {
        parts.percentEncodedPath = @"/models";
    } else {
        parts.percentEncodedPath = @"/v1/models";
    }
    return parts.URL;
}
+ (NSString *)errorMessage:(id)response {
    if (![response isKindOfClass:NSDictionary.class]) return @"";
    id error = response[@"error"];
    id msg = [error isKindOfClass:NSDictionary.class] ? error[@"message"] : error;
    if (![msg isKindOfClass:NSString.class]) msg = response[@"message"];
    return [msg isKindOfClass:NSString.class] ? msg : @"";
}
+ (NSString *)extractText:(id)content {
    if ([content isKindOfClass:NSString.class]) return content;
    if (![content isKindOfClass:NSArray.class]) return @"";
    NSMutableArray *chunks = [NSMutableArray array];
    for (id item in content) if ([item isKindOfClass:NSDictionary.class] &&
        [item[@"text"] isKindOfClass:NSString.class]) [chunks addObject:item[@"text"]];
    return [chunks componentsJoinedByString:@"\n"];
}
- (void)fetchModelsForURL:(NSString *)baseURL apiKey:(NSString *)apiKey completion:(DGPTModelsCompletion)completion {
    if (!completion) return;
    NSError *error = nil;
    NSURL *url = [DGPTClient resolvedModelsEndpointForBaseURL:baseURL error:&error];
    if (!url) { completion(nil, error); return; }
    if (!apiKey.length) { completion(nil, [DGPTClient problem:@"请先填写服务商的 API Key。"]); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 30;
    [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError) { completion(nil, networkError); return; }
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
        id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *result = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
        if (!http || http.statusCode < 200 || http.statusCode >= 300) {
            NSString *detail = [DGPTClient errorMessage:result];
            completion(nil, [DGPTClient problem:[NSString stringWithFormat:@"模型列表 HTTP %ld%@；地址 %@", (long)http.statusCode,
                detail.length ? [@"：" stringByAppendingString:detail] : @"", url.absoluteString]]);
            return;
        }
        id entries = result[@"data"];
        if (![entries isKindOfClass:NSArray.class]) entries = result[@"models"];
        if (![entries isKindOfClass:NSArray.class]) {
            completion(nil, [DGPTClient problem:@"该服务商没有返回 OpenAI 兼容的 data 模型列表。"]); return;
        }
        NSMutableSet<NSString *> *ids = [NSMutableSet set];
        for (id item in entries) {
            id model = [item isKindOfClass:NSString.class] ? item :
                ([item isKindOfClass:NSDictionary.class] ? (item[@"id"] ?: item[@"name"]) : nil);
            if ([model isKindOfClass:NSString.class] && [model length]) [ids addObject:model];
        }
        NSArray *models = [[ids allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        if (!models.count) {
            completion(nil, [DGPTClient problem:@"API 返回的模型列表为空，请确认服务商权限。"]); return;
        }
        completion(models, nil);
    }] resume];
}
- (void)testProviderURL:(NSString *)baseURL apiKey:(NSString *)apiKey
                   model:(NSString *)model completion:(DGPTCompletion)completion {
    if (!completion) return;
    NSError *error = nil;
    NSURL *url = [DGPTClient resolvedEndpointForBaseURL:baseURL error:&error];
    if (!url) { completion(nil, error); return; }
    if (!apiKey.length || !model.length) {
        completion(nil, [DGPTClient problem:@"请先输入 API Key 和模型。"]); return;
    }
    NSDictionary *payload = @{
        @"model":model,
        @"messages":@[@{@"role":@"user", @"content":@"只回复 OK"}],
        @"stream":@NO
    };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!body) { completion(nil, error ?: [DGPTClient problem:@"API 验证请求无法编码"]); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 45;
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError) { completion(nil, networkError); return; }
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
        id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *json = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
        if (!http || http.statusCode < 200 || http.statusCode >= 300) {
            NSString *detail = [DGPTClient errorMessage:json];
            if (!detail.length) detail = @"服务商未接受请求";
            if (detail.length > 260) detail = [[detail substringToIndex:260] stringByAppendingString:@"…"];
            completion(nil, [DGPTClient problem:[NSString stringWithFormat:@"HTTP %ld：%@", (long)http.statusCode, detail]]);
            return;
        }
        NSArray *choices = [json[@"choices"] isKindOfClass:NSArray.class] ? json[@"choices"] : nil;
        NSDictionary *choice = choices.count && [choices.firstObject isKindOfClass:NSDictionary.class] ? choices.firstObject : nil;
        NSDictionary *message = [choice[@"message"] isKindOfClass:NSDictionary.class] ? choice[@"message"] : nil;
        NSString *answer = [DGPTClient extractText:message[@"content"]];
        if (!answer.length) {
            completion(nil, [DGPTClient problem:@"已连接服务商，但未得到 Chat Completions 文字回复。"]);
            return;
        }
        completion([NSString stringWithFormat:@"当前填写的接口和模型可用。回复：%@", answer], nil);
    }] resume];
}

- (void)ask:(NSString *)question completion:(DGPTCompletion)completion {
    if (!question.length) {
        if (completion) completion(nil, [DGPTClient problem:@"消息内容为空"]);
        return;
    }
    [self askWithMessages:@[@{@"role":@"user", @"content":question}] completion:completion];
}

- (void)askWithMessages:(NSArray<NSDictionary *> *)conversationMessages completion:(DGPTCompletion)completion {
    [self submitMessages:conversationMessages applyReplyPreset:YES completion:completion];
}
- (void)askForAnalysisWithMessages:(NSArray<NSDictionary *> *)conversationMessages completion:(DGPTCompletion)completion {
    [self submitMessages:conversationMessages applyReplyPreset:NO completion:completion];
}
- (void)submitMessages:(NSArray<NSDictionary *> *)conversationMessages
      applyReplyPreset:(BOOL)applyReplyPreset completion:(DGPTCompletion)completion {
    if (!completion) return;
    DGPTConfig *config = [DGPTConfig shared];
    NSDictionary *provider = [[config activeProvider] copy];
    NSString *pid = provider[@"id"];
    NSString *key = [config apiKeyForProviderID:pid ?: @""];
    NSString *model = [provider[@"model"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!pid.length || !key.length || !model.length) {
        completion(nil, [DGPTClient problem:@"请在服务商管理中设置 API Key，并拉取和选择模型。"]); return;
    }
    if (![conversationMessages isKindOfClass:NSArray.class] || !conversationMessages.count) {
        completion(nil, [DGPTClient problem:@"消息内容为空"]); return;
    }
    NSError *urlError = nil;
    NSURL *url = [DGPTClient resolvedEndpointForBaseURL:provider[@"url"] error:&urlError];
    if (!url) { completion(nil, urlError); return; }

    // The selected preset is the base system prompt. Callers may then add
    // conversation-specific system instructions and alternating history turns.
    NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
    NSString *activeName = [config stringForKey:DGPTActivePrompt];
    if (applyReplyPreset && activeName.length) {
        for (id value in [config arrayForKey:DGPTPromptPresets]) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *item = (NSDictionary *)value;
            if (![item[@"name"] isKindOfClass:NSString.class] ||
                ![item[@"name"] isEqualToString:activeName]) continue;
            NSString *prompt = [item[@"prompt"] isKindOfClass:NSString.class] ? item[@"prompt"] : @"";
            if (prompt.length) [messages addObject:@{@"role":@"system", @"content":prompt}];
            break;
        }
    }
    BOOL hasUserMessage = NO;
    for (id value in conversationMessages) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = (NSDictionary *)value;
        NSString *role = [item[@"role"] isKindOfClass:NSString.class] ? item[@"role"] : @"";
        NSString *content = [item[@"content"] isKindOfClass:NSString.class] ? item[@"content"] : @"";
        if (!content.length || ![@[@"system", @"user", @"assistant"] containsObject:role]) continue;
        [messages addObject:@{@"role":role, @"content":content}];
        if ([role isEqualToString:@"user"]) hasUserMessage = YES;
    }
    if (!hasUserMessage) {
        completion(nil, [DGPTClient problem:@"上下文中没有用户消息"]); return;
    }

    NSDictionary *body = @{
        @"model": model,
        @"messages": messages,
        @"stream": @NO
    };
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    if (!payload.length) {
        completion(nil, [DGPTClient problem:@"无法序列化聊天上下文"]); return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 75;
    request.HTTPBody = payload;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError) { completion(nil, networkError); return; }
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
        id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *json = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
        if (!http || http.statusCode < 200 || http.statusCode >= 300) {
            NSString *detail = [DGPTClient errorMessage:json];
            if (!detail.length) detail = @"请求失败";
            if (detail.length > 260) detail = [[detail substringToIndex:260] stringByAppendingString:@"…"];
            completion(nil, [DGPTClient problem:[NSString stringWithFormat:@"HTTP %ld: %@\n请求路径：%@", (long)http.statusCode, detail, url.path]]);
            return;
        }
        NSArray *choices = [json[@"choices"] isKindOfClass:NSArray.class] ? json[@"choices"] : nil;
        NSDictionary *choice = choices.count && [choices.firstObject isKindOfClass:NSDictionary.class] ? choices.firstObject : nil;
        NSDictionary *message = [choice[@"message"] isKindOfClass:NSDictionary.class] ? choice[@"message"] : nil;
        NSString *answer = [DGPTClient extractText:message[@"content"]];
        if (!answer.length) {
            completion(nil, [DGPTClient problem:@"未收到 OpenAI choices[0].message.content，请检查模型是否支持 Chat Completions。"]);
            return;
        }
        completion(answer, nil);
    }] resume];
}

@end

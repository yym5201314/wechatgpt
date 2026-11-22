#import "AxsWeChatGPTAnalysisViewController.h"
#import "AxsWeChatGPTWeChatBridge.h"
#import "AxsWeChatGPTClient.h"

// Prevent runaway memory use if a chat has hundreds of thousands of records.
// If reached, the UI explicitly marks counts as PARTIAL rather than "all".
static const NSUInteger kAxsWeChatGPTAnalysisSafetyRecords = 100000;
static const NSUInteger kAxsWeChatGPTAnalysisPageSize = 200;
static const NSUInteger kAxsWeChatGPTAnalysisChunkChars = 11000;

static NSString *axs_wechatgpt_trimmed(NSString *s) {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}
static UIViewController *axs_wechatgpt_analysisHost(UIWindow *window) {
    UIViewController *host = window.rootViewController;
    for (NSUInteger i=0; i<20 && host; ++i) {
        if (host.presentedViewController) host = host.presentedViewController;
        else if ([host isKindOfClass:UINavigationController.class])
            host = ((UINavigationController *)host).visibleViewController;
        else if ([host isKindOfClass:UITabBarController.class])
            host = ((UITabBarController *)host).selectedViewController;
        else break;
    }
    return host;
}
static UILabel *axs_wechatgpt_analysisLabel(NSString *text, CGFloat fontSize, BOOL bold) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = bold ? [UIFont boldSystemFontOfSize:fontSize] : [UIFont systemFontOfSize:fontSize];
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 0;
    return label;
}
static UIButton *axs_wechatgpt_analysisButton(NSString *title, id target, SEL selector) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    button.backgroundColor = [UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:0.9];
    button.layer.cornerRadius = 10;
    [button addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:46].active = YES;
    return button;
}

@interface AxsWeChatGPTAnalysisViewController () <UITextViewDelegate>
@end

@implementation AxsWeChatGPTAnalysisViewController {
    NSString *_session;
    BOOL _isGroup;
    UISegmentedControl *_range;
    UIDatePicker *_datePicker;
    UITextView *_question;
    UILabel *_questionPlaceholder;
    UILabel *_answerTitle;
    UILabel *_stats;
    UILabel *_progress;
    UITextView *_answer;
    UIButton *_readButton;
    UIButton *_analyzeButton;
    UIButton *_cancelButton;
    NSMutableDictionary<NSString *,NSDictionary *> *_records;
    NSArray<NSDictionary *> *_snapshot;
    NSArray<NSString *> *_chunks;
    NSString *_signature;
    NSString *_scopeTitle;
    NSString *_customQuestion;
    NSString *_partialSummary;
    BOOL _working;
    BOOL _scanComplete;
    BOOL _statsReady;
    BOOL _analyzeAfterRead;
    NSUInteger _serial;
    NSUInteger _pages;
    NSUInteger _rawReturned;
    NSUInteger _chunkIndex;
    long long _cursorID;
    long long _cursorTime;
    long long _startTime;
    long long _endTime;
}

+ (void)presentWithSessionContext:(NSDictionary<NSString *,id> *)context window:(UIWindow *)window {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self presentWithSessionContext:context window:window]; });
        return;
    }
    NSString *session = context[@"session"];
    if (![session isKindOfClass:NSString.class] || !session.length || !window) return;
    UIViewController *host = axs_wechatgpt_analysisHost(window);
    if (!host || host.isBeingPresented || host.isBeingDismissed) return;
    AxsWeChatGPTAnalysisViewController *vc = [AxsWeChatGPTAnalysisViewController new];
    vc->_session = [session copy];
    vc->_isGroup = [context[@"isGroup"] boolValue];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closePage)];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
    _range = [[UISegmentedControl alloc] initWithItems:@[@"指定日期", @"全部消息"]];
    _range.selectedSegmentIndex = 0;
    [_range addTarget:self action:@selector(rangeChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:_range];
    _datePicker = [UIDatePicker new];
    _datePicker.datePickerMode = UIDatePickerModeDate;
    _datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    [_datePicker addTarget:self action:@selector(rangeChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:_datePicker];
    _question = [UITextView new];
    _question.font = [UIFont systemFontOfSize:15];
    _question.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _question.layer.cornerRadius = 10;
    _question.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    _question.text = @"";
    _question.delegate = self;
    _questionPlaceholder = axs_wechatgpt_analysisLabel(@"想让AI分析什么？", 15, NO);
    _questionPlaceholder.textColor = UIColor.placeholderTextColor;
    _questionPlaceholder.userInteractionEnabled = NO;
    _questionPlaceholder.translatesAutoresizingMaskIntoConstraints = NO;
    [_question addSubview:_questionPlaceholder];
    [NSLayoutConstraint activateConstraints:@[
        [_questionPlaceholder.topAnchor constraintEqualToAnchor:_question.topAnchor constant:11],
        [_questionPlaceholder.leadingAnchor constraintEqualToAnchor:_question.leadingAnchor constant:13],
        [_questionPlaceholder.trailingAnchor constraintLessThanOrEqualToAnchor:_question.trailingAnchor constant:-10]
    ]];
    [_question.heightAnchor constraintEqualToConstant:100].active = YES;
    [stack addArrangedSubview:_question];
    _readButton = axs_wechatgpt_analysisButton(@"统计消息", self, @selector(readStatistics));
    _analyzeButton = axs_wechatgpt_analysisButton(@"确认分析", self, @selector(confirmAnalysis));
    _cancelButton = axs_wechatgpt_analysisButton(@"取消当前任务", self, @selector(cancelTask));
    _cancelButton.hidden = YES;
    [stack addArrangedSubview:_readButton];
    [stack addArrangedSubview:_analyzeButton];
    [stack addArrangedSubview:_cancelButton];
    _stats = axs_wechatgpt_analysisLabel(@"", 15, NO);
    _stats.hidden = YES;
    [stack addArrangedSubview:_stats];
    _progress = axs_wechatgpt_analysisLabel(@"", 13, NO);
    _progress.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:_progress];
    _answerTitle = axs_wechatgpt_analysisLabel(@"AI 分析结果", 16, YES);
    _answerTitle.hidden = YES;
    [stack addArrangedSubview:_answerTitle];
    _answer = [UITextView new];
    _answer.editable = NO;
    _answer.selectable = YES;
    _answer.font = [UIFont systemFontOfSize:15];
    _answer.text = @"";
    _answer.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _answer.layer.cornerRadius = 10;
    _answer.textContainerInset = UIEdgeInsetsMake(12, 8, 10, 8);
    [_answer.heightAnchor constraintEqualToConstant:300].active = YES;
    [stack addArrangedSubview:_answer];
    _answer.hidden = YES;
    [self rangeChanged];
}

- (void)closePage { ++_serial; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)updateQuestionPlaceholder {
    _questionPlaceholder.hidden = _question.isFirstResponder || axs_wechatgpt_trimmed(_question.text ?: @"").length > 0;
}
- (void)textViewDidBeginEditing:(UITextView *)textView {
    if (textView == _question) [self updateQuestionPlaceholder];
}
- (void)textViewDidChange:(UITextView *)textView {
    if (textView == _question) [self updateQuestionPlaceholder];
}
- (void)textViewDidEndEditing:(UITextView *)textView {
    if (textView == _question) [self updateQuestionPlaceholder];
}
- (void)hideAnalysisResult {
    _answerTitle.hidden = YES;
    _answer.hidden = YES;
    _answer.text = @"";
}
- (void)rangeChanged {
    _datePicker.hidden = _range.selectedSegmentIndex != 0;
    _statsReady = NO;
    _stats.hidden = YES;
    _progress.text = @"";
    [self hideAnalysisResult];
}
- (NSString *)currentSignature {
    if (_range.selectedSegmentIndex == 1) return @"all";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [@"date|" stringByAppendingString:[formatter stringFromDate:_datePicker.date] ?: @""];
}
- (void)displayError:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"AI 分析" message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)setWorking:(BOOL)working {
    _working = working;
    _range.enabled = !working;
    _datePicker.enabled = !working;
    _readButton.enabled = !working;
    _analyzeButton.enabled = !working;
    _cancelButton.hidden = !working;
}
- (BOOL)prepareScope {
    _startTime = 0;
    _endTime = 0;
    if (_range.selectedSegmentIndex == 0) {
        NSCalendar *calendar = NSCalendar.currentCalendar;
        NSDate *date = _datePicker.date;
        NSDate *start = [calendar startOfDayForDate:date];
        NSDate *next = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
        if (!start || !next) { [self displayError:@"日期无效，请重新选择。"]; return NO; }
        _startTime = (long long)start.timeIntervalSince1970;
        _endTime = (long long)next.timeIntervalSince1970;
        NSDateFormatter *fmt = [NSDateFormatter new];
        fmt.dateFormat = @"yyyy-MM-dd";
        _scopeTitle = [NSString stringWithFormat:@"指定日期（%@）", [fmt stringFromDate:date]];
    } else {
        _scopeTitle = @"全部聊天记录";
    }
    return YES;
}
- (void)readStatistics { [self beginReadAndAnalyze:NO]; }
- (void)confirmAnalysis {
    if (_working) return;
    _customQuestion = axs_wechatgpt_trimmed(_question.text ?: @"");
    if (!_customQuestion.length) _customQuestion = @"分析主要话题、双方态度与待办事项。";
    if (_statsReady && [_signature isEqualToString:[self currentSignature]]) {
        [self startAnalysis];
    } else {
        [self beginReadAndAnalyze:YES];
    }
}
- (void)beginReadAndAnalyze:(BOOL)analyze {
    if (_working || ![self prepareScope]) return;
    ++_serial;
    _analyzeAfterRead = analyze;
    _signature = [self currentSignature];
    _statsReady = NO;
    _scanComplete = NO;
    _records = [NSMutableDictionary dictionary];
    _snapshot = @[];
    _pages = 0; _rawReturned = 0;
    _cursorID = 0; _cursorTime = 0;
    _stats.hidden = NO;
    _stats.text = [NSString stringWithFormat:@"正在统计：%@",_scopeTitle];
    _progress.text = @"正在读取聊天记录…";
    [self hideAnalysisResult];
    [self setWorking:YES];
    [self scheduleNextPageForSerial:_serial];
}
- (void)scheduleNextPageForSerial:(NSUInteger)serial {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (serial != self->_serial || !self->_working) return;
        [self fetchNextPageForSerial:serial];
    });
}
- (void)fetchNextPageForSerial:(NSUInteger)serial {
    if (serial != _serial) return;
    NSUInteger pageLimit = kAxsWeChatGPTAnalysisPageSize;
    NSDictionary *page = [AxsWeChatGPTWeChatBridge historyPageForSession:_session limit:pageLimit fromID:_cursorID fromTime:_cursorTime];
    NSString *error = page[@"error"];
    if (error.length) { [self endReadCompleted:NO note:error]; return; }
    ++_pages;
    NSUInteger rawCount = [page[@"rawCount"] unsignedIntegerValue];
    _rawReturned += rawCount;
    NSUInteger before = _records.count;
    for (NSDictionary *record in page[@"messages"] ?: @[]) {
        long long stamp = [record[@"timestamp"] longLongValue];
        if (_startTime > 0 && (stamp < _startTime || stamp >= _endTime)) continue;
        NSString *key = record[@"key"];
        if (key.length && !_records[key]) _records[key] = record;
    }
    NSString *progress = [NSString stringWithFormat:
        @"已读取 %lu 页，返回 %lu 条，统计 %lu 条",
        (unsigned long)_pages, (unsigned long)_rawReturned, (unsigned long)_records.count];
    _progress.text = progress;
    if (rawCount == 0) { [self endReadCompleted:YES note:@""]; return; }
    long long earliest = [page[@"fromTime"] longLongValue];
    long long oldestID = [page[@"fromID"] longLongValue];
    if (_startTime > 0 && earliest > 0 && earliest < _startTime) {
        [self endReadCompleted:YES note:@""]; return;
    }
    // Some builds may cap the returned page below our requested size.
    // If the native LeftCount reports more, continue even on a short page.
    // -1 means the pointer did not provide a usable remaining count.
    long long remaining = [page[@"leftCount"] longLongValue];
    if (remaining == 0 || (rawCount < pageLimit && remaining < 0)) {
        [self endReadCompleted:YES note:@""]; return;
    }
    if (_rawReturned >= kAxsWeChatGPTAnalysisSafetyRecords) {
        [self endReadCompleted:NO note:@"达到 100000 条安全保护上限；统计和分析仅涵盖已读取部分。"];
        return;
    }
    if (earliest <= 0 || (earliest == _cursorTime && oldestID == _cursorID)) {
        [self endReadCompleted:NO note:@"原生接口分页游标未向前推进；无法确认已读取全部历史。"];
        return;
    }
    // The selector's FromID / FromCreateTime ordering is private and varies
    // by release. Try the returned oldest local ID and timestamp; detect
    // repeated pages to avoid infinite loops or false "all" counts.
    if (_pages > 1 && before == _records.count && _startTime == 0) {
        [self endReadCompleted:NO note:@"分页没有新增记录，可能是接口不支持该游标；结果不完整。"];
        return;
    }
    _cursorID = oldestID;
    _cursorTime = earliest;
    [self scheduleNextPageForSerial:serial];
}
- (void)endReadCompleted:(BOOL)complete note:(NSString *)note {
    _scanComplete = complete;
    _snapshot = [[_records allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long x=[a[@"timestamp"] longLongValue], y=[b[@"timestamp"] longLongValue];
        if (x != y) return x<y ? NSOrderedAscending:NSOrderedDescending;
        long long ai=[a[@"localID"] longLongValue], bi=[b[@"localID"] longLongValue];
        return ai<bi ? NSOrderedAscending:(ai>bi ? NSOrderedDescending:NSOrderedSame);
    }];
    NSUInteger mine=0, other=0, textCount=0;
    NSMutableDictionary<NSString *, NSNumber *> *categoryCounts=[NSMutableDictionary dictionary];
    for (NSDictionary *record in _snapshot) {
        NSString *who = record[@"direction"];
        if ([who isEqualToString:@"mine"]) ++mine;
        else if ([who isEqualToString:@"other"]) ++other;
        // Direction-unknown records stay in the total, but are not
        // attributed to either party and have no dedicated UI row.
        if ([record[@"content"] isKindOfClass:NSString.class] && [record[@"content"] length]) ++textCount;
        NSString *category = [record[@"category"] isKindOfClass:NSString.class] ? record[@"category"] : @"other";
        categoryCounts[category] = @([categoryCounts[category] unsignedIntegerValue]+1);
    }
    NSUInteger (^tally)(NSString *) = ^NSUInteger(NSString *key) {
        return [categoryCounts[key] unsignedIntegerValue];
    };
    _statsReady = YES;
    _stats.text = [NSString stringWithFormat:
        @"消息总数：%lu 条\n我发送：%lu 条\n%@：%lu 条\n\n"
         @"文字：%lu 条\n图片：%lu 条\n视频：%lu 条\n转账：%lu 条\n红包：%lu 条\n小程序链接：%lu 条\n"
         @"网页链接：%lu 条\n语音：%lu 条\n表情：%lu 条\n文件：%lu 条\n其他：%lu 条\n"
         @"可提取文字：%lu 条",
        (unsigned long)_snapshot.count, (unsigned long)mine,
        _isGroup ? @"其他群成员" : @"对方发送", (unsigned long)other,
        (unsigned long)tally(@"text"), (unsigned long)tally(@"image"),
        (unsigned long)tally(@"video"), (unsigned long)tally(@"transfer"),
        (unsigned long)tally(@"redPacket"), (unsigned long)tally(@"miniProgram"),
        (unsigned long)tally(@"link"), (unsigned long)tally(@"voice"),
        (unsigned long)tally(@"sticker"), (unsigned long)tally(@"file"),
        (unsigned long)(tally(@"appOther") + tally(@"other") + tally(@"location") +
                         tally(@"quote") + tally(@"forwardedChat")),
        (unsigned long)textCount];
    _progress.text = complete ? @"读取完成" :
        (note.length ? [@"读取未完成：" stringByAppendingString:note] : @"读取未完成");
    [self setWorking:NO];
    if (_analyzeAfterRead) {
        _analyzeAfterRead = NO;
        if (!_snapshot.count) [self displayError:@"此范围没有读取到可分析的聊天消息，请检查日期和分页诊断。"];
        else [self startAnalysis];
    }
}
- (NSArray<NSString *> *)buildChunks {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm";
    NSMutableArray<NSString *> *chunks = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSDictionary *r in _snapshot) {
        // A non-text message contributes a type placeholder, never invented
        // visual/audio content or a hidden transfer amount.
        NSString *content = r[@"analysisText"];
        if (![content isKindOfClass:NSString.class] || !content.length) continue;
        NSString *who = r[@"direction"];
        NSString *speaker = [who isEqualToString:@"mine"] ? @"我" :
            ([who isEqualToString:@"other"] ? (_isGroup ? @"其他群成员" : @"对方") : @"方向待确认");
        if (_isGroup && [who isEqualToString:@"other"]) {
            NSString *sender = [r[@"sender"] isKindOfClass:NSString.class] ? r[@"sender"] : @"";
            if (sender.length && sender.length < 160)
                speaker = [NSString stringWithFormat:@"群成员 %@", sender];
        }
        NSString *date = [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:[r[@"timestamp"] longLongValue]]] ?: @"时间未知";
        NSString *line = [NSString stringWithFormat:@"[%@] %@：%@%@\n", date, speaker, content,
            [r[@"truncated"] boolValue] ? @"（此条过长，已截断）" : @""];
        if (current.length && current.length+line.length > kAxsWeChatGPTAnalysisChunkChars) {
            [chunks addObject:[current copy]];
            [current setString:@""];
        }
        [current appendString:line];
    }
    if (current.length) [chunks addObject:[current copy]];
    return chunks;
}
- (void)startAnalysis {
    if (_working || !_statsReady) return;
    _customQuestion = axs_wechatgpt_trimmed(_question.text ?: @"");
    if (!_customQuestion.length) _customQuestion = @"分析主要话题、双方态度与待办事项。";
    _chunks = [self buildChunks];
    if (!_chunks.count) { [self displayError:@"该范围没有可供分析的聊天记录。"];
        return; }
    ++_serial;
    _chunkIndex = 0; _partialSummary = @"";
    [self setWorking:YES];
    [self hideAnalysisResult];
    _progress.text = @"正在请求 AI 分析…";
    [self analyzeNextChunkForSerial:_serial];
}
- (void)analyzeNextChunkForSerial:(NSUInteger)serial {
    if (serial != _serial) return;
    if (_chunks.count == 1 || _chunkIndex >= _chunks.count) {
        [self requestFinalResultForSerial:serial];
        return;
    }
    NSString *chunk = _chunks[_chunkIndex];
    _progress.text = [NSString stringWithFormat:@"AI 正在整理第 %lu / %lu 段聊天（较长记录分段分析）",
        (unsigned long)(_chunkIndex+1),(unsigned long)_chunks.count];
    NSString *question = [NSString stringWithFormat:
        @"请继续更新对聊天记录的事实摘要。之前摘要：\n%@\n\n新增聊天记录：\n%@\n\n"
         @"保留重要话题、时间、双方表态、待办事项、矛盾与待核实之处；不捏造信息；摘要控制在约2000汉字内。",
        _partialSummary.length ? _partialSummary : @"（首次）", chunk];
    [[AxsWeChatGPTClient shared] askForAnalysisWithMessages:@[
        @{ @"role":@"system", @"content":@"你是严谨的聊天记录分析助手。将分段对话累积为可靠的阶段摘要，避免把我的话误当对方的话。" },
        @{ @"role":@"user", @"content":question }
    ] completion:^(NSString *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (serial != self->_serial) return;
            if (error || !response.length) {
                self->_progress.text = [NSString stringWithFormat:@"第 %lu 段摘要失败：%@",
                    (unsigned long)(self->_chunkIndex+1), error.localizedDescription ?: @"无返回内容"];
                [self setWorking:NO]; return;
            }
            self->_partialSummary = [response copy];
            ++self->_chunkIndex;
            [self analyzeNextChunkForSerial:serial];
        });
    }];
}
- (void)requestFinalResultForSerial:(NSUInteger)serial {
    if (serial != _serial) return;
    _progress.text = @"AI 正在生成最终分析…";
    NSString *history = _chunks.count == 1 ? _chunks.firstObject : _partialSummary;
    NSString *status = _scanComplete ? @"已完整遍历所选范围" : @"由于分页或安全保护限制，仅包含已读部分，不能当成全部历史";
    NSString *question = [NSString stringWithFormat:
        @"聊天范围：%@\n读取状态：%@\n%@\n\n用户的分析问题：%@\n\n%@：\n%@\n\n"
         @"请用中文明确回答分析问题，严格区分我和对方。方括号内的图片/视频/语音/转账/红包等只表示消息类型和出现次数，不代表已读取媒体内容、支付金额或交易结果。若历史不完整请说明结论只针对已读部分。",
        _scopeTitle, status, _stats.text ?: @"", _customQuestion ?: @"请分析聊天记录", 
        _chunks.count == 1 ? @"原始聊天" : @"逐段累计的聊天摘要", history ?: @""];
    [[AxsWeChatGPTClient shared] askForAnalysisWithMessages:@[
        @{ @"role":@"system", @"content":@"你是微信聊天记录分析助手，引用对话时要精确区分“我”“对方”和方向待确认的消息；无法确认方向时不要猜测。" },
        @{ @"role":@"user", @"content":question }
    ] completion:^(NSString *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (serial != self->_serial) return;
            if (error || !response.length) {
                self->_progress.text = [NSString stringWithFormat:@"分析失败：%@",
                    error.localizedDescription ?: @"AI 没有返回分析内容"];
                [self hideAnalysisResult];
            } else {
                self->_answer.text = response;
                self->_answerTitle.hidden = NO;
                self->_answer.hidden = NO;
                self->_progress.text = @"分析完成";
            }
            [self setWorking:NO];
        });
    }];
}
- (void)cancelTask {
    ++_serial;
    _analyzeAfterRead = NO;
    [self setWorking:NO];
    _progress.text = @"已停止后续分页或忽略尚未完成的 AI 请求。";
}
@end

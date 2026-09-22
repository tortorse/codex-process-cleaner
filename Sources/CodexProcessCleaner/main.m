#import <Cocoa/Cocoa.h>
#import <signal.h>
#import <unistd.h>

typedef NS_ENUM(NSInteger, Safety) { Recommended, Review, Protected };

@interface RawProcess : NSObject
@property pid_t pid, ppid; @property uid_t uid; @property long long rss;
@property double cpu; @property NSInteger elapsed;
@property(copy) NSString *exe, *command;
@end
@implementation RawProcess @end

@interface ProcessItem : NSObject
@property pid_t pid; @property long long rss; @property double cpu; @property NSInteger elapsed;
@property(copy) NSString *exe, *command, *reason, *threadId; @property Safety safety; @property BOOL selected;
@end
@implementation ProcessItem
- (NSString *)name { if([self.command.lowercaseString containsString:@"skycomputeruseclient"])return @"SkyComputerUseClient"; return self.exe.lastPathComponent.length ? self.exe.lastPathComponent : self.exe; }
- (NSString *)memory { return [NSByteCountFormatter stringFromByteCount:self.rss * 1024 countStyle:NSByteCountFormatterCountStyleMemory]; }
- (NSString *)age {
    if (_elapsed >= 86400) return [NSString stringWithFormat:@"%ld天", _elapsed / 86400];
    if (_elapsed >= 3600) return [NSString stringWithFormat:@"%ld小时", _elapsed / 3600];
    if (_elapsed >= 60) return [NSString stringWithFormat:@"%ld分钟", _elapsed / 60];
    return [NSString stringWithFormat:@"%ld秒", _elapsed];
}
- (NSString *)status { return _safety == Recommended ? @"建议关闭" : (_safety == Review ? @"手动判断" : @"必须保留"); }
@end

static NSInteger elapsedSeconds(NSString *text) {
    NSInteger days = 0; NSString *clock = text; NSRange dash = [text rangeOfString:@"-"];
    if (dash.location != NSNotFound) { days = [[text substringToIndex:dash.location] integerValue]; clock = [text substringFromIndex:dash.location + 1]; }
    NSArray *p = [clock componentsSeparatedByString:@":"];
    if (p.count == 3) return days * 86400 + [p[0] integerValue] * 3600 + [p[1] integerValue] * 60 + [p[2] integerValue];
    if (p.count == 2) return days * 86400 + [p[0] integerValue] * 60 + [p[1] integerValue];
    return days * 86400;
}

@interface Scanner : NSObject
- (NSArray<ProcessItem *> *)scan:(NSError **)error;
@end

@implementation Scanner
- (NSArray<ProcessItem *> *)demo {
    NSArray *rows = @[
      @[@48211,@438400,@18420,@0.1,@"/usr/local/bin/vite",@"vite --host 127.0.0.1 --port 5173",@(Recommended),@"Codex 示例任务 demo-a1b2… 启动；父进程已结束，仍在后台运行"],
      @[@51302,@176128,@4380,@0.0,@"/opt/homebrew/bin/postgres",@"postgres -D .data",@(Recommended),@"Codex 示例任务 demo-c3d4… 启动；父进程已结束，仍在后台运行"],
      @[@52519,@92672,@620,@0.4,@"/usr/bin/python3",@"python3 tools/local_preview.py",@(Review),@"仍属于 Codex 示例任务 demo-e5f6…；关闭可能中断正在进行的工作"],
      @[@52901,@64512,@98,@0.2,@"/path/to/project/bin/worker",@"./bin/worker --watch",@(Review),@"仍属于 Codex 示例任务 demo-e5f6…；关闭可能中断正在进行的工作"]];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *r in rows) { ProcessItem *p=[ProcessItem new]; p.pid=[r[0] intValue];p.rss=[r[1] longLongValue];p.elapsed=[r[2] integerValue];p.cpu=[r[3] doubleValue];p.exe=r[4];p.command=r[5];p.safety=[r[6] integerValue];p.reason=r[7];p.selected=p.safety==Recommended;[out addObject:p]; }
    return out;
}
- (NSArray<RawProcess *> *)raw:(NSError **)error {
    FILE *stream=popen("/bin/ps -axo 'pid=,ppid=,uid=,rss=,%cpu=,etime=,ucomm=,args=' 2>/dev/null", "r");
    if (!stream) { if(error)*error=[NSError errorWithDomain:@"CodexProcessGuard" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法启动系统进程检查。"}]; return nil; }
    NSMutableData *processData=[NSMutableData data]; char buffer[8192]; size_t length=0;
    while((length=fread(buffer,1,sizeof(buffer),stream))>0)[processData appendBytes:buffer length:length];
    pclose(stream);
    NSString *output=[[NSString alloc] initWithData:processData encoding:NSUTF8StringEncoding];
    if (!output) { if(error)*error=[NSError errorWithDomain:@"CodexProcessGuard" code:2 userInfo:@{NSLocalizedDescriptionKey:@"系统返回的进程信息无法读取。"}];return nil; }
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+([0-9.]+)\\s+([^\\s]+)\\s+([^\\s]+)\\s+(.+)$" options:0 error:nil];
    NSMutableArray *items=[NSMutableArray array];
    [output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop){
        NSTextCheckingResult *m=[re firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];if(!m||m.numberOfRanges!=9)return;
        NSString *(^f)(NSInteger)=^NSString*(NSInteger i){return [line substringWithRange:[m rangeAtIndex:i]];};
        RawProcess *p=[RawProcess new];p.pid=f(1).intValue;p.ppid=f(2).intValue;p.uid=f(3).intValue;p.rss=f(4).longLongValue;p.cpu=f(5).doubleValue;p.elapsed=elapsedSeconds(f(6));p.exe=f(7);p.command=f(8);[items addObject:p];
    }]; return items;
}
- (NSDictionary<NSNumber *,NSString *> *)markedThreads:(NSError **)error {
    FILE *stream=popen("/bin/ps eww -axo 'pid=,command=' 2>/dev/null", "r");
    if(!stream){if(error)*error=[NSError errorWithDomain:@"CodexProcessGuard" code:3 userInfo:@{NSLocalizedDescriptionKey:@"无法读取 Codex 任务标记。"}];return nil;}
    NSMutableData *data=[NSMutableData data];char buffer[16384];size_t length=0;while((length=fread(buffer,1,sizeof(buffer),stream))>0)[data appendBytes:buffer length:length];pclose(stream);
    NSString *output=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];if(!output){if(error)*error=[NSError errorWithDomain:@"CodexProcessGuard" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Codex 任务标记无法读取。"}];return nil;}
    NSMutableDictionary *threads=[NSMutableDictionary dictionary];NSString *marker=@"CODEX_THREAD_ID=";
    [output enumerateLinesUsingBlock:^(NSString *line,BOOL *stop){
        NSRange markerRange=[line rangeOfString:marker];if(markerRange.location==NSNotFound)return;
        NSScanner *scanner=[NSScanner scannerWithString:line];NSInteger pid=0;if(![scanner scanInteger:&pid]||pid<=0)return;
        NSUInteger start=NSMaxRange(markerRange),end=start;NSCharacterSet *space=NSCharacterSet.whitespaceAndNewlineCharacterSet;
        while(end<line.length&&![space characterIsMember:[line characterAtIndex:end]])end++;
        if(end>start)threads[@(pid)]=[line substringWithRange:NSMakeRange(start,end-start)];
    }];return threads;
}
- (NSArray<ProcessItem *> *)scan:(NSError **)error {
    if([NSProcessInfo.processInfo.arguments containsObject:@"--demo"])return [self demo];
    NSArray *raw=[self raw:error];if(!raw)return nil;NSDictionary *marked=[self markedThreads:error];if(!marked)return nil;
    NSMutableDictionary *map=[NSMutableDictionary dictionary];for(RawProcess*p in raw)map[@(p.pid)]=p;
    NSString *(^threadForPID)(pid_t)=^NSString*(pid_t pid){NSMutableSet*seen=[NSMutableSet set];pid_t current=pid;for(int i=0;i<60;i++){NSString*thread=marked[@(current)];if(thread.length)return thread;RawProcess*p=map[@(current)];if(!p||p.ppid<=0||[seen containsObject:@(current)])return nil;[seen addObject:@(current)];current=p.ppid;}return nil;};
    BOOL (^isOwnTree)(pid_t)=^BOOL(pid_t pid){pid_t current=pid;NSMutableSet*seen=[NSMutableSet set];for(int i=0;i<60;i++){if(current==getpid())return YES;RawProcess*p=map[@(current)];if(!p||p.ppid<=0||[seen containsObject:@(current)])return NO;[seen addObject:@(current)];current=p.ppid;}return NO;};
    BOOL (^isDetached)(pid_t,NSString*)=^BOOL(pid_t pid,NSString*thread){pid_t current=pid;NSMutableSet*seen=[NSMutableSet set];for(int i=0;i<60;i++){RawProcess*p=map[@(current)];if(!p||p.ppid<=1)return YES;NSString*parentThread=threadForPID(p.ppid);if(![parentThread isEqualToString:thread])return NO;if([seen containsObject:@(current)])return NO;[seen addObject:@(current)];current=p.ppid;}return NO;};
    NSMutableArray *result=[NSMutableArray array];
    for(RawProcess*r in raw){
        NSString*thread=threadForPID(r.pid);if(!thread.length||r.uid!=getuid()||r.pid==getpid()||isOwnTree(r.pid)||r.elapsed<5)continue;
        NSString*s=r.command.lowercaseString,*n=r.exe.lastPathComponent.lowercaseString;
        BOOL transient=[n isEqualToString:@"ps"]||[n isEqualToString:@"perl"]||[s containsString:@"codexprocesscleaner"]||[s containsString:@"ps eww -axo"];
        BOOL infrastructure=([n isEqualToString:@"codex"]&&([s containsString:@" app-server"]||[s containsString:@" sandbox "]))||[s containsString:@"codex-code-mode-host"]||[s containsString:@"codex (renderer)"]||[s containsString:@"codex (service)"]||[s containsString:@"browser_crashpad"];
        if(transient||infrastructure)continue;
        ProcessItem*p=[ProcessItem new];p.pid=r.pid;p.rss=r.rss;p.cpu=r.cpu;p.elapsed=r.elapsed;p.exe=r.exe;p.command=r.command;p.threadId=thread;
        NSString*shortThread=thread.length>8?[NSString stringWithFormat:@"%@…",[thread substringToIndex:8]]:thread;BOOL detached=isDetached(r.pid,thread);
        if(detached&&r.elapsed>=3600&&r.cpu<2.0){p.safety=Recommended;p.reason=[NSString stringWithFormat:@"Codex 任务 %@ 启动；父进程已结束，仍在后台运行",shortThread];p.selected=YES;}
        else if(detached){p.safety=Review;p.reason=[NSString stringWithFormat:@"Codex 任务 %@ 启动；已脱离父进程，请确认是否仍需使用",shortThread];}
        else{p.safety=Review;p.reason=[NSString stringWithFormat:@"仍属于 Codex 任务 %@；关闭可能中断正在进行的工作",shortThread];}
        [result addObject:p];
    }
    [result sortUsingComparator:^NSComparisonResult(ProcessItem*a,ProcessItem*b){if(a.safety!=b.safety)return a.safety<b.safety?NSOrderedAscending:NSOrderedDescending;return a.rss>b.rss?NSOrderedAscending:NSOrderedDescending;}];return result;
}
@end

@interface AppDelegate : NSObject<NSApplicationDelegate,NSTableViewDataSource,NSTableViewDelegate>
@property(strong)NSWindow*window;@property(strong)NSTableView*table;@property(strong)NSMutableArray<ProcessItem*>*items;
@property(strong)NSTextField*memoryMetric,*recommendMetric,*countMetric,*message,*selectedText,*updatedText,*emptyTitle,*emptySubtitle;
@property(strong)NSButton*closeButton,*closeAllButton,*filterToggle,*autoToggle,*refreshButton,*selectRecommendedButton,*clearButton;
@property(strong)NSProgressIndicator*spinner;@property(strong)NSView*emptyView;@property(strong)NSTimer*timer;@property BOOL scanning;
@end

@implementation AppDelegate
static NSTextField *label(NSString *text,CGFloat size,NSFontWeight weight){NSTextField*l=[NSTextField labelWithString:text];l.font=[NSFont systemFontOfSize:size weight:weight];return l;}
- (NSTextField*)metric:(NSString*)value caption:(NSString*)caption {NSTextField*v=label(value,19,NSFontWeightSemibold);v.font=[NSFont monospacedDigitSystemFontOfSize:19 weight:NSFontWeightSemibold];v.alignment=NSTextAlignmentRight;NSTextField*c=label(caption,11,NSFontWeightRegular);c.textColor=NSColor.secondaryLabelColor;c.alignment=NSTextAlignmentRight;NSStackView*s=[NSStackView stackViewWithViews:@[v,c]];s.orientation=NSUserInterfaceLayoutOrientationVertical;s.alignment=NSLayoutAttributeTrailing;s.spacing=3;return v;}
- (void)applicationDidFinishLaunching:(NSNotification*)note {
    self.items=[NSMutableArray array];
    self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,980,680) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Codex 进程清理器";self.window.minSize=NSMakeSize(860,560);self.window.titlebarAppearsTransparent=YES;[self.window center];NSView*root=self.window.contentView;

    NSTextField*t=label(@"Codex 进程清理器",27,NSFontWeightBold),*sub=label(@"查找 Codex 项目任务启动后仍在运行的程序，不限于 Node.js 或 Python。",13,NSFontWeightRegular);sub.textColor=NSColor.secondaryLabelColor;
    NSStackView*titles=[NSStackView stackViewWithViews:@[t,sub]];titles.orientation=NSUserInterfaceLayoutOrientationVertical;titles.alignment=NSLayoutAttributeLeading;titles.spacing=6;
    self.memoryMetric=[self metric:@"0 MB" caption:@"相关内存"];self.recommendMetric=[self metric:@"0" caption:@"建议关闭"];self.countMetric=[self metric:@"0" caption:@"相关程序"];
    NSStackView*metrics=[NSStackView stackViewWithViews:@[self.memoryMetric.superview,self.recommendMetric.superview,self.countMetric.superview]];metrics.spacing=24;
    NSStackView*header=[NSStackView stackViewWithViews:@[titles,[NSView new],metrics]];header.orientation=NSUserInterfaceLayoutOrientationHorizontal;header.alignment=NSLayoutAttributeTop;header.spacing=18;
    [titles setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];[metrics setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.filterToggle=[NSButton checkboxWithTitle:@"只看可关闭" target:self action:@selector(filter:)];self.filterToggle.toolTip=@"隐藏必须保留的程序";
    self.autoToggle=[NSButton checkboxWithTitle:@"每 5 秒刷新" target:self action:@selector(autoRefresh:)];self.autoToggle.state=NSControlStateValueOn;
    self.updatedText=label(@"尚未检查",11,NSFontWeightRegular);self.updatedText.textColor=NSColor.tertiaryLabelColor;
    self.spinner=[[NSProgressIndicator alloc]init];self.spinner.style=NSProgressIndicatorStyleSpinning;self.spinner.controlSize=NSControlSizeSmall;self.spinner.displayedWhenStopped=NO;
    self.refreshButton=[NSButton buttonWithTitle:@"立即刷新" target:self action:@selector(refresh:)];self.refreshButton.toolTip=@"重新读取当前进程";
    NSStackView*toolbar=[NSStackView stackViewWithViews:@[self.filterToggle,self.autoToggle,self.updatedText,[NSView new],self.spinner,self.refreshButton]];toolbar.orientation=NSUserInterfaceLayoutOrientationHorizontal;toolbar.alignment=NSLayoutAttributeCenterY;toolbar.spacing=12;

    self.table=[NSTableView new];self.table.delegate=self;self.table.dataSource=self;self.table.rowHeight=68;self.table.allowsMultipleSelection=NO;self.table.allowsEmptySelection=YES;self.table.usesAlternatingRowBackgroundColors=NO;
    NSArray*cols=@[@[@"pick",@"",@42],@[@"process",@"程序",@190],@[@"status",@"建议",@90],@[@"reason",@"说明与启动命令",@375],@[@"memory",@"占用 · 时间 · CPU",@220]];
    for(NSArray*c in cols){NSTableColumn*x=[[NSTableColumn alloc]initWithIdentifier:c[0]];x.title=c[1];x.width=[c[2] doubleValue];BOOL flexible=[c[0] isEqualToString:@"memory"];x.minWidth=flexible?170:([c[0] isEqualToString:@"reason"]?300:42);x.resizingMask=NSTableColumnUserResizingMask|(flexible?NSTableColumnAutoresizingMask:0);[self.table addTableColumn:x];}
    self.table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    NSScrollView*scroll=[NSScrollView new];scroll.documentView=self.table;scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;

    NSImageView*emptyIcon=[[NSImageView alloc]initWithFrame:NSMakeRect(0,0,36,36)];emptyIcon.image=[NSImage imageWithSystemSymbolName:@"checkmark.shield" accessibilityDescription:@"未发现程序"];
    emptyIcon.contentTintColor=NSColor.tertiaryLabelColor;[emptyIcon.widthAnchor constraintEqualToConstant:36].active=YES;[emptyIcon.heightAnchor constraintEqualToConstant:36].active=YES;
    self.emptyTitle=label(@"没有相关程序",15,NSFontWeightSemibold);self.emptyTitle.alignment=NSTextAlignmentCenter;
    self.emptySubtitle=label(@"Codex 项目任务启动后仍在运行的程序会显示在这里。",12,NSFontWeightRegular);self.emptySubtitle.textColor=NSColor.secondaryLabelColor;self.emptySubtitle.alignment=NSTextAlignmentCenter;
    NSStackView*emptyStack=[NSStackView stackViewWithViews:@[emptyIcon,self.emptyTitle,self.emptySubtitle]];emptyStack.orientation=NSUserInterfaceLayoutOrientationVertical;emptyStack.alignment=NSLayoutAttributeCenterX;emptyStack.spacing=8;
    self.emptyView=emptyStack;self.emptyView.hidden=YES;

    self.message=label(@"正在读取 Codex 启动的程序…",12,NSFontWeightRegular);self.message.textColor=NSColor.secondaryLabelColor;self.message.lineBreakMode=NSLineBreakByTruncatingTail;
    self.selectedText=label(@"",12,NSFontWeightMedium);
    self.selectRecommendedButton=[NSButton buttonWithTitle:@"选择建议项" target:self action:@selector(selectRecommended:)];self.selectRecommendedButton.enabled=NO;
    self.clearButton=[NSButton buttonWithTitle:@"清除选择" target:self action:@selector(clear:)];self.clearButton.enabled=NO;
    self.closeButton=[NSButton buttonWithTitle:@"关闭所选程序" target:self action:@selector(closeSelected:)];self.closeButton.enabled=NO;
    self.closeAllButton=[NSButton buttonWithTitle:@"全部关闭…" target:self action:@selector(closeAll:)];self.closeAllButton.contentTintColor=NSColor.systemRedColor;self.closeAllButton.enabled=NO;
    NSStackView*actions=[NSStackView stackViewWithViews:@[self.message,[NSView new],self.selectedText,self.selectRecommendedButton,self.clearButton,self.closeButton,self.closeAllButton]];actions.orientation=NSUserInterfaceLayoutOrientationHorizontal;actions.alignment=NSLayoutAttributeCenterY;actions.spacing=9;

    for(NSView*v in @[header,toolbar,scroll,self.emptyView,actions]){v.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:v];}
    [NSLayoutConstraint activateConstraints:@[[header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],[header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],[header.topAnchor constraintEqualToAnchor:root.topAnchor constant:22],[toolbar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18],[toolbar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18],[toolbar.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:18],[toolbar.heightAnchor constraintEqualToConstant:34],[scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:8],[scroll.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-1],[self.emptyView.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],[self.emptyView.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor constant:-8],[actions.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18],[actions.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18],[actions.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-14],[actions.heightAnchor constraintEqualToConstant:38],[self.message.widthAnchor constraintLessThanOrEqualToConstant:330],[metrics.widthAnchor constraintGreaterThanOrEqualToConstant:290]]];
    [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[self refreshSelecting:YES];self.timer=[NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
}
- (NSArray*)visible {if(self.filterToggle.state!=NSControlStateValueOn)return self.items;return[self.items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ProcessItem*p,NSDictionary*b){return p.safety!=Protected;}]];}
- (void)refreshSelecting:(BOOL)select {
    if(self.scanning)return;self.scanning=YES;self.message.stringValue=@"正在检查…";self.refreshButton.enabled=NO;[self.spinner startAnimation:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError*e=nil;NSArray*found=[[Scanner new]scan:&e];dispatch_async(dispatch_get_main_queue(),^{
        self.scanning=NO;self.refreshButton.enabled=YES;[self.spinner stopAnimation:nil];
        if(!found){self.message.stringValue=e.localizedDescription?:@"检查失败。";self.updatedText.stringValue=@"检查失败";return;}
        NSMutableSet*old=[NSMutableSet set];for(ProcessItem*p in self.items)if(p.selected)[old addObject:@(p.pid)];self.items=[found mutableCopy];
        for(ProcessItem*p in self.items)if([old containsObject:@(p.pid)]||(select&&p.safety==Recommended))p.selected=YES;
        NSDateFormatter*formatter=[NSDateFormatter new];formatter.dateFormat=@"HH:mm:ss";self.updatedText.stringValue=[NSString stringWithFormat:@"更新于 %@",[formatter stringFromDate:NSDate.date]];
        self.message.stringValue=self.items.count?[NSString stringWithFormat:@"已检查 %ld 个任务进程。",self.items.count]:@"没有发现 Codex 项目任务留下的进程。";
        [self.table reloadData];[self update];
    });});
}
- (void)update {
    long long total=0,selected=0;NSInteger rec=0,count=0,closeable=0;
    for(ProcessItem*p in self.items){total+=p.rss;if(p.safety==Recommended)rec++;if(p.safety!=Protected)closeable++;if(p.selected){selected+=p.rss;count++;}}
    self.memoryMetric.stringValue=[NSByteCountFormatter stringFromByteCount:total*1024 countStyle:NSByteCountFormatterCountStyleMemory];self.recommendMetric.stringValue=[NSString stringWithFormat:@"%ld",rec];self.countMetric.stringValue=[NSString stringWithFormat:@"%ld",self.items.count];
    self.selectedText.stringValue=count?[NSString stringWithFormat:@"已选 %ld 个 · 约 %@",count,[NSByteCountFormatter stringFromByteCount:selected*1024 countStyle:NSByteCountFormatterCountStyleMemory]]:@"";
    self.closeButton.enabled=count>0;self.clearButton.enabled=count>0;self.selectRecommendedButton.enabled=rec>0;self.closeAllButton.enabled=closeable>0;
    NSArray*shown=self.visible;self.emptyView.hidden=shown.count>0;
    if(!self.emptyView.hidden){BOOL filtered=self.filterToggle.state==NSControlStateValueOn&&self.items.count>0;self.emptyTitle.stringValue=filtered?@"没有符合筛选条件的程序":@"没有任务进程";self.emptySubtitle.stringValue=filtered?@"关闭“只看可关闭”即可查看其他任务进程。":@"Codex 项目任务启动后仍在运行的程序会显示在这里。";}
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)tv{return self.visible.count;}
- (NSView*)tableView:(NSTableView*)tv viewForTableColumn:(NSTableColumn*)col row:(NSInteger)row {ProcessItem*p=self.visible[row];NSString*i=col.identifier;if([i isEqualToString:@"pick"]){NSButton*b=[NSButton checkboxWithTitle:@"" target:self action:@selector(check:)];b.tag=p.pid;b.state=p.selected;b.enabled=p.safety!=Protected;return b;}NSTextField*l=[NSTextField labelWithString:@""];l.maximumNumberOfLines=2;l.lineBreakMode=NSLineBreakByTruncatingTail;if([i isEqualToString:@"process"]){l.stringValue=[NSString stringWithFormat:@"%@\nPID %d",p.name,p.pid];l.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];}else if([i isEqualToString:@"status"]){l.stringValue=p.status;l.font=[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];l.textColor=p.safety==Recommended?NSColor.systemGreenColor:(p.safety==Review?NSColor.systemOrangeColor:NSColor.secondaryLabelColor);}else if([i isEqualToString:@"reason"]){l.stringValue=[NSString stringWithFormat:@"%@\n%@",p.reason,p.command];l.font=[NSFont systemFontOfSize:11];l.textColor=NSColor.secondaryLabelColor;l.toolTip=p.command;}else{l.stringValue=[NSString stringWithFormat:@"%@\n%@ · CPU %.1f%%",p.memory,p.age,p.cpu];l.font=[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];l.alignment=NSTextAlignmentLeft;}return l;}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {NSInteger row=self.table.selectedRow;if(row<0||row>=self.visible.count)return;ProcessItem*p=self.visible[row];if(p.safety!=Protected)p.selected=!p.selected;[self.table deselectAll:nil];[self.table reloadData];[self update];}
- (void)check:(NSButton*)b{for(ProcessItem*p in self.items)if(p.pid==b.tag&&p.safety!=Protected)p.selected=b.state==NSControlStateValueOn;[self update];}
- (void)filter:(id)x{[self.table reloadData];[self update];}- (void)refresh:(id)x{[self refreshSelecting:NO];}- (void)timerFired:(id)x{[self refreshSelecting:NO];}
- (void)autoRefresh:(NSButton*)b{[self.timer invalidate];self.timer=nil;if(b.state==NSControlStateValueOn)self.timer=[NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];}
- (void)selectRecommended:(id)x{for(ProcessItem*p in self.items)if(p.safety==Recommended)p.selected=YES;[self.table reloadData];[self update];}
- (void)clear:(id)x{for(ProcessItem*p in self.items)p.selected=NO;[self.table reloadData];[self update];}
- (void)closeAll:(id)x{NSInteger count=0;long long memory=0;for(ProcessItem*p in self.items)if(p.safety!=Protected){count++;memory+=p.rss;}if(!count)return;NSAlert*alert=[NSAlert new];alert.alertStyle=NSAlertStyleCritical;alert.messageText=[NSString stringWithFormat:@"关闭全部 %ld 个可关闭程序？",count];alert.informativeText=[NSString stringWithFormat:@"预计涉及 %@ 内存。“手动判断”项目也会关闭，正在运行的 Codex 任务可能中断；Codex 需要时可能再次启动这些程序。不会关闭 Codex 主程序和当前界面。",[NSByteCountFormatter stringFromByteCount:memory*1024 countStyle:NSByteCountFormatterCountStyleMemory]];[alert addButtonWithTitle:@"全部关闭"];[alert addButtonWithTitle:@"取消"];[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSAlertFirstButtonReturn)return;for(ProcessItem*p in self.items)p.selected=p.safety!=Protected;[self.table reloadData];[self update];[self closeSelected:nil];}];}
- (void)closeSelected:(id)x{NSInteger ok=0,fail=0;for(ProcessItem*p in self.items){if(!p.selected||p.safety==Protected)continue;if(kill(p.pid,SIGTERM)==0)ok++;else fail++;p.selected=NO;}self.message.stringValue=fail?[NSString stringWithFormat:@"已请求关闭 %ld 个；%ld 个未能关闭。",ok,fail]:[NSString stringWithFormat:@"已请求关闭 %ld 个程序；仍在使用的程序可能会重新出现。",ok];[self update];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.9*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self refreshSelecting:NO];});}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender{return YES;}
@end

static AppDelegate *applicationDelegate;
int main(int argc,const char*argv[]){@autoreleasepool{NSApplication*app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyRegular];applicationDelegate=[AppDelegate new];app.delegate=applicationDelegate;[app run];}return 0;}

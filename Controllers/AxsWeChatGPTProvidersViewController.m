#import "AxsWeChatGPTProvidersViewController.h"

#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTPrivate.h"
#import "AxsWeChatGPTProviderEditorViewController.h"

@implementation AxsWeChatGPTProvidersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AI接口";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(axs_wechatgpt_addProvider)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)axs_wechatgpt_addProvider {
    [self.navigationController
        pushViewController:[[AxsWeChatGPTProviderEditorViewController alloc] initWithProvider:nil]
                  animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return (NSInteger)[[AxsWeChatGPTConfig shared] providers].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"点一行设为当前服务商，点行尾按钮编辑，左滑删除。密钥保存在当前 App 的钥匙串。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NSDictionary *provider = [[AxsWeChatGPTConfig shared] providers][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                    reuseIdentifier:nil];
    BOOL active = [provider[@"id"] isEqualToString:[[AxsWeChatGPTConfig shared] activeProviderID]];
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", active ? @"✓ " : @"", provider[@"name"]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", provider[@"model"], provider[@"url"]];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<NSDictionary *> *providers = [[AxsWeChatGPTConfig shared] providers];
    if (indexPath.row >= (NSInteger)providers.count) return;
    [[AxsWeChatGPTConfig shared] selectProviderWithID:providers[indexPath.row][@"id"]];
    [tableView reloadData];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NSArray<NSDictionary *> *providers = [[AxsWeChatGPTConfig shared] providers];
    if (indexPath.row >= (NSInteger)providers.count) return;
    [self.navigationController
        pushViewController:[[AxsWeChatGPTProviderEditorViewController alloc]
            initWithProvider:providers[indexPath.row]]
                  animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
                                    forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    NSArray<NSDictionary *> *providers = [[AxsWeChatGPTConfig shared] providers];
    if (indexPath.row >= (NSInteger)providers.count) return;
    [[AxsWeChatGPTConfig shared] removeProviderWithID:providers[indexPath.row][@"id"]];
    [tableView reloadData];
}

@end

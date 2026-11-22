#import "AxsWeChatGPTModelPickerViewController.h"

@implementation AxsWeChatGPTModelPickerViewController {
    NSArray<NSString *> *_models;
    NSArray<NSString *> *_filtered;
    NSString *_selected;
    void (^_choose)(NSString *);
    UISearchController *_search;
}

- (instancetype)initWithModels:(NSArray<NSString *> *)models
                      selected:(NSString *)selected
                     selection:(void (^)(NSString *model))selection {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _models = [models copy];
        _filtered = _models;
        _selected = [selected copy];
        _choose = [selection copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择模型";
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = _search;
    self.definesPresentationContext = YES;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (!query.length) {
        _filtered = _models;
    } else {
        _filtered = [_models filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id value, NSDictionary *bindings) {
            (void)bindings;
            return [value isKindOfClass:NSString.class] &&
                [value rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return (NSInteger)_filtered.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                    reuseIdentifier:nil];
    NSString *name = _filtered[indexPath.row];
    cell.textLabel.text = name;
    cell.accessoryType = [name isEqualToString:_selected]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)_filtered.count) return;
    NSString *model = _filtered[indexPath.row];
    if (_choose) _choose(model);
    [self.navigationController popViewControllerAnimated:YES];
}

@end

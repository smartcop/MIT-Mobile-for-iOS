#import "MITNewsRecentSearchController.h"
#import "MITNewsModelController.h"
#import "MITNewsRecentSearchQuery.h"

@interface MITNewsRecentSearchController () <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate>

@property (strong, nonatomic) MITNewsModelController *modelController;
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic, readwrite) UIActionSheet *confirmSheet;
@property (nonatomic, weak) IBOutlet UIBarButtonItem *clearButtonItem;
@property (nonatomic, strong) NSString *filterString;
@property (nonatomic, strong) NSArray *recentResults;

@end

@implementation MITNewsRecentSearchController

#pragma mark - properties

- (MITNewsModelController *)modelController
{
    if(!_modelController) {
        MITNewsModelController *modelController = [[MITNewsModelController alloc] init];
        _modelController = modelController;
    }
    return _modelController;
}

#pragma mark - Recent Add/Remove methods

- (IBAction)clearRecentsButtonClicked:(id)sender
{
    NSString *cancelButtonTitle = NSLocalizedString(@"Cancel", @"Cancel button title");
    NSString *clearAllRecentsButtonTitle = NSLocalizedString(@"Clear All Recents", @"Clear All Recents button title");
    
    // If the user taps the Clear Recents button, present an action sheet to confirm.

    self.confirmSheet = [[UIActionSheet alloc] initWithTitle:@"" delegate:self cancelButtonTitle:cancelButtonTitle destructiveButtonTitle:clearAllRecentsButtonTitle otherButtonTitles:nil];
    [self.confirmSheet showInView:self.view];
}

- (void)addRecentSearchItem:(NSString *)searchTerm
{
    NSError *error;
    [self.modelController addRecentSearchItem:searchTerm error:error];
    self.recentResults = [self.modelController recentSearchItemswithFilterString:self.filterString];

    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.tableView reloadData];
    }];
    self.clearButtonItem.enabled = YES;
}

- (void)filterResultsUsingString:(NSString *)filterString
{
    self.recentResults = [self.modelController recentSearchItemswithFilterString:filterString];
    self.filterString = filterString;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.tableView reloadData];
    }];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    if (buttonIndex == 0) {
        NSError *error;
        [self.modelController clearRecentSearchesWithError:error];
        self.recentResults = nil;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.tableView reloadData];
        }];
        self.clearButtonItem.enabled = NO;
    }
    self.confirmSheet = nil;
}

#pragma mark - Table View methods

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    
    
    MITNewsRecentSearchQuery *query = self.recentResults[indexPath.row];
    cell.textLabel.text = query.text;
    
    return cell;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.recentResults count];
}

#pragma mark - View lifecycle

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.recentResults = [self.modelController recentSearchItemswithFilterString:self.filterString];
    if ([self.recentResults count] == 0) {
        self.clearButtonItem.enabled = NO;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

#import "MITLibrariesYourAccountViewController.h"
#import "MITLibrariesWebservices.h"
#import "MITLibrariesUser.h"

#import "MITLibrariesLoansViewController.h"
#import "MITLibrariesHoldsViewController.h"
#import "MITLibrariesFinesViewController.h"

typedef NS_ENUM(NSInteger, MITLibrariesYourAccountSection) {
    MITLibrariesYourAccountSectionLoans = 0,
    MITLibrariesYourAccountSectionFines,
    MITLibrariesYourAccountSectionHolds
};

@interface MITLibrariesYourAccountViewController () <MITLibrariesUserRefreshDelegate>

@property (nonatomic, strong) UISegmentedControl *loansHoldsFinesSegmentedControl;

@property (nonatomic, strong) MITLibrariesLoansViewController *loansViewController;
@property (nonatomic, strong) MITLibrariesHoldsViewController *holdsViewController;
@property (nonatomic, strong) MITLibrariesFinesViewController *finesViewController;

@property (nonatomic, strong) MITLibrariesUser *user;

@end

@implementation MITLibrariesYourAccountViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self refreshUserData];
    
    [self setupViewControllers];
    
    [self setupToolbar];
}

- (void)refreshUserData
{
    [MITLibrariesWebservices getUserWithCompletion:^(MITLibrariesUser *user, NSError *error) {
        self.user = user;
        
        [self refreshViewControllers];
    }];
}

- (void)setupToolbar
{
    self.loansHoldsFinesSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Loans", @"Fines", @"Holds"]];
    [self.loansHoldsFinesSegmentedControl addTarget:self action:@selector(showSelectedViewController) forControlEvents:UIControlEventValueChanged];
    [self.loansHoldsFinesSegmentedControl setWidth:90.0 forSegmentAtIndex:0];
    [self.loansHoldsFinesSegmentedControl setWidth:90.0 forSegmentAtIndex:1];
    [self.loansHoldsFinesSegmentedControl setWidth:90.0 forSegmentAtIndex:2];
    
    [self.loansHoldsFinesSegmentedControl setSelectedSegmentIndex:0];
    
    UIBarButtonItem *segmentedControlItem = [[UIBarButtonItem alloc] initWithCustomView:self.loansHoldsFinesSegmentedControl];
    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[flexibleSpace, segmentedControlItem, flexibleSpace];
    [self.navigationController setToolbarHidden:NO];
}

- (void)setupViewControllers
{
    self.loansViewController = [[MITLibrariesLoansViewController alloc] init];
    self.holdsViewController = [[MITLibrariesHoldsViewController alloc] init];
    self.finesViewController = [[MITLibrariesFinesViewController alloc] init];
    
    self.loansViewController.refreshDelegate =
    self.holdsViewController.refreshDelegate =
    self.finesViewController.refreshDelegate = self;
    
    self.loansViewController.view.frame =
    self.holdsViewController.view.frame =
    self.finesViewController.view.frame = self.view.bounds;
    
    [self addChildViewController:self.loansViewController];
    [self addChildViewController:self.holdsViewController];
    [self addChildViewController:self.finesViewController];
    
    [self.view addSubview:self.loansViewController.view];
    [self.view addSubview:self.holdsViewController.view];
    [self.view addSubview:self.finesViewController.view];
}

- (void)showSelectedViewController
{
    switch (self.loansHoldsFinesSegmentedControl.selectedSegmentIndex) {
        case 0:
            [self showLoansViewController];
            break;
        case 1:
            [self showFinesViewController];
            break;
        case 2:
            [self showHoldsViewController];
            break;
        default:
            break;
    }
}

- (void)showLoansViewController
{
    self.holdsViewController.view.hidden =
    self.finesViewController.view.hidden = YES;
    
    self.loansViewController.view.hidden = NO;
}

- (void)showHoldsViewController
{
    self.loansViewController.view.hidden =
    self.finesViewController.view.hidden = YES;
    
    self.holdsViewController.view.hidden = NO;
}

- (void)showFinesViewController
{
    self.holdsViewController.view.hidden =
    self.loansViewController.view.hidden = YES;
    
    self.finesViewController.view.hidden = NO;
}

- (void)refreshViewControllers
{
    self.loansViewController.items = self.user.loans;
    self.holdsViewController.items = self.user.holds;
    self.finesViewController.items = self.user.fines;
    
    [self showSelectedViewController];
}

@end

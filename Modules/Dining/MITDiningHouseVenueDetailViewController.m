#import "MITDiningHouseVenueDetailViewController.h"
#import "MITDiningHouseVenueInfoViewController.h"
#import "MITDiningHouseMealSelectionView.h"
#import "MITDiningFilterViewController.h"
#import "MITDiningHouseVenueInfoCell.h"
#import "Foundation+MITAdditions.h"
#import "MITDiningMenuItemCell.h"
#import "MITDiningFiltersCell.h"
#import "MITDiningHouseVenue.h"
#import "MITDiningMenuItem.h"
#import "MITDiningHouseDay.h"
#import "MITDiningMeal.h"

typedef NS_ENUM(NSInteger, kMITVenueDetailSection) {
    kMITVenueDetailSectionInfo,
    kMITVenueDetailSectionMenu
};

static NSString *const kMITDiningHouseVenueInfoCell = @"MITDiningHouseVenueInfoCell";
static NSString *const kMITDiningMenuItemCell = @"MITDiningMenuItemCell";
static NSString *const kMITDiningFiltersCell = @"MITDiningFiltersCell";

@interface MITDiningHouseVenueDetailViewController () <MITDiningHouseVenueInfoCellDelegate, MITDiningFilterDelegate>

@property (nonatomic, strong) MITDiningHouseDay *currentlyDisplayedDay;
@property (nonatomic, strong) MITDiningMeal *currentlyDisplayedMeal;

@property (nonatomic, strong) NSArray *currentlyDisplayedItems;
@property (nonatomic, strong) NSArray *sortedMeals;
@property (nonatomic, strong) NSSet *filters;

@property (nonatomic, strong) NSDate *currentlyDisplayedDate;

@property (nonatomic, strong) MITDiningHouseMealSelectionView *mealSelectionView;

@end

@implementation MITDiningHouseVenueDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupNavigationBar];
    
    self.currentlyDisplayedDate = [NSDate date];
    
    self.currentlyDisplayedDay = [self.houseVenue houseDayForDate:self.currentlyDisplayedDate];
    self.currentlyDisplayedMeal = [self.currentlyDisplayedDay bestMealForDate:self.currentlyDisplayedDate];
    
    self.filters = [NSSet set];
    [self updateCurrentlyDisplayedMeals];
    
    [self setupTableView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setupNavigationBar
{
    UIBarButtonItem *filterButton = [[UIBarButtonItem alloc] initWithTitle:@"Filters" style:UIBarButtonItemStylePlain target:self action:@selector(showFilterSelector)];
    self.navigationItem.rightBarButtonItem = filterButton;
}

#pragma mark - Table view data source

- (void)setupTableView
{
    UINib *cellNib = [UINib nibWithNibName:kMITDiningHouseVenueInfoCell bundle:nil];
    [self.tableView registerNib:cellNib forCellReuseIdentifier:kMITDiningHouseVenueInfoCell];
    
    cellNib = [UINib nibWithNibName:kMITDiningMenuItemCell bundle:nil];
    [self.tableView registerNib:cellNib forCellReuseIdentifier:kMITDiningMenuItemCell];
    
    cellNib = [UINib nibWithNibName:kMITDiningFiltersCell bundle:nil];
    [self.tableView registerNib:cellNib forCellReuseIdentifier:kMITDiningFiltersCell];
    
    self.mealSelectionView = [[[NSBundle mainBundle] loadNibNamed:@"MITDiningHouseMealSelectionView" owner:nil options:nil] firstObject];
    [self.mealSelectionView.nextMealButton addTarget:self action:@selector(nextMealPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.mealSelectionView.previousMealButton addTarget:self action:@selector(previousMealPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.mealSelectionView setMeal:self.currentlyDisplayedMeal];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return section == kMITVenueDetailSectionMenu ? 64.0 : 0.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case kMITVenueDetailSectionInfo:
            return [MITDiningHouseVenueInfoCell heightForHouseVenue:self.houseVenue tableViewWidth:self.tableView.frame.size.width];
            break;
        case kMITVenueDetailSectionMenu:
            if ([self hasFiltersApplied]) {
                if (indexPath.row == 0) {
                    return [MITDiningFiltersCell heightForFilters:self.filters tableViewWidth:self.tableView.frame.size.width];
                } else {
                    return [MITDiningMenuItemCell heightForMenuItem:self.currentlyDisplayedItems[indexPath.row - 1] tableViewWidth:self.tableView.frame.size.width];
                }
            }
            else {
                return [MITDiningMenuItemCell heightForMenuItem:self.currentlyDisplayedItems[indexPath.row] tableViewWidth:self.tableView.frame.size.width];
            }
            break;
        default:
            return 0;
            break;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case kMITVenueDetailSectionInfo:
            return 1;
            break;
        case kMITVenueDetailSectionMenu:
            if ([self hasFiltersApplied]) {
                return self.currentlyDisplayedItems.count + 1;
            }
            else {
                return self.currentlyDisplayedItems.count;
            }
            break;
        default:
            return 0;
            break;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kMITVenueDetailSectionInfo:
            return nil;
            break;
        case kMITVenueDetailSectionMenu:
            return self.mealSelectionView;
            break;
        default:
            return nil;
            break;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case kMITVenueDetailSectionInfo:
            return [self venueInfoCell];
            break;
        case kMITVenueDetailSectionMenu:
            if ([self hasFiltersApplied] && indexPath.row == 0) {
                return [self filtersCell];
            } else {
                return [self menuItemCellForIndexPath:indexPath];
            }
            break;
        default:
            return [[UITableViewCell alloc] init];
            break;
    }
}

- (UITableViewCell *)venueInfoCell
{
    MITDiningHouseVenueInfoCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kMITDiningHouseVenueInfoCell];
    [cell setHouseVenue:self.houseVenue];
    cell.delegate = self;
    return cell;
}

- (UITableViewCell *)menuItemCellForIndexPath:(NSIndexPath *)indexPath
{
    MITDiningMenuItemCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kMITDiningMenuItemCell];
    NSInteger index = [self hasFiltersApplied] ? indexPath.row - 1 : indexPath.row;
    [cell setMenuItem:self.currentlyDisplayedItems[index]];
    
    return cell;
}

- (UITableViewCell *)filtersCell
{
    MITDiningFiltersCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kMITDiningFiltersCell];
    [cell setFilters:self.filters];
    
    return cell;
}

#pragma mark - Cell Delegate
- (void)infoCellDidPressInfoButton:(MITDiningHouseVenueInfoCell *)infoCell
{
    MITDiningHouseVenueInfoViewController *infoVC = [[MITDiningHouseVenueInfoViewController alloc] init];
    infoVC.houseVenue = self.houseVenue;
    
    [self.navigationController pushViewController:infoVC animated:YES];
}


#pragma mark - Meal Selection View

- (void)updateMealSelection
{
    self.mealSelectionView.meal = self.currentlyDisplayedMeal;
    self.currentlyDisplayedDay = self.currentlyDisplayedMeal.houseDay;
    self.currentlyDisplayedDate = self.self.currentlyDisplayedDay.date;
    
    self.mealSelectionView.nextMealButton.enabled = ([self.sortedMeals indexOfObject:self.currentlyDisplayedMeal] + 1 < self.sortedMeals.count);
    self.mealSelectionView.previousMealButton.enabled = ([self.sortedMeals indexOfObject:self.currentlyDisplayedMeal] > 0);
    
    [self updateCurrentlyDisplayedMeals];
}

- (void)nextMealPressed:(id)sender
{
    self.currentlyDisplayedMeal = self.sortedMeals[[self.sortedMeals indexOfObject:self.currentlyDisplayedMeal] + 1];

    [self updateMealSelection];
}

- (void)previousMealPressed:(id)sender
{
   self.currentlyDisplayedMeal = self.sortedMeals[[self.sortedMeals indexOfObject:self.currentlyDisplayedMeal] - 1];
    
    [self updateMealSelection];
}

#pragma mark - Setters/Getters
- (void)setHouseVenue:(MITDiningHouseVenue *)houseVenue
{
    _houseVenue = houseVenue;
    self.title = self.houseVenue.name;
    self.currentlyDisplayedDate = [NSDate date];
    self.currentlyDisplayedDay = [self.houseVenue houseDayForDate:self.currentlyDisplayedDate];
    self.sortedMeals = nil; // Force Recalculation
    
    [self updateMealSelection];
}

- (NSArray *)sortedMeals
{
    if (!_sortedMeals) {
        _sortedMeals = [self.houseVenue sortedMealsInWeek];
    }
    return _sortedMeals;
}

#pragma mark - Filtering

- (void)showFilterSelector
{
    MITDiningFilterViewController *filterVC = [[MITDiningFilterViewController alloc] init];
    [filterVC setSelectedFilters:self.filters];
    filterVC.delegate = self;
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:filterVC] animated:YES completion:NULL];
}

- (void)applyFilters:(NSSet *)filters
{
    self.filters = filters;
    [self updateCurrentlyDisplayedMeals];
}

- (void)updateCurrentlyDisplayedMeals
{
    if (self.filters.count == 0) {
        self.currentlyDisplayedItems = [self.currentlyDisplayedMeal.items array];
    }
    else {
        NSMutableArray *filteredItems = [[NSMutableArray alloc] init];
        for (MITDiningMenuItem *item in self.currentlyDisplayedMeal.items) {
            if (item.dietaryFlags) {
                for (NSString *dietaryFlag in (NSArray *)item.dietaryFlags) {
                    if ([self.filters containsObject:dietaryFlag]) {
                        [filteredItems addObject:item];
                        break;
                    }
                }
            }
        }
        self.currentlyDisplayedItems = filteredItems;
    }
    [self.tableView reloadData];
}

- (BOOL)hasFiltersApplied
{
    return (self.filters.count > 0);
}

@end

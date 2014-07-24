#import "MITEventsHomeViewController.h"
#import "MITDayOfTheWeekCell.h"
#import "MITCalendarEventCell.h"
#import "MITCalendarDataManager.h"
#import "UIKit+MITAdditions.h"
#import "NSDate+MITAdditions.h"
#import "MITEventList.h"

static NSString *const kMITDayOfTheWeekCell = @"MITDayOfTheWeekCell";
static NSString *const kMITCalendarEventCell = @"MITCalendarEventCell";

@interface MITEventsHomeViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UITableViewDataSource, UITableViewDelegate>

@property (weak, nonatomic) IBOutlet UIView *dayPickerContainerView;
@property (weak, nonatomic) IBOutlet UICollectionView *dayPickerCollectionView;

@property (weak, nonatomic) IBOutlet UITableView *eventsListTableView;


@property (weak, nonatomic) UIView *navBarSeparatorView;

@property (nonatomic) CGFloat pageWidth;

@property (nonatomic, strong) NSDate *startDate;

@property (nonatomic, strong) MITEventList *activeEventList;
@property (nonatomic, strong) NSArray *activeEvents;

@property (nonatomic, strong) NSArray *datesArray;

@property (nonatomic, strong) NSDate *startOfDisplayedWeekDate;
@property (nonatomic, strong) NSDate *currentlyDisplayedDate;


@end

@implementation MITEventsHomeViewController

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
    
    self.currentlyDisplayedDate = [[NSDate date] beginningOfDay];
    [self updateDatesArray];

    [self setupExtendedNavBar];
    [self setupDayPickerCollectionView];
    [self setupEventsTableView];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    self.navBarSeparatorView.hidden = YES;
    
    self.startDate = [[NSDate date] beginningOfDay];
    
    [self registerForNotifications];
    
    [self loadActiveEventList];
    [self centerDayPickerCollectionView];
    
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.navBarSeparatorView.hidden = NO;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setupExtendedNavBar
{
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    
    self.navBarSeparatorView = [self findHairlineImageViewUnder:navigationBar];
    navigationBar.opaque = YES;
    navigationBar.translucent = NO;
    UIColor *navbarGrey = [UIColor colorWithRed:248.0/255.0 green:248.0/255.0 blue:248.0/255.0 alpha:1.0];
    [navigationBar setBarTintColor:navbarGrey];
    self.dayPickerContainerView.backgroundColor = navbarGrey;
    
}

- (void)registerForNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(calendarListLoaded:) name:kCalendarListsLoaded object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(calendarListLoadedFailed:) name:kCalendarListsFailedToLoad object:nil];
}

- (void)loadActiveEventList
{
    if (!self.activeEventList) {
		NSArray *lists = [[MITCalendarDataManager sharedManager] eventLists];
		if ([lists count]) {
			self.activeEventList = lists[0];
		}
	}
    [self reloadEvents];
    
}

- (void)reloadEvents
{
    [MITCalendarDataManager performEventsRequestForDate:self.currentlyDisplayedDate
                                             eventList:self.activeEventList completion:^(NSArray *events, NSError *error) {
                                                 if (events) {
                                                     self.activeEvents = events;
                                                     [self.eventsListTableView reloadData];
                                                 }
                                             }];
}
- (UIImageView *)findHairlineImageViewUnder:(UIView *)view {
    if ([view isKindOfClass:UIImageView.class] && view.bounds.size.height <= 1.0) {
        return (UIImageView *)view;
    }
    for (UIView *subview in view.subviews) {
        UIImageView *imageView = [self findHairlineImageViewUnder:subview];
        if (imageView) {
            return imageView;
        }
    }
    return nil;
}

- (void)setupDayPickerCollectionView
{
    self.dayPickerCollectionView.backgroundColor = [UIColor clearColor];
    
    UINib *cellNib = [UINib nibWithNibName:kMITDayOfTheWeekCell bundle:nil];
    [self.dayPickerCollectionView registerNib:cellNib forCellWithReuseIdentifier:kMITDayOfTheWeekCell];
    
    self.pageWidth = self.dayPickerCollectionView.frame.size.width;
}

- (void)setupEventsTableView
{
    UINib *cellNib = [UINib nibWithNibName:kMITCalendarEventCell bundle:nil];
    [self.eventsListTableView registerNib:cellNib forCellReuseIdentifier:kMITCalendarEventCell];
}

#pragma mark - Day of the week Collection View Datasource/Delegate

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return 24;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MITDayOfTheWeekCell *cell = [self.dayPickerCollectionView dequeueReusableCellWithReuseIdentifier:kMITDayOfTheWeekCell
                                                                                        forIndexPath:indexPath];
    

   [self configureCell:cell forIndexPath:indexPath];
    
    return cell;

}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    [self.dayPickerCollectionView deselectItemAtIndexPath:indexPath animated:NO];
    MITDayOfTheWeek dayOfTheWeek = indexPath.row  % 8;

    if (dayOfTheWeek == MITDayOfTheWeekOther) {
        NSLog(@"Present Date Picker");
    }
    else {
        [self daySelectedAtIndexPath:indexPath];
        [self updateDisplayedDay];
    }
        
}

#pragma mark - Tableview Datasource/Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.activeEvents count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MITCalendarEvent *event = self.activeEvents[indexPath.row];
    return [MITCalendarEventCell heightForEvent:event tableViewWidth:self.eventsListTableView.frame.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MITCalendarEventCell *cell = [self.eventsListTableView dequeueReusableCellWithIdentifier:kMITCalendarEventCell forIndexPath:indexPath];

    [cell setEvent:self.activeEvents[indexPath.row]];

    return cell;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (scrollView == self.dayPickerCollectionView) {
        [self updateDayPickerOffsetForInfiniteScrolling];
    }
}

- (void)updateDayPickerOffsetForInfiniteScrolling
{
    if (self.dayPickerCollectionView.contentOffset.x <= 0 ) {
        self.currentlyDisplayedDate = [self.currentlyDisplayedDate dateBySubtractingWeek];
        [self updateDisplayedDay];

    }
    else if (self.dayPickerCollectionView.contentOffset.x >= self.pageWidth * 2) {
        self.currentlyDisplayedDate = [self.currentlyDisplayedDate dateByAddingWeek];
        [self updateDisplayedDay];
    }
}

- (void)updateDisplayedDay
{
    [self reloadEvents];
    [self updateDatesArray];
    [self centerDayPickerCollectionView];

}

- (void)updateDatesArray
{
    NSMutableArray *newDatesArray = [[NSMutableArray alloc] init];

    NSDate *lastWeek = [self.currentlyDisplayedDate dateBySubtractingWeek];
    NSDate *nextWeek = [self.currentlyDisplayedDate dateByAddingWeek];
    
    [newDatesArray addObjectsFromArray:[lastWeek datesInWeek]];
    [newDatesArray addObjectsFromArray:[self.currentlyDisplayedDate datesInWeek]];
    [newDatesArray addObjectsFromArray:[nextWeek datesInWeek]];
    
    self.datesArray = newDatesArray;
}

- (void)centerDayPickerCollectionView
{
    [self.dayPickerCollectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:8 inSection:0]
                                         atScrollPosition:UICollectionViewScrollPositionLeft
                                                 animated:NO];
}

- (void)daySelectedAtIndexPath:(NSIndexPath *)indexPath
{
    self.currentlyDisplayedDate = [self dateForIndexPath:indexPath];
    for (MITDayOfTheWeekCell *cell in self.dayPickerCollectionView.visibleCells) {
        NSIndexPath *cellIndexPath = [self.dayPickerCollectionView indexPathForCell:cell];
        [self configureCell:cell forIndexPath:cellIndexPath];
    }
}

- (void)configureCell:(MITDayOfTheWeekCell *)cell  forIndexPath:(NSIndexPath *)indexPath
{
    cell.dayOfTheWeek = indexPath.row  % 8;
    
    if (cell.dayOfTheWeek == MITDayOfTheWeekOther) {
        cell.state = MITDayOfTheWeekStateSelected;
    }
    else {
        NSDate *cellDate = [self dateForIndexPath:indexPath];
        if ([cellDate isSameDayAsDate:self.currentlyDisplayedDate]) {
            cell.state = MITDayOfTheWeekStateSelected;
        }
        else {
            cell.state = MITDayOfTheWeekStateUnselected;
        }
        if ([cellDate isSameDayAsDate:[NSDate date]]){
            cell.state |= MITDayOfTheWeekStateToday;
        }
    }
}

- (NSDate *)dateForIndexPath:(NSIndexPath *)indexPath
{
    NSInteger adjustedIndex = indexPath.row;
    if (indexPath.row > 6) {
        adjustedIndex--;
    }
    if (indexPath.row > 14) {
        adjustedIndex--;
    }
    return self.datesArray[adjustedIndex];
}

- (void)calendarListLoaded:(NSNotification *)ntfn
{
    
}

- (void)calendarListLoadedFailed:(NSNotification *)ntfn
{
    
}

@end

#import <objc/runtime.h>
#import "MITNewsViewController.h"
#import "MITCoreData.h"
#import "MITNewsCategory.h"
#import "MITNewsStory.h"
#import "MITNewsImage.h"
#import "MITNewsImageRepresentation.h"

#import "MITNewsStoryViewController.h"
#import "MITNewsCategoryViewController.h"
#import "MITNewsModelController.h"
#import "MITNewsStoryCell.h"
#import "MITDisclosureHeaderView.h"
#import "UIImageView+WebCache.h"

#import "MITNewsConstants.h"
#import "MITAdditions.h"
#import "UIScrollView+SVPullToRefresh.h"

static NSUInteger MITNewsDefaultNumberOfFeaturedStories = 5;
static NSString* const MITNewsCachedLayoutCellsAssociatedObjectKey = @"MITNewsCachedLayoutCells_NSMutableDictionary";

@interface MITNewsViewController () <NSFetchedResultsControllerDelegate,UISearchDisplayDelegate,UISearchBarDelegate>
@property (nonatomic) BOOL needsNavigationItemUpdate;

@property (nonatomic,getter = isUpdating) BOOL updating;
@property (nonatomic,strong) NSDate *lastUpdated;

@property (nonatomic,strong) NSMapTable *gestureRecognizersByView;
@property (nonatomic,strong) NSMapTable *categoriesByGestureRecognizer;
@property (nonatomic,strong) NSMapTable *cachedStoriesByCategory;
@property (nonatomic,strong) NSMapTable *sizingCellsByIdentifier;

@property (nonatomic,strong) NSFetchedResultsController *featuredStoriesFetchedResultsController;
@property (nonatomic,strong) NSFetchedResultsController *categoriesFetchedResultsController;

#pragma mark Searching
@property (nonatomic,getter = isSearching) BOOL searching;
@property (nonatomic,strong) NSString *searchQuery;
@property (nonatomic,strong) NSMutableArray *searchResults;

@property (nonatomic,readonly) MITNewsStory *selectedStory;

- (void)loadFetchedResultsControllers;

- (MITNewsStoryCell*)sizingCellForIdentifier:(NSString*)identifier;

#pragma mark Updating
- (void)beginUpdatingAnimated:(BOOL)animate;
- (void)endUpdatingAnimated:(BOOL)animate;
- (void)endUpdatingWithError:(NSError*)error animated:(BOOL)animate;
- (void)setToolbarString:(NSString*)string animated:(BOOL)animated;

- (IBAction)searchButtonTapped:(UIBarButtonItem*)sender;
- (IBAction)loadMoreFooterTapped:(id)sender;
@end

@interface MITNewsViewController (DynamicTableViewCellsShared)
#pragma mark private(-ish)
// I think these methods shouldn't require modification to be used
// in another class.
- (NSMutableDictionary*)_cachedLayoutCellsForTableView:(UITableView*)tableView;
- (UITableViewCell*)_tableView:(UITableView*)tableView dequeueReusableLayoutCellWithIdentifier:(NSString*)reuseIdentifier forIndexPath:(NSIndexPath*)indexPath;
- (NSInteger)_tableView:(UITableView*)tableView minimumHeightForRowAtIndexPath:(NSIndexPath*)indexPath;
- (void)_tableView:(UITableView*)tableView registerClass:(Class)nilOrClass forCellReuseIdentifier:(NSString*)cellReuseIdentifier;
- (void)_tableView:(UITableView*)tableView registerNib:(UINib*)nilOrNib forCellReuseIdentifier:(NSString*)cellReuseIdentifier;
@end

@interface MITNewsViewController (DynamicTableViewCells)
// You'll need to modify these for them to work in another class
// should be delegated out
- (NSInteger)_tableView:(UITableView *)tableView primitiveNumberOfRowsInSection:(NSInteger)section;
- (id)_tableView:(UITableView*)tableView representedObjectForRowAtIndexPath:(NSIndexPath*)indexPath;
- (void)_tableView:(UITableView*)tableView configureCell:(UITableViewCell*)cell forRowAtIndexPath:(NSIndexPath*)indexPath;
- (NSString*)_tableView:(UITableView*)tableView reuseIdentifierForRowAtIndexPath:(NSIndexPath*)indexPath;
@end


@implementation MITNewsViewController {
    CGPoint _contentOffsetToRestoreAfterSearching;
}

#pragma mark UI Element text attributes
+ (NSDictionary*)updateItemTextAttributes
{
    return @{NSFontAttributeName: [UIFont systemFontOfSize:[UIFont smallSystemFontSize]],
             NSForegroundColorAttributeName: [UIColor blackColor]};
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    return [self initWithNibName:nibNameOrNil bundle:nibBundleOrNil managedObjectContext:nil];
}


- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil managedObjectContext:(NSManagedObjectContext*)context
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _managedObjectContext = context;
    }

    return self;
}

#pragma mark Lifecycle
- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.numberOfStoriesPerCategory = 3;
    self.showFeaturedStoriesSection = YES;

    [self.tableView registerNib:[UINib nibWithNibName:@"NewsCategoryHeaderView" bundle:nil] forHeaderFooterViewReuseIdentifier:MITNewsCategoryHeaderIdentifier];
    
    [self _tableView:self.tableView registerNib:[UINib nibWithNibName:MITNewsStoryCellNibName bundle:nil] forCellReuseIdentifier:MITNewsStoryCellIdentifier];
    [self _tableView:self.tableView registerNib:[UINib nibWithNibName:MITNewsStoryNoDekCellNibName bundle:nil] forCellReuseIdentifier:MITNewsStoryNoDekCellIdentifier];
    [self _tableView:self.tableView registerNib:[UINib nibWithNibName:MITNewsStoryExternalCellNibName bundle:nil] forCellReuseIdentifier:MITNewsStoryExternalCellIdentifier];

    self.gestureRecognizersByView = [NSMapTable weakToWeakObjectsMapTable];
    self.categoriesByGestureRecognizer = [NSMapTable weakToStrongObjectsMapTable];
    self.sizingCellsByIdentifier = [NSMapTable strongToWeakObjectsMapTable];
    
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshControlWasTriggered:) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
}

- (void)viewWillAppear:(BOOL)animated
{
    [self loadFetchedResultsControllers];

    NSError *fetchError = nil;
    [self.featuredStoriesFetchedResultsController performFetch:&fetchError];
    if (fetchError) {
        DDLogWarn(@"[%@] error while executing fetch: %@",NSStringFromClass([self class]),fetchError);
    }

    fetchError = nil;
    [self.categoriesFetchedResultsController performFetch:&fetchError];
    if (fetchError) {
        DDLogWarn(@"[%@] error while executing fetch: %@",NSStringFromClass([self class]),fetchError);
    }

    [super viewWillAppear:animated];
    
    // Only make sure the toolbar is visible if we are not searching
    // otherwise, returning after viewing a story pops it up
    if (!self.isSearching) {
        [self.navigationController setToolbarHidden:NO animated:animated];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.lastUpdated) {
        __weak MITNewsViewController *weakSelf = self;
        [self performDataUpdate:^(NSError *error){
            MITNewsViewController *blockSelf = weakSelf;
            if (blockSelf) {
                [self.tableView reloadData];
            }
        }];
    } else {
        NSString *relativeDateString = [NSDateFormatter relativeDateStringFromDate:self.lastUpdated
                                                                            toDate:[NSDate date]];
        NSString *updateText = [NSString stringWithFormat:@"Updated %@",relativeDateString];
        [self setToolbarString:updateText animated:animated];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    UIViewController *destinationViewController = [segue destinationViewController];

    DDLogVerbose(@"Performing segue with identifier '%@'",[segue identifier]);

    if ([segue.identifier isEqualToString:@"showStoryDetail"]) {
        if ([destinationViewController isKindOfClass:[MITNewsStoryViewController class]]) {
            MITNewsStoryViewController *storyDetailViewController = (MITNewsStoryViewController*)destinationViewController;
            MITNewsStory *story = [self selectedStory];
            if (story) {
                NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
                managedObjectContext.parentContext = self.managedObjectContext;
                storyDetailViewController.managedObjectContext = managedObjectContext;
                storyDetailViewController.story = (MITNewsStory*)[managedObjectContext objectWithID:[story objectID]];
            }
        } else {
            DDLogWarn(@"unexpected class for segue %@. Expected %@ but got %@",segue.identifier,
                      NSStringFromClass([MITNewsStoryViewController class]),
                      NSStringFromClass([[segue destinationViewController] class]));
        }
    } else if ([segue.identifier isEqualToString:@"showCategoryDetail"]) {
        if ([destinationViewController isKindOfClass:[MITNewsCategoryViewController class]]) {
            MITNewsCategoryViewController *storiesViewController = (MITNewsCategoryViewController*)destinationViewController;

            UIGestureRecognizer *gestureRecognizer = (UIGestureRecognizer*)sender;
            MITNewsCategory *category = [self.categoriesByGestureRecognizer objectForKey:gestureRecognizer];

            NSManagedObjectContext *managedObjectContext = [[MITCoreDataController defaultController] mainQueueContext];
            storiesViewController.managedObjectContext = managedObjectContext;
            [storiesViewController setCategoryWithObjectID:[category objectID]];
        } else {
            DDLogWarn(@"unexpected class for segue %@. Expected %@ but got %@",segue.identifier,
                      NSStringFromClass([MITNewsCategoryViewController class]),
                      NSStringFromClass([[segue destinationViewController] class]));
        }
    } else {
        DDLogWarn(@"[%@] unknown segue '%@'",self,segue.identifier);
    }
}

#pragma mark Notifications
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark View Orientation
- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}


#pragma mark - Property Setters & Getters
- (NSManagedObjectContext*)managedObjectContext
{
    if (!_managedObjectContext) {
        DDLogWarn(@"[%@] A managed object context was not set before being added to the view hierarchy. The default main queue NSManaged object context will be used but this will be a fatal error in the future.",self);
        _managedObjectContext = [[[MIT_MobileAppDelegate applicationDelegate] coreDataController] mainQueueContext];
    }

    NSAssert(_managedObjectContext, @"[%@] failed to load a valid NSManagedObjectContext", NSStringFromClass([self class]));
    return _managedObjectContext;
}

#pragma mark - Managing states
#pragma mark Searching
- (void)beginSearchingAnimated:(BOOL)animated
{
    if (!self.isSearching) {
        self.searching = YES;
        
        _contentOffsetToRestoreAfterSearching = self.tableView.contentOffset;
        
        UISearchBar *searchBar = self.searchDisplayController.searchBar;
        searchBar.frame = CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 44.);
        [searchBar sizeToFit];
        self.tableView.tableHeaderView = searchBar;
        
        [UIView animateWithDuration:(animated ? 0.33 : 0)
                              delay:0.
                            options:UIViewAnimationCurveEaseOut
                         animations:^{
                             [self.tableView scrollRectToVisible:searchBar.frame animated:NO];
                         } completion:^(BOOL finished) {
                             if (finished) {
                                 [searchBar becomeFirstResponder];
                                 [self.navigationController setToolbarHidden:YES animated:NO];
                             }
                         }];
    }
}

- (void)willLoadResultsForSearchAnimated:(BOOL)animate
{
    if (self.searchDisplayController.isActive) {
        UITableView *tableView = self.searchDisplayController.searchResultsTableView;
        
        UIActivityIndicatorView *indicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [indicatorView startAnimating];
        tableView.tableHeaderView = indicatorView;
        [tableView reloadData];
        
        [tableView scrollRectToVisible:indicatorView.frame animated:animate];
    }
}

- (void)didLoadResultsForSearchWithError:(NSError*)error animated:(BOOL)animate
{
    if (self.searchDisplayController.isActive) {
        UITableView *tableView = self.searchDisplayController.searchResultsTableView;
        tableView.tableHeaderView = nil;
        [tableView reloadData];
    }
}

- (void)endSearchingAnimated:(BOOL)animated
{
    if (self.isSearching) {
        self.searching = NO;
        UISearchBar *searchBar = self.searchDisplayController.searchBar;
        
        [UIView animateWithDuration:(animated ? 0.33 : 0)
                              delay:0.
                            options:UIViewAnimationCurveEaseIn
                         animations:^{
                             CGPoint targetPoint = _contentOffsetToRestoreAfterSearching;
                             // Add in the search bar's height otherwise we will come up short
                             targetPoint.y += CGRectGetHeight(searchBar.frame);
                             [self.tableView setContentOffset:targetPoint animated:NO];
                             
                         } completion:^(BOOL finished) {
                             if (finished) {
                                 self.tableView.tableHeaderView = nil;
                                 
                                 // Now that the search bar is gone, correct out content offset to the
                                 // correct one.
                                 [self.tableView setContentOffset:_contentOffsetToRestoreAfterSearching animated:NO];
                                 [self.navigationController setToolbarHidden:NO animated:YES];
                                 
                                 self.searchResults = nil;
                                 _contentOffsetToRestoreAfterSearching = CGPointZero;
                                 self.searching = NO;
                             }
                         }];
    }
}

#pragma mark Updating
#pragma mark Updating
- (void)beginUpdatingAnimated:(BOOL)animate
{
    if (!self.isUpdating) {
        self.updating = YES;
        
        if (!self.isSearching) {
            [self.refreshControl beginRefreshing];
            [self setToolbarString:@"Updating..." animated:animate];
        }
    }
}

- (void)endUpdatingAnimated:(BOOL)animate
{
    [self endUpdatingWithError:nil animated:animate];
}

- (void)endUpdatingWithError:(NSError*)error animated:(BOOL)animate
{
    if (self.isUpdating) {
        if (!self.isSearching) {
            
            [self.featuredStoriesFetchedResultsController performFetch:nil];
            [self.categoriesFetchedResultsController performFetch:nil];
            
            
            if (!error) {
                self.lastUpdated = [NSDate date];
                
                NSString *relativeDateString = [NSDateFormatter relativeDateStringFromDate:self.lastUpdated
                                                                                    toDate:[NSDate date]];
                NSString *updateText = [NSString stringWithFormat:@"Updated %@",relativeDateString];
                [self setToolbarString:updateText animated:animate];
            } else {
                [self setToolbarString:@"Update Failed" animated:animate];
            }
            
            [self.refreshControl endRefreshing];
        }
        
        self.updating = NO;
    }
}

#pragma mark UI Helper
- (void)setToolbarString:(NSString*)string animated:(BOOL)animated
{
    UILabel *updatingLabel = [[UILabel alloc] init];
    updatingLabel.font = [UIFont systemFontOfSize:[UIFont smallSystemFontSize]];
    updatingLabel.text = string;
    updatingLabel.backgroundColor = [UIColor clearColor];
    [updatingLabel sizeToFit];
    
    UIBarButtonItem *updatingItem = [[UIBarButtonItem alloc] initWithCustomView:updatingLabel];
    [self setToolbarItems:@[[UIBarButtonItem flexibleSpace],updatingItem,[UIBarButtonItem flexibleSpace]] animated:animated];
}


#pragma mark - Responding to UI events
- (IBAction)tableSectionHeaderTapped:(UIGestureRecognizer *)gestureRecognizer
{
    MITNewsCategory *category = [self.categoriesByGestureRecognizer objectForKey:gestureRecognizer];

    if (category) {
        [self.managedObjectContext performBlockAndWait:^{
            MITNewsCategory *localCategory = (MITNewsCategory*)[self.managedObjectContext objectWithID:[category objectID]];
            DDLogVerbose(@"Recieved tap on section header for category with name '%@'",localCategory.name);
        }];

        [self performSegueWithIdentifier:@"showCategoryDetail" sender:gestureRecognizer];
    }

}

- (IBAction)searchButtonTapped:(UIBarButtonItem*)sender
{
    [self beginSearchingAnimated:YES];
}

- (IBAction)refreshControlWasTriggered:(UIRefreshControl*)sender
{    __weak MITNewsViewController *weakSelf = self;
    [self performDataUpdate:^(NSError *error){
        MITNewsViewController *blockSelf = weakSelf;
        if (blockSelf) {
            [blockSelf.tableView reloadData];
        }
    }];
}

#pragma mark Loading & updating, and retrieving data
- (void)loadFetchedResultsControllers
{
    // Featured fetched results controller
    if (self.showFeaturedStoriesSection && !self.featuredStoriesFetchedResultsController) {
        NSFetchRequest *featuredStories = [NSFetchRequest fetchRequestWithEntityName:[MITNewsStory entityName]];
        featuredStories.predicate = [NSPredicate predicateWithFormat:@"featured == YES"];
        featuredStories.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"publishedAt" ascending:NO],
                                            [NSSortDescriptor sortDescriptorWithKey:@"identifier" ascending:NO]];

        NSFetchedResultsController *fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:featuredStories
                                                                                                   managedObjectContext:self.managedObjectContext
                                                                                                     sectionNameKeyPath:nil
                                                                                                              cacheName:nil];
        fetchedResultsController.delegate = self;
        self.featuredStoriesFetchedResultsController = fetchedResultsController;
    }

    if (!self.categoriesFetchedResultsController) {
        NSFetchRequest *categories = [NSFetchRequest fetchRequestWithEntityName:[MITNewsCategory entityName]];
        categories.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"order" ascending:YES]];

        NSFetchedResultsController *fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:categories
                                                                                                   managedObjectContext:self.managedObjectContext
                                                                                                     sectionNameKeyPath:nil
                                                                                                              cacheName:nil];
        fetchedResultsController.delegate = self;
        self.categoriesFetchedResultsController = fetchedResultsController;
    }
}

- (void)performDataUpdate:(void (^)(NSError *error))completion
{
    if (!self.isUpdating) {
        [self beginUpdatingAnimated:YES];

        // Probably can be reimplemented some other way but, for now, this works.
        // Assumes that each of the blocks passed to the model controller below
        // will retain a strong reference to inFlightDataRequests even after this method
        // returns. When the final request completes and removes the last 'token'
        // from the in-flight request tracker, call our completion block.
        // All the callbacks should be on the main thread so race conditions should be a non-issue.
        NSHashTable *inFlightDataRequests = [NSHashTable weakObjectsHashTable];
        __weak MITNewsViewController *weakSelf = self;
        MITNewsModelController *modelController = [MITNewsModelController sharedController];

        [inFlightDataRequests addObject:MITNewsStoryFeaturedStoriesRequestToken];
        [modelController featuredStoriesWithOffset:0
                                             limit:self.numberOfStoriesPerCategory
                                        completion:^(NSArray* stories, MITResultsPager* pager, NSError* error) {
                                            MITNewsViewController *blockSelf = weakSelf;
                                            if (blockSelf) {
                                                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                                    [inFlightDataRequests removeObject:MITNewsStoryFeaturedStoriesRequestToken];
                                                    
                                                    if ([inFlightDataRequests count] == 0) {
                                                        [self endUpdatingWithError:error animated:YES];
                                                        if (error) {
                                                            if (completion) {
                                                                completion(error);
                                                            }
                                                        } else {
                                                            blockSelf.lastUpdated = [NSDate date];
                                                            if (completion) {
                                                                completion(nil);
                                                            }
                                                        }
                                                    }
                                                }];
                                            }
                                        }];

        [modelController categories:^(NSArray *categories, NSError *error) {
            [categories enumerateObjectsUsingBlock:^(MITNewsCategory *category, NSUInteger idx, BOOL *stop) {
                [inFlightDataRequests addObject:category];

                [modelController storiesInCategory:category.identifier
                                             query:nil
                                            offset:0
                                             limit:self.numberOfStoriesPerCategory
                                        completion:^(NSArray* stories, MITResultsPager* pager, NSError* error) {
                                            MITNewsViewController *blockSelf = weakSelf;
                                            if (blockSelf) {
                                                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                                    [inFlightDataRequests removeObject:category];

                                                    if ([inFlightDataRequests count] == 0) {
                                                        [self endUpdatingWithError:error animated:YES];
                                                        
                                                        if (error) {
                                                            if (completion) {
                                                                completion(error);
                                                            }
                                                        } else {
                                                            blockSelf.lastUpdated = [NSDate date];
                                                            if (completion) {
                                                                completion(nil);
                                                            }
                                                        }
                                                    }
                                                }];
                                            }
                                        }];
            }];
        }];
    }
}

- (void)loadSearchResultsForQuery:(NSString*)query loaded:(void (^)(NSError *error))completion
{
    if ([query length] == 0) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            self.searchQuery = nil;
            self.searchResults = nil;
            
            [self willLoadResultsForSearchAnimated:YES];
            
            if (completion) {
                completion(nil);
            }
            
            [self didLoadResultsForSearchWithError:nil animated:YES];
        }];
    } else if (![self.searchQuery isEqualToString:query]) {
        [self.searchResults removeAllObjects];
        self.searchQuery = query;
        
        [self willLoadResultsForSearchAnimated:YES];
        NSString *currentQuery = self.searchQuery;
        
        MITNewsModelController *modelController = [MITNewsModelController sharedController];
        __weak MITNewsViewController *weakSelf = self;
        [modelController storiesInCategory:nil
                                     query:query
                                    offset:0
                                     limit:20
                                completion:^(NSArray* stories, MITResultsPager* pager, NSError* error) {
                                    MITNewsViewController *blockSelf = weakSelf;
                                    if (blockSelf) {
                                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                            if (blockSelf.searchDisplayController.isActive && (blockSelf.searchQuery == currentQuery)) {
                                                if (error) {
                                                    blockSelf.searchResults = [[NSMutableArray alloc] init];
                                                } else {
                                                    blockSelf.searchResults = [[NSMutableArray alloc] initWithArray:stories];
                                                }
                                                
                                                [self didLoadResultsForSearchWithError:error animated:YES];

                                                if (completion) {
                                                    completion(error);
                                                }
                                            }
                                        }];
                                    }
                                }];
    }
}

- (NSArray*)storiesInCategory:(MITNewsCategory*)category
{
    if (!self.cachedStoriesByCategory) {
        self.cachedStoriesByCategory = [NSMapTable strongToStrongObjectsMapTable];
    }

    NSArray *cachedStories = [self.cachedStoriesByCategory objectForKey:[category objectID]];

    if (!cachedStories) {
        __block NSArray *stories = nil;
        NSArray *sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"publishedAt" ascending:NO],
                                     [NSSortDescriptor sortDescriptorWithKey:@"identifier" ascending:NO]];

        [self.managedObjectContext performBlockAndWait:^{
            MITNewsCategory *blockCategory = (MITNewsCategory*)[self.managedObjectContext objectWithID:[category objectID]];
            stories = [blockCategory.stories sortedArrayUsingDescriptors:sortDescriptors];
        }];

        [self.cachedStoriesByCategory setObject:stories forKey:[category objectID]];
        cachedStories = stories;
    }

    return cachedStories;
}

- (MITNewsStory*)selectedStory
{
    UITableView *tableView = nil;

    if (self.searchDisplayController.isActive) {
        tableView = self.searchDisplayController.searchResultsTableView;
    } else {
        tableView = self.tableView;
    }

    NSIndexPath* selectedIndexPath = [tableView indexPathForSelectedRow];
    return [self storyAtIndexPath:selectedIndexPath inTableView:tableView];
}

- (MITNewsStory*)storyAtIndexPath:(NSIndexPath*)indexPath inTableView:(UITableView*)tableView
{
    NSUInteger section = (NSUInteger)indexPath.section;
    NSUInteger row = (NSUInteger)indexPath.row;

    if (tableView == self.tableView) {
        MITNewsStory *story = nil;

        if (self.showFeaturedStoriesSection && (section == 0)) {
            story = [self.featuredStoriesFetchedResultsController objectAtIndexPath:indexPath];
        } else {
            if (self.showFeaturedStoriesSection) {
                section -= 1;
            }

            MITNewsCategory *sectionCategory = self.categoriesFetchedResultsController.fetchedObjects[section];
            NSArray *stories = [self storiesInCategory:sectionCategory];
            story = stories[row];
        }

        return story;
    } else if (tableView == self.searchDisplayController.searchResultsTableView) {
        if (indexPath.row < [self.searchResults count]) {
            return self.searchResults[row];
        } else {
            return nil;
        }
    } else {
        return nil;
    }
}

- (NSString*)tableViewCellIdentifierForStory:(MITNewsStory*)story
{
    __block NSString *identifier = nil;
    if (story) {
        [self.managedObjectContext performBlockAndWait:^{
            MITNewsStory *newsStory = (MITNewsStory*)[self.managedObjectContext objectWithID:[story objectID]];

            if ([newsStory.type isEqualToString:MITNewsStoryExternalType]) {
                identifier = MITNewsStoryExternalCellIdentifier;
            } else if ([newsStory.dek length])  {
                identifier = MITNewsStoryCellIdentifier;
            } else {
                identifier = MITNewsStoryNoDekCellIdentifier;
            }
        }];
    }

    return identifier;
}


- (MITNewsStoryCell*)sizingCellForIdentifier:(NSString *)identifier
{
    MITNewsStoryCell *sizingCell = [self.sizingCellsByIdentifier objectForKey:identifier];

    if (!sizingCell) {
        UINib *cellNib = nil;
        if ([identifier isEqualToString:MITNewsStoryCellIdentifier]) {
            cellNib = [UINib nibWithNibName:MITNewsStoryCellNibName bundle:nil];
        } else if ([identifier isEqualToString:MITNewsStoryNoDekCellIdentifier]) {
            cellNib = [UINib nibWithNibName:MITNewsStoryNoDekCellNibName bundle:nil];
        } else if ([identifier isEqualToString:MITNewsStoryExternalCellIdentifier]) {
            cellNib = [UINib nibWithNibName:MITNewsStoryExternalCellNibName bundle:nil];
        }

        sizingCell = [[cellNib instantiateWithOwner:sizingCell options:nil] firstObject];
        sizingCell.hidden = YES;
        sizingCell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        sizingCell.frame = CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 86.);
        [self.tableView addSubview:sizingCell];
        [self.sizingCellsByIdentifier setObject:sizingCell forKey:identifier];
    }

    return sizingCell;
}

#pragma mark - NSFetchedResultsController
- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    if (controller == self.categoriesFetchedResultsController) {
        [self.cachedStoriesByCategory removeAllObjects];
    }
}

#pragma mark - UITableView
#pragma mark UITableViewDelegate
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (tableView == self.tableView) {
        return 44.;
    } else if (self.searchDisplayController.searchResultsTableView) {
        return 44.;
    } else {
        return UITableViewAutomaticDimension;
    }
}

- (UIView*)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (tableView == self.tableView) {
        MITDisclosureHeaderView *headerView = (MITDisclosureHeaderView*)[tableView dequeueReusableHeaderFooterViewWithIdentifier:MITNewsCategoryHeaderIdentifier];

        if (self.showFeaturedStoriesSection && (section == 0)) {
            headerView.titleLabel.text = @"Featured Stories";
            headerView.accessoryView.hidden = YES;

            UIGestureRecognizer *recognizer = [self.gestureRecognizersByView objectForKey:headerView];
            if (recognizer) {
                [headerView removeGestureRecognizer:recognizer];
                [self.categoriesByGestureRecognizer removeObjectForKey:recognizer];
                [self.gestureRecognizersByView removeObjectForKey:headerView];
            }

            return headerView;
        } else {
            if (self.featuredStoriesFetchedResultsController) {
                section -= 1;
            }

            UIGestureRecognizer *recognizer = [self.gestureRecognizersByView objectForKey:headerView];
            if (!recognizer) {
                recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tableSectionHeaderTapped:)];
                [headerView addGestureRecognizer:recognizer];
            }

            // Keep track of the gesture recognizers we create so we can remove
            // them later
            [self.gestureRecognizersByView setObject:recognizer forKey:headerView];

            NSArray *categories = [self.categoriesFetchedResultsController fetchedObjects];
            [self.categoriesByGestureRecognizer setObject:categories[section] forKey:recognizer];

            __block NSString *categoryName = nil;
            [self.managedObjectContext performBlockAndWait:^{
                MITNewsCategory *category = (MITNewsCategory*)[self.managedObjectContext objectWithID:[categories[section] objectID]];
                categoryName = category.name;
            }];

            headerView.titleLabel.text = categoryName;
            headerView.accessoryView.hidden = NO;
            return headerView;
        }
    } else if (tableView == self.searchDisplayController.searchResultsTableView) {
        if (self.searchQuery) {
            UITableViewHeaderFooterView *headerView = (UITableViewHeaderFooterView*)[tableView dequeueReusableHeaderFooterViewWithIdentifier:@"NewsSearchHeader"];
            
            if (!headerView) {
                headerView = [[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:@"NewsSearchHeader"];
            }
            
            headerView.textLabel.text = [NSString stringWithFormat:@"results for '%@'",self.searchQuery];
            return  headerView;
        }
    }
    
    return nil;
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([cell isKindOfClass:[MITNewsStoryCell class]]) {
        MITNewsStoryCell *storyCell = (MITNewsStoryCell*)cell;
        [storyCell.storyImageView cancelCurrentImageLoad];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self _tableView:tableView minimumHeightForRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    id representedObject = [self _tableView:tableView representedObjectForRowAtIndexPath:indexPath];
    if (representedObject && [representedObject isKindOfClass:[MITNewsStory class]]) {
        [self performSegueWithIdentifier:@"showStoryDetail" sender:tableView];
    } else if (tableView == self.searchDisplayController.searchResultsTableView) {
        NSString *reuseIdentifier = [self _tableView:tableView reuseIdentifierForRowAtIndexPath:indexPath];
        if ([reuseIdentifier isEqualToString:MITNewsLoadMoreCellIdentifier]) {
            DDLogVerbose(@"Load more cell!");
            NSAssert(NO, @"needs to be implemented");
        }
    }
}

#pragma mark UITableViewDataSource
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == self.tableView) {
        NSInteger numberOfSections = 0;

        if (self.showFeaturedStoriesSection && self.featuredStoriesFetchedResultsController.fetchedObjects) {
            numberOfSections += 1;
        }

        numberOfSections += [self.categoriesFetchedResultsController.fetchedObjects count];
        return numberOfSections;
    } else if (tableView == self.searchDisplayController.searchResultsTableView) {
        return (self.searchResults ? 1 : 0);
    }

    return 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self _tableView:tableView primitiveNumberOfRowsInSection:section];
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *identifier = [self _tableView:tableView reuseIdentifierForRowAtIndexPath:indexPath];

    NSAssert(identifier,@"[%@] missing UITableViewCell identifier in %@",self,NSStringFromSelector(_cmd));

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier forIndexPath:indexPath];
    //NSAssert(!cell.hidden, @"a dequeued UITableViewCell should not be hidden");
    
    [self _tableView:tableView configureCell:cell forRowAtIndexPath:indexPath];
    return cell;
}

#pragma mark - UISearchDisplayController
#pragma mark UISearchDisplayDelegate
- (void)searchDisplayControllerWillBeginSearch:(UISearchDisplayController *)controller
{
    // See searchButtonTapped: and beginSearchingAnimated:
    NSAssert(self.isSearching, @"fatal error: 'isSearching' should already be 'YES' by the time the searchDisplayController is active");
}

- (void)searchDisplayController:(UISearchDisplayController *)controller didLoadSearchResultsTableView:(UITableView *)tableView
{
    [self _tableView:tableView registerNib:[UINib nibWithNibName:MITNewsStoryCellNibName bundle:nil] forCellReuseIdentifier:MITNewsStoryCellIdentifier];
    [self _tableView:tableView registerNib:[UINib nibWithNibName:MITNewsStoryNoDekCellNibName bundle:nil] forCellReuseIdentifier:MITNewsStoryNoDekCellIdentifier];
    [self _tableView:tableView registerNib:[UINib nibWithNibName:MITNewsStoryExternalCellNibName bundle:nil] forCellReuseIdentifier:MITNewsStoryExternalCellIdentifier];
    [self _tableView:tableView registerNib:[UINib nibWithNibName:MITNewsLoadMoreCellNibName bundle:nil] forCellReuseIdentifier:MITNewsLoadMoreCellIdentifier];
}

- (void)searchDisplayControllerDidBeginSearch:(UISearchDisplayController *)controller
{
    [controller.searchBar becomeFirstResponder];
}

- (void)searchDisplayController:(UISearchDisplayController *)controller willShowSearchResultsTableView:(UITableView *)tableView
{
    //[tableView reloadData];
}

- (void)searchDisplayControllerDidEndSearch:(UISearchDisplayController *)controller
{
    [self endSearchingAnimated:YES];
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    if ([searchString length] == 0) {
        return YES;
    } else {
        return NO;
    }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    NSString *searchQuery = searchBar.text;
    
    __weak UISearchDisplayController *searchDisplayController = self.searchDisplayController;
    searchDisplayController.searchResultsTableView.tableFooterView = nil;

    UIColor *textColor = nil;
    if ([self.view respondsToSelector:@selector(tintColor)]) {
        textColor = self.view.tintColor;
    } else {
        textColor = [UIColor MITTintColor];
    }

    [self loadSearchResultsForQuery:searchQuery loaded:^(NSError *error) {
        [searchDisplayController.searchResultsTableView reloadData];
    }];
}

@end



#pragma mark Data Source/Delegate Helper Methods
@implementation MITNewsViewController (DynamicTableViewCellsShared)
- (NSMutableDictionary*)_cachedLayoutCellsForTableView:(UITableView*)tableView
{
    const void *objectKey = (__bridge const void *)MITNewsCachedLayoutCellsAssociatedObjectKey;
    NSMapTable *cachedLayoutCells = objc_getAssociatedObject(tableView,objectKey);
    
    if (!cachedLayoutCells) {
        cachedLayoutCells = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(tableView, objectKey, cachedLayoutCells, OBJC_ASSOCIATION_RETAIN);
    }
    
    NSMutableDictionary *sizingCellsByIdentifier = [cachedLayoutCells objectForKey:tableView];
    if (!sizingCellsByIdentifier) {
        sizingCellsByIdentifier = [[NSMutableDictionary alloc] init];
        [cachedLayoutCells setObject:sizingCellsByIdentifier forKey:tableView];
    }
    
    return sizingCellsByIdentifier;
}

- (void)_tableView:(UITableView*)tableView registerClass:(Class)nilOrClass forCellReuseIdentifier:(NSString*)cellReuseIdentifier
{
    // Order is important! This depends on !nilOrClass short-circuiting the
    // OR.
    NSParameterAssert(!nilOrClass || class_isMetaClass(object_getClass(nilOrClass)));
    NSParameterAssert(!nilOrClass || [nilOrClass isSubclassOfClass:[UITableViewCell class]]);
    
    [tableView registerClass:nilOrClass forCellReuseIdentifier:cellReuseIdentifier];
    
    NSMutableDictionary *cachedLayoutCells = [self _cachedLayoutCellsForTableView:tableView];
    if (nilOrClass) {
        if (NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_6_1) {
            UITableViewCell *layoutCell = (UITableViewCell*)[[[nilOrClass class] alloc] init];
            cachedLayoutCells[cellReuseIdentifier] = layoutCell;
        }
    } else {
        [cachedLayoutCells removeObjectForKey:cellReuseIdentifier];
    }
}

- (void)_tableView:(UITableView*)tableView registerNib:(UINib*)nilOrNib forCellReuseIdentifier:(NSString*)cellReuseIdentifier
{
    NSParameterAssert(!nilOrNib || [nilOrNib isKindOfClass:[UINib class]]);
    
    [tableView registerNib:nilOrNib forCellReuseIdentifier:cellReuseIdentifier];
    
    NSMutableDictionary *cachedLayoutCells = [self _cachedLayoutCellsForTableView:tableView];
    
    if (nilOrNib) {
        if (NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_6_1) {
            UITableViewCell *layoutCell = [[nilOrNib instantiateWithOwner:nil options:nil] firstObject];
            NSAssert([layoutCell isKindOfClass:[UITableViewCell class]], @"class must be a subclass of %@",NSStringFromClass([UITableViewCell class]));
            cachedLayoutCells[cellReuseIdentifier] = layoutCell;
        }
    } else {
        [cachedLayoutCells removeObjectForKey:cellReuseIdentifier];
    }
}

- (UITableViewCell*)_tableView:(UITableView*)tableView dequeueReusableLayoutCellWithIdentifier:(NSString*)reuseIdentifier forIndexPath:(NSIndexPath*)indexPath
{
    NSMutableDictionary *cachedLayoutCellsForTableView = [self _cachedLayoutCellsForTableView:tableView];
    
    UITableViewCell *layoutCell = cachedLayoutCellsForTableView[reuseIdentifier];
    
    if (!layoutCell) {
        layoutCell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
        NSAssert(layoutCell, @"you must register a nib or class with for reuse identifier '%@'",reuseIdentifier);
        cachedLayoutCellsForTableView[reuseIdentifier] = layoutCell;
    }
    
    CGSize cellSize = [layoutCell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    layoutCell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    layoutCell.frame = CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), cellSize.height + 16.);
    
    if (![layoutCell isDescendantOfView:tableView]) {
        [tableView addSubview:layoutCell];
    } else {
        [layoutCell prepareForReuse];
    }
    
    layoutCell.hidden = YES;
    [layoutCell.contentView setNeedsLayout];
    [layoutCell.contentView layoutIfNeeded];
    
    return layoutCell;
}

- (NSInteger)_tableView:(UITableView*)tableView minimumHeightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSString *reuseIdentifier = [self _tableView:tableView reuseIdentifierForRowAtIndexPath:indexPath];
    UITableViewCell *layoutCell = [self _tableView:tableView dequeueReusableLayoutCellWithIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    NSAssert(layoutCell, @"unable to get a valid layout cell!");
    if ([self respondsToSelector:@selector(_tableView:configureCell:forRowAtIndexPath:)]) {
        [self _tableView:tableView configureCell:layoutCell forRowAtIndexPath:indexPath];
    } else if ([layoutCell respondsToSelector:@selector(setRepresentedObject:)]) {
        id representedObejct = [self _tableView:tableView representedObjectForRowAtIndexPath:indexPath];
        [layoutCell performSelector:@selector(setRepresentedObject:) withObject:representedObejct];
    } else {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"unable to configure cell in table view %@ at %@",tableView,indexPath]
                                     userInfo:nil];
    }
    
    [layoutCell.contentView setNeedsUpdateConstraints];
    [layoutCell.contentView setNeedsLayout];
    [layoutCell.contentView layoutIfNeeded];
    
    CGSize rowSize = [layoutCell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    return (ceil(rowSize.height) + 6);
}
@end

@implementation MITNewsViewController (DynamicTableViewCells)
- (NSString*)_tableView:(UITableView*)tableView reuseIdentifierForRowAtIndexPath:(NSIndexPath*)indexPath
{
    MITNewsStory *story = [self _tableView:tableView representedObjectForRowAtIndexPath:indexPath];
    if (story) {
        __block NSString *identifier = nil;
        [self.managedObjectContext performBlockAndWait:^{
            MITNewsStory *newsStory = (MITNewsStory*)[self.managedObjectContext objectWithID:[story objectID]];
            
            if ([newsStory.type isEqualToString:MITNewsStoryExternalType]) {
                if (newsStory.coverImage) {
                    identifier = MITNewsStoryExternalCellIdentifier;
                } else {
                    identifier = MITNewsStoryExternalNoImageCellIdentifier;
                }
            } else if ([newsStory.dek length])  {
                identifier = MITNewsStoryCellIdentifier;
            } else {
                identifier = MITNewsStoryNoDekCellIdentifier;
            }
        }];
        
        return identifier;
    } else if (tableView == self.searchDisplayController.searchResultsTableView) {
        return MITNewsLoadMoreCellIdentifier;
    } else {
        return nil;
    }
}

// Should delegate
- (id)_tableView:(UITableView*)tableView representedObjectForRowAtIndexPath:(NSIndexPath*)indexPath {
    return [self storyAtIndexPath:indexPath inTableView:tableView];
}

// Should delegate
- (NSInteger)_tableView:(UITableView *)tableView primitiveNumberOfRowsInSection:(NSInteger)section
{
    if (tableView == self.tableView) {
        if (self.showFeaturedStoriesSection && (section == 0)) {
            NSArray *stories = [self.featuredStoriesFetchedResultsController fetchedObjects];
            return MIN(MITNewsDefaultNumberOfFeaturedStories,[stories count]);
        } else if (self.categoriesFetchedResultsController.fetchedObjects) {
            if (self.featuredStoriesFetchedResultsController) {
                section -= 1;
            }
            
            MITNewsCategory *category = self.categoriesFetchedResultsController.fetchedObjects[section];
            NSArray *storiesInCategory = [self storiesInCategory:category];
            return MIN(self.numberOfStoriesPerCategory,[storiesInCategory count]);
        }
        
        return 0;
    } else if (tableView == self.searchDisplayController.searchResultsTableView) {
        if ([self.searchResults count] > 0) {
            return [self.searchResults count] + 1; // Add one for the 'load more' cell
        } else {
            return 0;
        }
    } else {
        return 0;
    }
}

// Should delegate
- (void)_tableView:(UITableView*)tableView configureCell:(UITableViewCell*)cell forRowAtIndexPath:(NSIndexPath*)indexPath
{
    MITNewsStory *story = [self _tableView:tableView representedObjectForRowAtIndexPath:indexPath];
    
    if (story && [cell isKindOfClass:[MITNewsStoryCell class]]) {
        MITNewsStoryCell *storyCell = (MITNewsStoryCell*)cell;
        [self.managedObjectContext performBlockAndWait:^{
            MITNewsStory *contextStory = (MITNewsStory*)[self.managedObjectContext objectWithID:[story objectID]];
            storyCell.story = contextStory;
        }];
    }
}
@end


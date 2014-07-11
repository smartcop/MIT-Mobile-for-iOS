#import "MITMapHomeViewController.h"
#import "MITMapModelController.h"
#import "MITMapPlace.h"
#import "MITTiledMapView.h"
#import "MITMapPlaceAnnotationView.h"
#import "MITMapResultsListViewController.h"
#import "MITMapBrowseContainerViewController.h"
#import "CoreData+MITAdditions.h"
#import "UIKit+MITAdditions.h"
#import "MITMapPlaceDetailViewController.h"
#import "MITMapPlaceSelector.h"
#import "MITMapTypeAheadTableViewController.h"

static NSString * const kMITMapPlaceAnnotationViewIdentifier = @"MITMapPlaceAnnotationView";

typedef NS_ENUM(NSUInteger, MITMapSearchQueryType) {
    MITMapSearchQueryTypeText,
    MITMapSearchQueryTypePlace,
    MITMapSearchQueryTypeCategory
};

@interface MITMapHomeViewController () <UISearchBarDelegate, MKMapViewDelegate, MITTiledMapViewButtonDelegate, MITMapResultsListViewControllerDelegate, MITMapPlaceSelectionDelegate, MITMapTypeAheadTableViewControllerDelegate>

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIBarButtonItem *bookmarksBarButton;
@property (nonatomic, strong) UIBarButtonItem *menuBarButton;
@property (nonatomic) BOOL searchBarShouldBeginEditing;
@property (nonatomic) MITMapSearchQueryType searchQueryType;
@property (nonatomic, strong) MITMapTypeAheadTableViewController *typeAheadViewController;
@property (nonatomic, strong) UIPopoverController *typeAheadPopoverController;

@property (weak, nonatomic) IBOutlet MITTiledMapView *tiledMapView;
@property (nonatomic, readonly) MKMapView *mapView;

@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, copy) NSArray *places;
@property (nonatomic, strong) MITMapCategory *category;

@end

@implementation MITMapHomeViewController

#pragma mark - Map View

- (MKMapView *)mapView
{
    return self.tiledMapView.mapView;
}

#pragma mark - Init

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _searchBarShouldBeginEditing = YES;
    }
    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupNavigationBar];
    [self setupMapView];
    [self setupResultsTableView];
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        [self.navigationController setToolbarHidden:NO];
        [self.tiledMapView setButtonsHidden:YES animated:NO];
        UIBarButtonItem *listBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"global/menu.png"] style:UIBarButtonItemStylePlain target:self action:@selector(ipadListButtonPressed)];
        UIBarButtonItem *currentLocationBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"global/location"] style:UIBarButtonItemStylePlain target:self action:@selector(ipadCurrentLocationButtonPressed)];
        UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.toolbarItems = @[listBarButton, flexibleSpace, currentLocationBarButton];
    } else {
        [self.navigationController setToolbarHidden:YES];
        [self.tiledMapView setButtonsHidden:NO animated:NO];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationItem setHidesBackButton:YES animated:NO];
    [self registerForKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self unregisterForKeyboardNotifications];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self.navigationItem setHidesBackButton:NO animated:NO];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Rotation

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self setupMapBoundingBoxAnimated:YES];
}

#pragma mark - Setup

- (void)setupNavigationBar
{
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(-10, 0, 340, 44)];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = @"Search MIT Campus";
    // Insert the correct clear button image and uncomment the next line when ready
//    [searchBar setImage:[UIImage imageNamed:@""] forSearchBarIcon:UISearchBarIconClear state:UIControlStateNormal];
    
    UIView *searchBarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    searchBarView.autoresizingMask = 0;
    self.searchBar.delegate = self;
    [searchBarView addSubview:self.searchBar];
    self.navigationItem.titleView = searchBarView;
    
    self.bookmarksBarButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemBookmarks target:self action:@selector(bookmarksButtonPressed)];
    [self.navigationItem setRightBarButtonItem:self.bookmarksBarButton];
    
    self.menuBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"global/menu.png"] style:UIBarButtonItemStylePlain target:self action:@selector(menuButtonPressed)];
    [self.navigationItem setLeftBarButtonItem:self.menuBarButton];
}

- (void)setupMapView
{
    self.tiledMapView.buttonDelegate = self;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    [self setupMapBoundingBoxAnimated:NO];
}

- (void)setupResultsTableView
{
    self.typeAheadViewController = [[MITMapTypeAheadTableViewController alloc] initWithStyle:UITableViewStylePlain];
    self.typeAheadViewController.delegate = self;
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        self.typeAheadPopoverController = [[UIPopoverController alloc] initWithContentViewController:self.typeAheadViewController];
        self.typeAheadViewController.showsTitleHeader = YES;
    } else {
        [self addChildViewController:self.typeAheadViewController];
        self.typeAheadViewController.view.frame = CGRectMake(0, -100, self.view.frame.size.width, 0);
        [self.view addSubview:self.typeAheadViewController.view];
        [self.typeAheadViewController didMoveToParentViewController:self];
    }
}

#pragma mark - Button Actions

- (void)registerForKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)unregisterForKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)bookmarksButtonPressed
{
    MITMapBrowseContainerViewController *browseContainerViewController = [[MITMapBrowseContainerViewController alloc] initWithNibName:nil bundle:nil];
    [browseContainerViewController setDelegate:self];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:browseContainerViewController];
    navigationController.navigationBarHidden = YES;
    navigationController.toolbarHidden = NO;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)menuButtonPressed
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)ipadListButtonPressed
{
    
}

- (void)ipadCurrentLocationButtonPressed
{
    [self.tiledMapView centerMapOnUserLocation];
}

#pragma mark - Search Bar

- (void)closeSearchBar:(UISearchBar *)searchBar
{
    self.navigationItem.leftBarButtonItem = self.menuBarButton;
    self.navigationItem.rightBarButtonItem = self.bookmarksBarButton;
    [searchBar setShowsCancelButton:NO animated:YES];
}

- (void)setSearchBarTextColor:(UIColor *)color
{
    // A public API would be preferable, but UIAppearance doesn't update unless you remove the view from superview and re-add, which messes with the display
    UITextField *searchBarTextField = [self.searchBar textField];
    searchBarTextField.textColor = color;
}

- (void)setSearchQueryType:(MITMapSearchQueryType)searchQueryType
{
    UIColor *searchBarTextColor = (searchQueryType == MITMapSearchQueryTypeText) ? [UIColor blackColor] : [UIColor mit_tintColor];
    [self setSearchBarTextColor:searchBarTextColor];
    _searchQueryType = searchQueryType;
}

#pragma mark - Map View

- (void)setupMapBoundingBoxAnimated:(BOOL)animated
{
    [self.view layoutIfNeeded]; // ensure that map has autoresized before setting region
    
    if ([self.places count] > 0) {
        [self.mapView showAnnotations:self.places animated:animated];
    } else {
        [self.mapView setRegion:kMITShuttleDefaultMapRegion animated:animated];
    }
}

#pragma mark - Places

- (void)setPlaces:(NSArray *)places
{
    [self setPlaces:places animated:NO];
}

- (void)setPlaces:(NSArray *)places animated:(BOOL)animated
{
    _places = places;
    [self refreshPlaceAnnotations];
    [self setupMapBoundingBoxAnimated:animated];
}

- (void)clearPlacesAnimated:(BOOL)animated
{
    self.category = nil;
    self.searchQuery = nil;
    self.searchQueryType = MITMapSearchQueryTypeText;
    [self setPlaces:nil animated:animated];
}

- (void)refreshPlaceAnnotations
{
    [self removeAllPlaceAnnotations];
    [self.mapView addAnnotations:self.places];
}

- (void)removeAllPlaceAnnotations
{
    NSMutableArray *annotationsToRemove = [NSMutableArray array];
    for (id <MKAnnotation> annotation in self.mapView.annotations) {
        if ([annotation isKindOfClass:[MITMapPlace class]]) {
            [annotationsToRemove addObject:annotation];
        }
    }
    [self.mapView removeAnnotations:annotationsToRemove];
}

#pragma mark - Search Results

- (void)keyboardWillShow:(NSNotification *)notification
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        CGFloat navBarHeight = 64;
        CGRect endFrame = [[notification.userInfo valueForKeyPath:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGFloat tableViewHeight = self.view.frame.size.height - endFrame.size.height - navBarHeight;
        self.typeAheadViewController.view.frame = CGRectMake(0, -tableViewHeight, self.view.frame.size.width, tableViewHeight);
        [UIView animateWithDuration:0.5 animations:^{
            self.typeAheadViewController.view.frame = CGRectMake(0, navBarHeight, self.view.frame.size.width, tableViewHeight);
        }];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        [UIView animateWithDuration:0.5 animations:^{
            self.typeAheadViewController.view.frame = CGRectMake(0, -self.typeAheadViewController.view.frame.size.height, self.view.frame.size.width, self.typeAheadViewController.view.frame.size.height);
        }];
    }
}

- (void)updateSearchResultsForSearchString:(NSString *)searchString
{
    [self.typeAheadViewController updateResultsWithSearchTerm:searchString];
}

- (void)performSearchWithQuery:(NSString *)query
{
    self.searchQuery = query;
    [[MITMapModelController sharedController] addRecentSearch:query];
    [[MITMapModelController sharedController] searchMapWithQuery:query
                                                          loaded:^(NSArray *objects, NSError *error) {
                                                              if (objects) {
                                                                  [self setPlaces:objects animated:YES];
                                                              }
                                                          }];
}

- (void)setPlacesWithRecentSearchQuery:(NSString *)query
{
    [self performSearchWithQuery:query];
    self.category = nil;
    self.searchBar.text = query;
    self.searchQueryType = MITMapSearchQueryTypeText;
}

- (void)setPlacesWithPlace:(MITMapPlace *)place
{
    [[MITMapModelController sharedController] addRecentSearch:place];
    self.searchQuery = nil;
    self.category = nil;
    [self setPlaces:@[place] animated:YES];
    self.searchBar.text = place.name;
    self.searchQueryType = MITMapSearchQueryTypePlace;
    [self showCalloutForPlace:place];
}

- (void)setPlacesWithCategory:(MITMapCategory *)category
{
    [[MITMapModelController sharedController] addRecentSearch:category];
    self.category = category;
    self.searchQuery = nil;
    NSArray *places = category.allPlaces;
    [self setPlaces:places animated:YES];
    self.searchBar.text = category.name;
    self.searchQueryType = MITMapSearchQueryTypeCategory;
}

- (void)pushDetailViewControllerForPlace:(MITMapPlace *)place
{
    MITMapPlaceDetailViewController *detailVC = [[MITMapPlaceDetailViewController alloc] initWithNibName:nil bundle:nil];
    detailVC.place = place;
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (void)showCalloutForPlace:(MITMapPlace *)place
{
    if ([self.places containsObject:place]) {
        [self.mapView selectAnnotation:place animated:YES];
    }
}

- (void)showTypeAheadPopover
{
    [self.typeAheadPopoverController presentPopoverFromRect:CGRectMake(self.searchBar.bounds.size.width / 2, self.searchBar.bounds.size.height, 1, 1) inView:self.searchBar permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

#pragma mark - MITMapTypeAheadTableViewControllerDelegate Methods

- (void)typeAheadViewController:(MITMapTypeAheadTableViewController *)typeAheadViewController didSelectRecentQuery:(NSString *)recentQuery
{
    [self.searchBar resignFirstResponder];
    [self.typeAheadPopoverController dismissPopoverAnimated:YES];
    [self setPlacesWithRecentSearchQuery:recentQuery];
}

- (void)typeAheadViewController:(MITMapTypeAheadTableViewController *)typeAheadViewController didSelectPlace:(MITMapPlace *)place
{
    [self.searchBar resignFirstResponder];
    [self.typeAheadPopoverController dismissPopoverAnimated:YES];
    [self setPlacesWithPlace:place];
}

- (void)typeAheadViewController:(MITMapTypeAheadTableViewController *)typeAheadViewController didSelectCategory:(MITMapCategory *)category
{
    [self.searchBar resignFirstResponder];
    [self.typeAheadPopoverController dismissPopoverAnimated:YES];
    [self setPlacesWithCategory:category];
}

#pragma mark - UISearchBarDelegate Methods

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        [self showTypeAheadPopover];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = nil;
    }
    
    [searchBar setShowsCancelButton:YES animated:YES];
    [self updateSearchResultsForSearchString:nil];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    [self closeSearchBar:searchBar];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    self.searchQueryType = MITMapSearchQueryTypeText;
    [self performSearchWithQuery:searchBar.text];
}

- (BOOL)searchBar:(UISearchBar *)searchBar shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if (self.searchQueryType != MITMapSearchQueryTypeText) {
        searchBar.text = text;
        self.searchQueryType = MITMapSearchQueryTypeText;
    }
    return YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self updateSearchResultsForSearchString:searchText];
    
    if (searchBar.isFirstResponder) {
        if (!self.typeAheadPopoverController.popoverVisible) {
            [self showTypeAheadPopover];
        }
    } else {
        self.searchBarShouldBeginEditing = NO;
        [self clearPlacesAnimated:YES];
    }
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    BOOL shouldBeginEditing = self.searchBarShouldBeginEditing;
    self.searchBarShouldBeginEditing = YES;
    return shouldBeginEditing;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    if ([searchBar.text length] == 0) {
        [self clearPlacesAnimated:YES];
    }
}

#pragma mark - MITTiledMapViewButtonDelegate

- (void)mitTiledMapViewRightButtonPressed:(MITTiledMapView *)mitTiledMapView
{
    MITMapResultsListViewController *resultsListViewController = [[MITMapResultsListViewController alloc] initWithPlaces:self.places];
    resultsListViewController.delegate = self;
    switch (self.searchQueryType) {
        case MITMapSearchQueryTypeText: {
            [resultsListViewController setTitleWithSearchQuery:self.searchQuery];
            break;
        }
        case MITMapSearchQueryTypePlace: {
            MITMapPlace *place = [self.places firstObject];
            [resultsListViewController setTitle:place.name];
            break;
        }
        case MITMapSearchQueryTypeCategory: {
            [resultsListViewController setTitle:self.category.name];
            break;
        }
        default:
            break;
    }
    
    UINavigationController *resultsListNavigationController = [[UINavigationController alloc] initWithRootViewController:resultsListViewController];
    [self presentViewController:resultsListNavigationController animated:YES completion:nil];
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation
{
    if ([annotation isKindOfClass:[MITMapPlace class]]) {
        MITMapPlaceAnnotationView *annotationView = (MITMapPlaceAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:kMITMapPlaceAnnotationViewIdentifier];
        if (!annotationView) {
            annotationView = [[MITMapPlaceAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:kMITMapPlaceAnnotationViewIdentifier];
        }
        NSInteger placeIndex = [self.places indexOfObject:annotation];
        [annotationView setNumber:(placeIndex + 1)];
        return annotationView;
    }
    return nil;
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay
{
    if ([overlay isKindOfClass:[MKTileOverlay class]]) {
        return [[MKTileOverlayRenderer alloc] initWithTileOverlay:overlay];
    }
    return nil;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control
{
    if ([view isKindOfClass:[MITMapPlaceAnnotationView class]]) {
        MITMapPlace *place = view.annotation;
        [self pushDetailViewControllerForPlace:place];
    }
}

#pragma mark - MITMapResultsListViewControllerDelegate

- (void)resultsListViewController:(MITMapResultsListViewController *)viewController didSelectPlace:(MITMapPlace *)place
{
    [self showCalloutForPlace:place];
}

#pragma mark - MITMapPlaceSelectionDelegate

- (void)placeSelectionViewController:(UIViewController <MITMapPlaceSelector >*)viewController didSelectPlace:(MITMapPlace *)place
{
    [self dismissViewControllerAnimated:YES completion:^{
        [self setPlacesWithPlace:place];
    }];
}

- (void)placeSelectionViewController:(UIViewController<MITMapPlaceSelector> *)viewController didSelectCategory:(MITMapCategory *)category
{
    [self dismissViewControllerAnimated:YES completion:^{
        [self setPlacesWithCategory:category];
    }];
}

@end

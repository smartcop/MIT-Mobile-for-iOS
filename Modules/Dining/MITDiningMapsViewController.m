#import "MITDiningMapsViewController.h"
#import "MITTiledMapView.h"
#import "MITDiningPlace.h"
#import "MITCoreData.h"
#import "MITAdditions.h"
#import "MITMapPlaceAnnotationView.h"
#import "MITDiningRetailVenue.h"
#import "MITDiningHouseVenue.h"
#import "MITDiningRetailVenueDetailViewController.h"
#import "MITDiningHouseVenueDetailViewController.h"
#import "MITLocationManager.h"
#import "MITCalloutView.h"

static NSString * const kMITMapPlaceAnnotationViewIdentifier = @"MITMapPlaceAnnotationView";

static NSString * const kMITEntityNameDiningHouseVenue = @"MITDiningHouseVenue";
static NSString * const kMITEntityNameDiningRetailVenue = @"MITDiningRetailVenue";

@interface MITDiningMapsViewController () <NSFetchedResultsControllerDelegate, MKMapViewDelegate, MITDiningRetailVenueDetailViewControllerDelegate, MITCalloutViewDelegate>

@property (strong, nonatomic) NSArray *places;
@property (nonatomic) BOOL shouldRefreshAnnotationsOnNextMapRegionChange;
@property (strong, nonatomic) NSFetchRequest *fetchRequest;
@property (nonatomic, copy) NSString *currentlyDisplayedEntityName;
@property (nonatomic, strong) UIPopoverController *detailPopoverController;
@property (nonatomic, strong) MKAnnotationView *annotationViewForPopoverAfterRegionChange;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *mapBottomConstraint;
@property (nonatomic, strong) NSArray *toolbarConstraints;
@property (nonatomic, strong) MITCalloutView *calloutView;
@property (nonatomic, strong) MKAnnotationView *currentlySelectedPlace;
@property (nonatomic, readonly) MITCalloutMapView *mapView;

@end

@implementation MITDiningMapsViewController

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
    [self setupTiledMapView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(locationManagerDidUpdateAuthorizationStatus:) name:kLocationManagerDidUpdateAuthorizationStatusNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setToolBarHidden:(BOOL)hidden
{
    if (hidden) {
        if (self.toolbarConstraints) {
            [self.view removeConstraints:self.toolbarConstraints];
            [self.toolbar removeFromSuperview];
            self.toolbarConstraints = nil;
            [self.view removeConstraint:self.mapBottomConstraint];
            self.mapBottomConstraint = [NSLayoutConstraint constraintWithItem:self.tiledMapView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1 constant:0];
            [self.view addConstraint:self.mapBottomConstraint];
        }
    } else {
        self.toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 44, self.view.bounds.size.width, 44)];
        [self.toolbar setItems:@[self.tiledMapView.userLocationButton] animated:NO];
        self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.toolbar];
        
        NSMutableArray *newToolbarConstraints = [NSMutableArray array];
        [newToolbarConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[toolbar]-0-|" options:0 metrics:nil views:@{@"toolbar": self.toolbar}]];
        [newToolbarConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[toolbar]-0-|" options:0 metrics:nil views:@{@"toolbar": self.toolbar}]];
        self.toolbarConstraints = [NSArray arrayWithArray:newToolbarConstraints];
        [self.view addConstraints:self.toolbarConstraints];
        
        [self.view removeConstraint:self.mapBottomConstraint];
        self.mapBottomConstraint = [NSLayoutConstraint constraintWithItem:self.tiledMapView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.toolbar attribute:NSLayoutAttributeTop multiplier:1 constant:0];
        [self.view addConstraint:self.mapBottomConstraint];
    }
    
    [self.view setNeedsUpdateConstraints];
    [self.view updateConstraintsIfNeeded];
}

#pragma mark - MapView Methods

- (void)setupTiledMapView
{
    [self.tiledMapView setMapDelegate:self];
    self.mapView.showsUserLocation = [MITLocationManager locationServicesAuthorized];
    [self setupMapBoundingBoxAnimated:NO];
    
    [self setupCalloutView];
}

- (void)setupCalloutView
{
    MITCalloutView *calloutView = [MITCalloutView new];
    calloutView.delegate = self;
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        calloutView.shouldHighlightOnTouch = NO;
    } else {
        calloutView.permittedArrowDirections = MITCalloutArrowDirectionTop | MITCalloutArrowDirectionBottom;
    }
    self.calloutView = calloutView;
    self.tiledMapView.mapView.mitCalloutView = self.calloutView;
}

- (void)setupMapBoundingBoxAnimated:(BOOL)animated
{
    [self.view layoutIfNeeded]; // ensure that map has autoresized before setting region
    
    if ([self.places count] > 0) {
        MKMapRect zoomRect = MKMapRectNull;
        for (id <MKAnnotation> annotation in self.places)
        {
            MKMapPoint annotationPoint = MKMapPointForCoordinate(annotation.coordinate);
            MKMapRect pointRect = MKMapRectMake(annotationPoint.x, annotationPoint.y, 0.1, 0.1);
            zoomRect = MKMapRectUnion(zoomRect, pointRect);
        }
        double inset = -zoomRect.size.width * 0.1;
        [self.mapView setVisibleMapRect:MKMapRectInset(zoomRect, inset, inset) animated:YES];
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
        if ([annotation isKindOfClass:[MITDiningPlace class]]) {
            [annotationsToRemove addObject:annotation];
        }
    }
    [self.mapView removeAnnotations:annotationsToRemove];
}


#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation
{
    if ([annotation isKindOfClass:[MITDiningPlace class]]) {
        MITMapPlaceAnnotationView *annotationView = (MITMapPlaceAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:kMITMapPlaceAnnotationViewIdentifier];
        if (!annotationView) {
            annotationView = [[MITMapPlaceAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:kMITMapPlaceAnnotationViewIdentifier];
        }
        [annotationView setNumber:[(MITDiningPlace *)annotation displayNumber]];
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

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        [self showDetailForAnnotationView:view];
        [self.mapView deselectAnnotation:view.annotation animated:NO];
    } else {
        if ([view isKindOfClass:[MITMapPlaceAnnotationView class]]) {
            [self presentIPhoneCalloutForAnnotationView:view];
        }
    }
}

- (void)mapView:(MKMapView *)mapView didDeselectAnnotationView:(MKAnnotationView *)view
{
    if ([view isKindOfClass:[MITMapPlaceAnnotationView class]]){
        [self.calloutView dismissCallout];
        self.currentlySelectedPlace = nil;
    }
}

- (void)showDetailForAnnotationView:(MKAnnotationView *)view
{
    if ([view isKindOfClass:[MITMapPlaceAnnotationView class]]) {
        MITDiningPlace *place = view.annotation;
        
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            if (place.retailVenue) {
                // Scroll map so that the annotation is centered vertically, and on the right edge horizontally
                // This ensures that the popover will not cover the left list
                MKCoordinateRegion newMapRegion = self.mapView.region;
                CLLocationCoordinate2D newMapRegionCenter = newMapRegion.center;
                newMapRegionCenter.latitude = place.coordinate.latitude;
                newMapRegionCenter.longitude = place.coordinate.longitude - (0.4 * newMapRegion.span.longitudeDelta);
                newMapRegion.center = newMapRegionCenter;
                
                // The map region is not exact when set. The new region can be within a margin of error and the regionDidChange delegate call will never be called.
                // Have to check within this margin to make sure we show the popover if the map is already scrolled to the right spot. This seems right based on testing, there is no official answer.
                if (newMapRegion.center.latitude > self.mapView.region.center.latitude - 0.00000001 && newMapRegion.center.latitude < self.mapView.region.center.latitude + 0.00000001 &&
                    newMapRegion.center.longitude > self.mapView.region.center.longitude - 0.00000001 && newMapRegion.center.longitude < self.mapView.region.center.longitude + 0.00000001) {
                    [self showRetailPopoverForAnnotationView:view];
                } else {
                    self.annotationViewForPopoverAfterRegionChange = view;
                    [self.mapView setRegion:newMapRegion animated:YES];
                }
            }
        } else {
            if (place.houseVenue) {
                MITDiningHouseVenueDetailViewController *detailVC = [[MITDiningHouseVenueDetailViewController alloc] init];
                detailVC.houseVenue = place.houseVenue;
                [self.navigationController pushViewController:detailVC animated:YES];
            } else if (place.retailVenue) {
                MITDiningRetailVenueDetailViewController *detailVC = [[MITDiningRetailVenueDetailViewController alloc] initWithNibName:nil bundle:nil];
                detailVC.retailVenue = place.retailVenue;
                [self.navigationController pushViewController:detailVC animated:YES];
            }
        }
    }
}

- (void)showDetailForRetailVenue:(MITDiningRetailVenue *)retailVenue
{
    for (MITDiningPlace *place in self.places) {
        if ([place.retailVenue.identifier isEqualToString:retailVenue.identifier]) {
            [self.mapView selectAnnotation:place animated:YES];
            return;
        }
    }
    
    // If we get here, the place doesn't have an annotation (probably because it has missing/invalid location data)
    [self showRetailPopoverForVenueWithoutAnnotation:retailVenue];
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    if (self.shouldRefreshAnnotationsOnNextMapRegionChange) {
        [self refreshPlaceAnnotations];
        self.shouldRefreshAnnotationsOnNextMapRegionChange = NO;
    } else if (self.annotationViewForPopoverAfterRegionChange) {
        MITDiningPlace *place = self.annotationViewForPopoverAfterRegionChange.annotation;
        if (place.retailVenue) {
            [self showRetailPopoverForAnnotationView:self.annotationViewForPopoverAfterRegionChange];
        }
        self.annotationViewForPopoverAfterRegionChange = nil;
    }
}


#pragma mark - Callout View

- (void)presentIPhoneCalloutForAnnotationView:(MKAnnotationView *)annotationView
{
    MITDiningPlace *place = annotationView.annotation;
    
    self.currentlySelectedPlace = annotationView;
    self.calloutView.titleText = place.title;
    
    // For whatever reason, an annotation view takes up the left half of its view.  Adjust this for proper presentation
    CGRect annotationBounds = annotationView.bounds;
    annotationBounds.size.width /= 2.0;
    [self.calloutView presentFromRect:annotationBounds inView:annotationView withConstrainingView:self.tiledMapView.mapView];
}

#pragma mark - MITCalloutViewDelegate

- (void)calloutViewRemovedFromViewHierarchy:(MITCalloutView *)calloutView
{
    
}

- (void)calloutView:(MITCalloutView *)calloutView positionedOffscreenWithOffset:(CGPoint)offscreenOffset
{
    MKMapView *mapView = self.mapView;
    CGPoint adjustedCenter = CGPointMake(offscreenOffset.x + mapView.bounds.size.width * 0.5,
                                         offscreenOffset.y + mapView.bounds.size.height * 0.5);
    CLLocationCoordinate2D newCenter = [mapView convertPoint:adjustedCenter toCoordinateFromView:mapView];
    [mapView setCenterCoordinate:newCenter animated:YES];
}

- (void)calloutViewTapped:(MITCalloutView *)calloutView
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        [self showDetailForAnnotationView:self.currentlySelectedPlace];
    }
}

- (void)showRetailPopoverForAnnotationView:(MKAnnotationView *)view
{
    MITDiningPlace *place = view.annotation;
    MITDiningRetailVenueDetailViewController *detailVC = [[MITDiningRetailVenueDetailViewController alloc] initWithNibName:nil bundle:nil];
    detailVC.retailVenue = place.retailVenue;
    detailVC.delegate = self;
    self.detailPopoverController = [[UIPopoverController alloc] initWithContentViewController:detailVC];
    
    CGFloat tableHeight = [detailVC targetTableViewHeight];
    CGFloat minPopoverHeight = [self minPopoverHeight];
    CGFloat maxPopoverHeight = [self maxPopoverHeight];
    
    if (tableHeight > maxPopoverHeight) {
        tableHeight = maxPopoverHeight;
    } else if (tableHeight < minPopoverHeight) {
        tableHeight = minPopoverHeight;
    }
    
    [self.detailPopoverController setPopoverContentSize:CGSizeMake(320, tableHeight) animated:NO];
    
    // Adjust so that popover arrow points to top of pin
    CGRect viewFrame = view.frame;
    viewFrame.size.height = viewFrame.size.height / 2.0;
    [self.detailPopoverController presentPopoverFromRect:viewFrame inView:self.mapView permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)showRetailPopoverForVenueWithoutAnnotation:(MITDiningRetailVenue *)retailVenue
{
    MITDiningRetailVenueDetailViewController *detailVC = [[MITDiningRetailVenueDetailViewController alloc] initWithNibName:nil bundle:nil];
    detailVC.retailVenue = retailVenue;
    detailVC.delegate = self;
    self.detailPopoverController = [[UIPopoverController alloc] initWithContentViewController:detailVC];
    
    CGFloat tableHeight = [detailVC targetTableViewHeight];
    CGFloat minPopoverHeight = [self minPopoverHeight];
    CGFloat maxPopoverHeight = [self maxPopoverHeight];
    
    if (tableHeight > maxPopoverHeight) {
        tableHeight = maxPopoverHeight;
    } else if (tableHeight < minPopoverHeight) {
        tableHeight = minPopoverHeight;
    }
    
    [self.detailPopoverController setPopoverContentSize:CGSizeMake(320, tableHeight) animated:NO];
    
    CLLocationCoordinate2D presentationCoordinate = CLLocationCoordinate2DMake(self.mapView.region.center.latitude, self.mapView.region.center.longitude + (0.4 * self.mapView.region.span.longitudeDelta));
    CGPoint presentationPoint = [self.mapView convertCoordinate:presentationCoordinate toPointToView:self.mapView];
    // TODO: Move the popover presentation point to the left to account for the missing arrow. Need to use our custom popover bg view class because simply moving this point doesnt work with permittedArrowDirections:0
    CGRect presentationRectInMapView = CGRectMake(presentationPoint.x, presentationPoint.y, 10, 10);
    [self.detailPopoverController presentPopoverFromRect:presentationRectInMapView inView:self.mapView permittedArrowDirections:0 animated:YES];
}

#pragma mark - Loading Events Into Map

- (void)updateMapWithDiningPlaces:(NSArray *)diningPlaceArray
{
    [self removeAllPlaceAnnotations];
    NSMutableArray *annotationsToAdd = [NSMutableArray array];
    for (int i = 0; i < diningPlaceArray.count; i++) {
        
        id venue = diningPlaceArray[i];
        MITDiningPlace *diningPlace = nil;
        if ([venue isKindOfClass:[MITDiningRetailVenue class]]) {
            diningPlace = [[MITDiningPlace alloc] initWithRetailVenue:venue];
        } else if ([venue isKindOfClass:[MITDiningHouseVenue class]]) {
            diningPlace = [[MITDiningPlace alloc] initWithHouseVenue:venue];
        }
        if (diningPlace) {
            diningPlace.displayNumber = (i + 1);
            [annotationsToAdd addObject:diningPlace];
        }
    }
    
    self.places = annotationsToAdd;
}

#pragma mark - MapView Getter

- (MKMapView *)mapView
{
    return self.tiledMapView.mapView;
}

#pragma mark - MITDiningRetailVenueDetailViewControllerDelegate Methods

- (void)retailDetailViewControllerDidUpdateSize:(MITDiningRetailVenueDetailViewController *)retailDetailViewController
{
    CGFloat tableHeight = [retailDetailViewController targetTableViewHeight];
    CGFloat maxPopoverHeight = [self maxPopoverHeight];
    CGFloat minPopoverHeight = [self minPopoverHeight];
    
    if (tableHeight > maxPopoverHeight) {
        tableHeight = maxPopoverHeight;
    } else if (tableHeight < minPopoverHeight) {
        tableHeight = minPopoverHeight;
    }
    
    [self.detailPopoverController setPopoverContentSize:CGSizeMake(320, tableHeight) animated:YES];
}

- (void)retailDetailViewController:(MITDiningRetailVenueDetailViewController *)viewController didUpdateFavoriteStatusForVenue:(MITDiningRetailVenue *)venue
{
    if ([self.delegate respondsToSelector:@selector(popoverChangedFavoriteStatusForRetailVenue:)]) {
        [self.delegate popoverChangedFavoriteStatusForRetailVenue:venue];
    }
}

#pragma mark - UIPopover Calculations

- (CGFloat)maxPopoverHeight
{
    CGFloat navbarHeight = 44;
    CGFloat statusBarHeight = 20;
    CGFloat toolbarHeight = 44;
    CGFloat padding = 30;
    CGFloat maxPopoverHeight = self.view.bounds.size.height - navbarHeight - statusBarHeight - toolbarHeight - (2 * padding);
    return maxPopoverHeight;
}

- (CGFloat)minPopoverHeight
{
    return 360.0;
}

#pragma mark - Location Notifications

- (void)locationManagerDidUpdateAuthorizationStatus:(NSNotification *)notification
{
    self.mapView.showsUserLocation = [MITLocationManager locationServicesAuthorized];
}

@end

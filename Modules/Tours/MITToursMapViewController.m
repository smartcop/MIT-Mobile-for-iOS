#import "MITToursMapViewController.h"
#import "MITToursStop.h"
#import "MITCalloutMapView.h"
#import "MITToursStopAnnotation.h"
#import "MITMapPlaceAnnotationView.h"
#import "MITToursDirectionsToStop.h"
#import "MITToursCalloutContentView.h"
#import "MITToursStopDetailContainerViewController.h"
#import "UIKit+MITAdditions.h"
#import "MITLocationManager.h"
#import "MITCalloutView.h"

#define MILES_PER_METER 0.000621371

static NSString * const kMITToursStopAnnotationViewIdentifier = @"MITToursStopAnnotationView";

static NSInteger kAnnotationMarginTop = 0;
static NSInteger kAnnotationMarginBottom = 200;
static NSInteger kAnnotationMarginLeft = 50;
static NSInteger kAnnotationMarginRight = 50;

@interface MITToursMapViewController () <MKMapViewDelegate, MITCalloutViewDelegate, MITTiledMapViewUserTrackingDelegate>

@property (strong, nonatomic) MITCalloutView *calloutView;
@property (strong, nonatomic) NSMutableArray *dismissingPopoverControllers;
@property (nonatomic) UIEdgeInsets annotationMarginInsets;

@property (weak, nonatomic) IBOutlet UIView *tourDetailsView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *tourDetailsHeightConstraint;

@property (nonatomic, strong, readwrite) MITToursTour *tour;
@property (nonatomic) MKMapRect savedMapRect;

@end

@implementation MITToursMapViewController

- (instancetype)initWithTour:(MITToursTour *)tour nibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.tour = tour;
        self.dismissingPopoverControllers = [[NSMutableArray alloc] init];
        self.annotationMarginInsets = UIEdgeInsetsMake(kAnnotationMarginTop, kAnnotationMarginLeft, kAnnotationMarginBottom, kAnnotationMarginRight);
        self.shouldShowStopDescriptions = NO;
        self.shouldShowTourDetailsPanel = YES;
        self.savedMapRect = MKMapRectNull;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupTiledMapView];
    [self setupCalloutView];
    [self setupTourDetailsView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(locationManagerDidUpdateAuthorizationStatus:) name:kLocationManagerDidUpdateAuthorizationStatusNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self setupMapBoundingBoxAnimated:NO];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupTiledMapView
{
    [self.tiledMapView setMapDelegate:self];
    [self.tiledMapView setUserTrackingDelegate:self];
    
    MKMapView *mapView = self.tiledMapView.mapView;
    mapView.showsUserLocation = [MITLocationManager locationServicesAuthorized];
    mapView.tintColor = [UIColor mit_systemTintColor];
    
    // Set up annotations from stops
    NSMutableArray *annotations = [[NSMutableArray alloc] init];
    for (MITToursStop *stop in self.tour.stops) {
        MITToursStopAnnotation *annotation = [[MITToursStopAnnotation alloc] initWithStop:stop];
        [annotations addObject:annotation];
    }
    [mapView addAnnotations:annotations];
    [self.tiledMapView showRouteForStops:[self.tour.stops array]];
}

- (void)setupCalloutView
{
    MITCalloutView *calloutView = [MITCalloutView new];
    calloutView.delegate = self;
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        calloutView.permittedArrowDirections = MITCalloutArrowDirectionTop | MITCalloutArrowDirectionBottom;
    }
    self.calloutView = calloutView;
    [self updateCalloutViewInsets];
    
    MITCalloutMapView *mapView = self.tiledMapView.mapView;
    mapView.mitCalloutView = calloutView;
}

- (void)updateCalloutViewInsets
{
    if (!self.calloutView) {
        return;
    }
    CGFloat topInset = 0;
    if (self.shouldShowTourDetailsPanel) {
        topInset = self.tourDetailsHeightConstraint.constant;
    }
    self.calloutView.externalInsets = UIEdgeInsetsMake(topInset, 10, 10, 10);
}

- (void)setupMapBoundingBoxAnimated:(BOOL)animated
{
    MKMapView *mapView = self.tiledMapView.mapView;
    if (!MKMapRectIsNull(self.savedMapRect)) {
        [mapView setVisibleMapRect:self.savedMapRect animated:animated];
        return;
    }
    
    // TODO: This code was more-or-less copied from the dining module map setup. Consider sharing
    // the code to DRY this out.
    if ([mapView.annotations count] > 0) {
        MKMapRect zoomRect = MKMapRectNull;
        for (id <MKAnnotation> annotation in mapView.annotations)
        {
            if (![annotation isKindOfClass:[MITToursStopAnnotation class]]) {
                continue;
            }
            MKMapPoint annotationPoint = MKMapPointForCoordinate(annotation.coordinate);
            MKMapRect pointRect = MKMapRectMake(annotationPoint.x, annotationPoint.y, 0.1, 0.1);
            zoomRect = MKMapRectUnion(zoomRect, pointRect);
        }
        double inset = -zoomRect.size.width * 0.1;
        [mapView setVisibleMapRect:MKMapRectInset(zoomRect, inset, inset) animated:animated];
    } else {
        // TODO: Figure out what the default region should be?
        [mapView setRegion:kMITShuttleDefaultMapRegion animated:animated];
    }
}

- (void)saveCurrentMapRect
{
    self.savedMapRect = self.tiledMapView.mapView.visibleMapRect;
}

#pragma mark - Tour Details

- (void)setupTourDetailsView
{
    self.tourDetailsView.hidden = !self.shouldShowTourDetailsPanel;

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tourDetailsViewWasTapped:)];
    [self.tourDetailsView addGestureRecognizer:tapRecognizer];
}

- (void)setShouldShowTourDetailsPanel:(BOOL)shouldShowTourDetailsPanel
{
    _shouldShowTourDetailsPanel = shouldShowTourDetailsPanel;
    self.tourDetailsView.hidden = !shouldShowTourDetailsPanel;
    [self updateCalloutViewInsets];
}

- (void)tourDetailsViewWasTapped:(UITapGestureRecognizer *)sender
{
    if ([self.delegate respondsToSelector:@selector(mapViewControllerDidPressInfoButton:)]) {
        [self.delegate mapViewControllerDidPressInfoButton:self];
    }
}

#pragma mark - Programmatically Triggered Stop Selection

- (MITToursStopAnnotation *)annotationForStop:(MITToursStop *)stop
{
    MITToursStopAnnotation *annotationForStop = nil;
    for (id<MKAnnotation> annotation in self.tiledMapView.mapView.annotations) {
        if (![annotation isKindOfClass:[MITToursStopAnnotation class]]) {
            continue;
        }
        if (((MITToursStopAnnotation *)annotation).stop == stop) {
            annotationForStop = annotation;
        }
    }
    return annotationForStop;
}

- (void)selectStop:(MITToursStop *)stop
{
    MITToursStopAnnotation *annotation = [self annotationForStop:stop];
    if (!annotation) {
        return;
    }
    [self.tiledMapView.mapView selectAnnotation:annotation animated:YES];
}

- (void)deselectStop:(MITToursStop *)stop
{
    MITToursStopAnnotation *annotation = [self annotationForStop:stop];
    if (!annotation) {
        return;
    }
    [self.tiledMapView.mapView deselectAnnotation:annotation animated:YES];
}

#pragma mark - MKMapViewDelegate Methods

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation
{
    if (![annotation isKindOfClass:[MITToursStopAnnotation class]]) {
        return nil;
    }
    
    MITMapPlaceAnnotationView *annotationView = (MITMapPlaceAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:kMITToursStopAnnotationViewIdentifier];
    if (!annotationView) {
        annotationView = [[MITMapPlaceAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:kMITToursStopAnnotationViewIdentifier];
        annotationView.canShowCallout = NO;
    }
    
    MITToursStop *stop = ((MITToursStopAnnotation *)annotation).stop;
    NSInteger number = [self.tour.stops indexOfObject:stop];
    
    if ([stop.stopType isEqualToString:@"Main Loop"]) {
        [annotationView setRedColor];
    } else {
        [annotationView setBlueColor];
    }
    [annotationView setNumber:(number + 1)];

    return annotationView;
}

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view
{
    if (![view.annotation isKindOfClass:[MITToursStopAnnotation class]]) {
        return;
    }
    [self presentCalloutForMapView:mapView annotationView:view];
    if ([self.delegate respondsToSelector:@selector(mapViewController:didSelectStop:)]) {
        MITToursStop *stop = ((MITToursStopAnnotation *)view.annotation).stop;
        [self.delegate mapViewController:self didSelectStop:stop];
    }
}

- (void)mapView:(MKMapView *)mapView didDeselectAnnotationView:(MKAnnotationView *)view
{
    [self dismissCurrentCallout];
    if ([self.delegate respondsToSelector:@selector(mapViewController:didDeselectStop:)] &&
        [view.annotation isKindOfClass:[MITToursStopAnnotation class]]) {
        MITToursStop *stop = ((MITToursStopAnnotation *)view.annotation).stop;
        [self.delegate mapViewController:self didDeselectStop:stop];
    }
}

#pragma mark - MITTiledMapViewUserTrackingDelegate

- (void)mitTiledMapView:(MITTiledMapView *)mitTiledMapView didChangeUserTrackingMode:(MKUserTrackingMode)mode animated:(BOOL)animated
{
    if ([self.delegate respondsToSelector:@selector(mapViewController:didChangeUserTrackingMode:animated:)]) {
        [self.delegate mapViewController:self didChangeUserTrackingMode:mode animated:animated];
    }
}

#pragma mark - Custom Callout

- (void)presentCalloutForMapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)annotationView
{
    MITToursStop *stop = ((MITToursStopAnnotation *)annotationView.annotation).stop;
    
    MITToursCalloutContentView *contentView = [[MITToursCalloutContentView alloc] initWithFrame:CGRectZero];
    [contentView configureForStop:stop userLocation:mapView.userLocation.location];
    
    MITCalloutView *calloutView = self.calloutView;
    calloutView.internalInsets = UIEdgeInsetsZero;
    calloutView.contentView = contentView;
    calloutView.contentViewPreferredSize = contentView.bounds.size;
    
    CGRect bounds = annotationView.bounds;
    bounds.size.width /= 2.0;
    [calloutView presentFromRect:bounds inView:annotationView withConstrainingView:self.tiledMapView.mapView];
}

- (void)dismissCurrentCallout
{
    [self.calloutView dismissCallout];
}

#pragma mark - MITCalloutViewDelegate

- (void)calloutView:(MITCalloutView *)calloutView positionedOffscreenWithOffset:(CGPoint)offscreenOffset
{
    MKMapView *mapView = self.tiledMapView.mapView;
    CGPoint adjustedCenter = CGPointMake(offscreenOffset.x + mapView.bounds.size.width * 0.5,
                                         offscreenOffset.y + mapView.bounds.size.height * 0.5);
    CLLocationCoordinate2D newCenter = [mapView convertPoint:adjustedCenter toCoordinateFromView:mapView];
    [mapView setCenterCoordinate:newCenter animated:YES];
}

- (void)calloutViewTapped:(MITCalloutView *)calloutView
{
    MITToursCalloutContentView *contentView = (MITToursCalloutContentView *)calloutView.contentView;
    if ([self.delegate respondsToSelector:@selector(mapViewController:didSelectCalloutForStop:)]) {
        [self.delegate mapViewController:self didSelectCalloutForStop:contentView.stop];
    }
}

- (void)calloutViewRemovedFromViewHierarchy:(MITCalloutView *)calloutView
{
    
}

#pragma mark - User Location Centering

- (BOOL)isTrackingUser
{
    return self.tiledMapView.isTrackingUser;
}

#pragma mark - Location Notifications

- (void)locationManagerDidUpdateAuthorizationStatus:(NSNotification *)notification
{
    self.tiledMapView.mapView.showsUserLocation = [MITLocationManager locationServicesAuthorized];
}

@end

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "MITManagedObject.h"
#import "MITMappedObject.h"
#import <MapKit/MapKit.h>

@class MITShuttleRoute, MITShuttleVehicleList, MITShuttlePrediction;

extern NSString * const kMITShuttleVehicleCoordinateUpdatedNotification;

@interface MITShuttleVehicle : MITManagedObject <MITMappedObject, MKAnnotation>

@property (nonatomic, retain) NSNumber * heading;
@property (nonatomic, retain) NSString * identifier;
@property (nonatomic, retain) NSNumber * latitude;
@property (nonatomic, retain) NSNumber * longitude;
@property (nonatomic, retain) NSNumber * secondsSinceReport;
@property (nonatomic, retain) NSNumber * speedKph;
@property (nonatomic, retain) MITShuttleRoute *route;
@property (nonatomic, retain) MITShuttleVehicleList *vehicleList;
@property (nonatomic, retain) NSSet *predictions;

- (void)setCoordinate:(CLLocationCoordinate2D)newCoordinate;
- (NSString *)routeTitle;

@end

@interface MITShuttleVehicle (CoreDataGeneratedAccessors)
- (void)addPredictionsObject:(MITShuttlePrediction *)value;
- (void)removePredictionsObject:(MITShuttlePrediction *)value;
- (void)addPredictions:(NSSet *)value;
- (void)removePredictions:(NSSet *)value;

@end

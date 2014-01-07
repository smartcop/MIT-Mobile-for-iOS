#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class MITNewsImageRepresentation, MITNewsStory;

@interface MITNewsImage : NSManagedObject

@property (nonatomic, retain) NSString * credits;
@property (nonatomic, retain) NSString * caption;
@property (nonatomic, retain) NSNumber * primary;
@property (nonatomic, retain) NSSet *representations;
@property (nonatomic, retain) MITNewsStory *story;

+ (NSString*)entityName;
@end

@interface MITNewsImage (CoreDataGeneratedAccessors)

- (void)addRepresentationsObject:(MITNewsImageRepresentation *)value;
- (void)removeRepresentationsObject:(MITNewsImageRepresentation *)value;
- (void)addRepresentations:(NSSet *)values;
- (void)removeRepresentations:(NSSet *)values;

@end
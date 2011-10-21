#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface NSString (MITUIAdditions)

- (NSInteger)lengthOfLineWithFont:(UIFont *)font constrainedToSize:(CGSize)size;

@end

@interface UIColor (MITUIAdditions)

+ (UIColor *)colorWithHexString:(NSString *)hexString;

@end

@interface UIImageView (MITUIAdditions)

+ (UIImageView *)accessoryViewWithMITType:(MITAccessoryViewType)type;
+ (UIImageView *)accessoryViewForInternalURL:(NSString *)url;

@end

@interface UIView (MITUIAdditions)

- (void)removeAllSubviews;

@end

@interface UITableViewCell (MITUIAdditions)

- (CGFloat)widthForContentViewThatFits:(CGFloat)width;
- (void)applyStandardFonts;
- (void)addAccessoryImage:(UIImage *)image;

@end

@interface UITableView (MITUIAdditions)

- (void)applyStandardColors;
- (void)applyStandardCellHeight;
+ (UIView *)groupedSectionHeaderWithTitle:(NSString *)title;
+ (UIView *)ungroupedSectionHeaderWithTitle:(NSString *)title;

@end

@interface UIActionSheet (MITUIAdditions)

- (void)showFromAppDelegate; // i don't like this name but can't think of a better one

@end

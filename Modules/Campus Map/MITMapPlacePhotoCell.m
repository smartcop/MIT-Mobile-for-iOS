#import "MITMapPlacePhotoCell.h"
#import "MITMapPlace.h"
#import <SDWebImage/UIImageView+WebCache.h>

@interface MITMapPlacePhotoCell()

@end

@implementation MITMapPlacePhotoCell

- (void)awakeFromNib
{
    [super awakeFromNib];
    // Initialization code
    self.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)setPlace:(MITMapPlace *)place
{
    [self.photoImageView sd_setImageWithURL:place.imageURL completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        if (image){
            [self resizeImageView:image];
        }
    }];
    
    self.captionLabel.text = place.imageCaption;
}

- (void)resizeImageView:(UIImage *)image
{
    CGFloat padding = 10;
    CGSize maxImageViewSize = {.width = self.bounds.size.width - (2 * padding), .height = self.bounds.size.height - (2 * padding) - self.captionLabel.bounds.size.height - padding};
    
    CGSize imageSize = image.size;
    CGFloat aspectRatio = imageSize.width / imageSize.height;
    CGRect imageFrame = self.photoImageView.frame;
    if (maxImageViewSize.width / aspectRatio <= maxImageViewSize.height) {
        imageFrame.size.width = maxImageViewSize.width;
        imageFrame.size.height = imageFrame.size.width / aspectRatio;
    } else {
        imageFrame.size.height = maxImageViewSize.height;
        imageFrame.size.width = imageFrame.size.height * aspectRatio;
    }
    self.photoImageView.frame = imageFrame;
    
    CGRect captionFrame = self.captionLabel.frame;
    captionFrame.size.width = imageFrame.size.width;
    self.captionLabel.frame = captionFrame;
}

@end

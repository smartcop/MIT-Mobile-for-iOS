#import "MITLibrariesHoldingLibraryHeaderCell.h"
#import "UIKit+MITLibraries.h"

@implementation MITLibrariesHoldingLibraryHeaderCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    [self.libraryNameLabel setLibrariesTextStyle:MITLibrariesTextStyleTitle];
    [self.availableCopiesLabel setLibrariesTextStyle:MITLibrariesTextStyleSubtitle];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.separatorInset = UIEdgeInsetsMake(0, self.bounds.size.width, 0, 0);
}

@end

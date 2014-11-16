//
//  MITScannerAdvancedMenuViewController.m
//  MIT Mobile
//

#import "MITScannerAdvancedMenuViewController.h"
#import "UIKit+MITAdditions.h"
#import "MITBatchScanningCell.h"

NSString* const kBatchScanningSettingKey = @"kBatchScanningSettingKey";

@interface MITScannerAdvancedMenuViewController () <UITableViewDataSource, UITableViewDelegate>
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@end

@interface MITScannerAdvancedMenuViewController (BatchScanningCellHandler) <MITBatchScanningCellDelegate>

- (NSString *)descForMultipleScanSetting;
- (NSString *)descForSingleScanSetting;

@end

@implementation MITScannerAdvancedMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MITBatchScanningCell" bundle:nil] forCellReuseIdentifier:@"batchScanningCell"];
    
    self.title = @"Advanced";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissMenu:)];
}

// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return MITCanAutorotateForOrientation(interfaceOrientation, [self supportedInterfaceOrientations]);
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dismissMenu:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:NULL];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 100.;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MITBatchScanningCell *cell = [tableView dequeueReusableCellWithIdentifier:@"batchScanningCell" forIndexPath:indexPath];
    
    cell.delegate = self;
    
    BOOL doBatchScanning = [[NSUserDefaults standardUserDefaults] boolForKey:kBatchScanningSettingKey];
    [cell setBatchScanningToggleSwitch:doBatchScanning];
    
    NSString *settingDescText = doBatchScanning ? [self descForMultipleScanSetting] : [self descForSingleScanSetting];
    [cell updateSettingDescriptionWithText:settingDescText];
    
    return cell;
}

@end

@implementation MITScannerAdvancedMenuViewController (BatchScanningCellHandler)

- (void)toggleSwitchDidChangeValue:(UISwitch *)toggleSwitch inCell:(MITBatchScanningCell *)cell
{
    NSString *settingDescText = toggleSwitch.isOn ? [self descForMultipleScanSetting] : [self descForSingleScanSetting];
    
    [cell updateSettingDescriptionWithText:settingDescText];
    
    [[NSUserDefaults standardUserDefaults] setBool:toggleSwitch.isOn forKey:kBatchScanningSettingKey];
}

- (NSString *)descForMultipleScanSetting
{
    return @"The device is set to scan multiple codes in quick succession.";
}

- (NSString *)descForSingleScanSetting
{
    return @"The device is set to scan one code at a time.";
}

@end



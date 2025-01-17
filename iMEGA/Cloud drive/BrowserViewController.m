#import "BrowserViewController.h"

#import "SVProgressHUD.h"
#import "UIScrollView+EmptyDataSet.h"

#import "Helper.h"
#import "MEGACreateFolderRequestDelegate.h"
#import "MEGANodeList+MNZCategory.h"
#import "MEGAMoveRequestDelegate.h"
#import "MEGAReachabilityManager.h"
#import "NSFileManager+MNZCategory.h"
#import "NSMutableArray+MNZCategory.h"
#import "NSString+MNZCategory.h"
#import "UIAlertAction+MNZCategory.h"
#import "UIImageView+MNZCategory.h"
#import "UITextField+MNZCategory.h"

#import "NodeTableViewCell.h"

@interface BrowserViewController () <UISearchBarDelegate, UISearchResultsUpdating, UIViewControllerPreviewingDelegate, DZNEmptyDataSetSource, DZNEmptyDataSetDelegate, MEGADelegate, UISearchControllerDelegate>

@property (nonatomic) id<UIViewControllerPreviewing> previewingContext;
@property (nonatomic, getter=isParentBrowser) BOOL parentBrowser;

@property (nonatomic, strong) MEGANodeList *nodes;
@property (nonatomic, strong) MEGAShareList *shares;

@property (nonatomic) MEGAShareType parentShareType;

@property (nonatomic) NSUInteger remainingOperations;

@property (weak, nonatomic) IBOutlet UIView *browserSegmentedControlView;
@property (weak, nonatomic) IBOutlet UISegmentedControl *browserSegmentedControl;

@property (weak, nonatomic) IBOutlet UIView *extendedNavigationBar_view;
@property (weak, nonatomic) IBOutlet UIButton *extendedNavigationBar_backButton;
@property (weak, nonatomic) IBOutlet UILabel *extendedNavigationBar_label;

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *tableViewTopConstraint;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *cancelBarButtonItem;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *toolBarNewFolderBarButtonItem;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *toolBarMoveBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *toolBarCopyBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *toolBarSaveInMegaBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *toolbarSendBarButtonItem;

@property (nonatomic) NSMutableArray *searchNodesArray;
@property (nonatomic) UISearchController *searchController;

@end

@implementation BrowserViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //White background for the view behind the table view
    self.tableView.backgroundView = UIView.alloc.init;
    
    self.tableView.emptyDataSetSource = self;
    self.tableView.emptyDataSetDelegate = self;
    
    [self setupBrowser];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(internetConnectionChanged) name:kReachabilityChangedNotification object:nil];
    
    [[MEGASdkManager sharedMEGASdk] addMEGADelegate:self];
    [[MEGAReachabilityManager sharedManager] retryPendingConnections];
    
    if (self.searchController && !self.tableView.tableHeaderView) {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    [self reloadUI];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if (self.searchController.isActive) {
        self.searchController.active = NO;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    
    [[MEGASdkManager sharedMEGASdk] removeMEGADelegate:self];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.tableView reloadEmptyDataSet];
        if (self.searchController.isActive) {
            float yCorrection = self.browserSegmentedControlView.hidden ? 0 : 44;
            
            self.searchController.view.frame = CGRectMake(0, UIApplication.sharedApplication.statusBarFrame.size.height + self.navigationController.navigationBar.frame.size.height + yCorrection, self.searchController.view.frame.size.width, self.searchController.view.frame.size.height);
            self.searchController.searchBar.superview.frame = CGRectMake(0, 0, self.searchController.searchBar.superview.frame.size.width, self.searchController.searchBar.superview.frame.size.height);
        }
    } completion:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)]) {
        if (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable) {
            if (!self.previewingContext) {
                self.previewingContext = [self registerForPreviewingWithDelegate:self sourceView:self.view];
            }
        } else {
            [self unregisterForPreviewingWithContext:self.previewingContext];
            self.previewingContext = nil;
        }
    }
}

#pragma mark - Private

- (void)setupBrowser {
    self.parentBrowser = !self.isChildBrowser;
    
    self.cancelBarButtonItem.title = AMLocalizedString(@"cancel", nil);
    
    UIBarButtonItem *flexibleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    
    switch (self.browserAction) {
        case BrowserActionCopy: {
            [self setupDefaultElements];
            
            self.toolBarCopyBarButtonItem.title = AMLocalizedString(@"copy", @"List option shown on the details of a file or folder");
            [self.toolBarCopyBarButtonItem setTitleTextAttributes:@{NSFontAttributeName:[UIFont mnz_SFUIMediumWithSize:17.0f]} forState:UIControlStateNormal];
            [self setToolbarItems:@[self.toolBarNewFolderBarButtonItem, flexibleItem, self.toolBarCopyBarButtonItem]];
            break;
        }
            
        case BrowserActionMove: {
            [self setupDefaultElements];
            
            self.toolBarMoveBarButtonItem.title = AMLocalizedString(@"move", @"Title for the action that allows you to move a file or folder");
            [self.toolBarMoveBarButtonItem setTitleTextAttributes:@{NSFontAttributeName:[UIFont mnz_SFUIMediumWithSize:17.0f]} forState:UIControlStateNormal];
            [self setToolbarItems:@[self.toolBarNewFolderBarButtonItem, flexibleItem, self.toolBarMoveBarButtonItem]];
            break;
        }
            
        case BrowserActionImport:
        case BrowserActionImportFromFolderLink: {
            [self setupDefaultElements];
            
            self.toolBarCopyBarButtonItem.title = AMLocalizedString(@"import", @"Button title that triggers the importing link action");
            [self.toolBarCopyBarButtonItem setTitleTextAttributes:@{NSFontAttributeName:[UIFont mnz_SFUIMediumWithSize:17.0f]}  forState:UIControlStateNormal];
            [self setToolbarItems:@[self.toolBarNewFolderBarButtonItem, flexibleItem, self.toolBarCopyBarButtonItem]];
            break;
        }
            
        case BrowserActionOpenIn: {
            [self setupDefaultElements];
            
            self.toolBarSaveInMegaBarButtonItem.title = AMLocalizedString(@"upload", nil);
            [self.toolBarSaveInMegaBarButtonItem setTitleTextAttributes:@{NSFontAttributeName:[UIFont mnz_SFUIMediumWithSize:17.0f]} forState:UIControlStateNormal];
            [self setToolbarItems:@[self.toolBarNewFolderBarButtonItem, flexibleItem, self.toolBarSaveInMegaBarButtonItem]];
            break;
        }
            
        case BrowserActionShareExtension: {
            [self setupDefaultElements];
            
            self.navigationItem.rightBarButtonItem = nil;
            self.toolBarSaveInMegaBarButtonItem.title = AMLocalizedString(@"upload", nil);
            [self.toolBarSaveInMegaBarButtonItem setTitleTextAttributes:@{NSFontAttributeName:[UIFont mnz_SFUIMediumWithSize:17.0f]} forState:UIControlStateNormal];
            [self setToolbarItems:@[self.toolBarNewFolderBarButtonItem, flexibleItem, self.toolBarSaveInMegaBarButtonItem]];
            break;
        }

        case BrowserActionSendFromCloudDrive: {
            [self setupDefaultElements];
            
            self.toolbarSendBarButtonItem.title = AMLocalizedString(@"send", @"Label for any 'Send' button, link, text, title, etc. - (String as short as possible).");
            [self.toolbarSendBarButtonItem setTitleTextAttributes:@{NSFontAttributeName:[UIFont mnz_SFUIMediumWithSize:17.0f]} forState:UIControlStateNormal];
             [self setToolbarItems:@[flexibleItem, self.toolbarSendBarButtonItem]];
            
            if (self.isParentBrowser) {
                self.selectedNodesMutableDictionary = [[NSMutableDictionary alloc] init];
            }
            
            [self.tableView setEditing:YES];
            break;
        }
            
        case BrowserActionDocumentProvider: {
            if (self.isChildBrowser) {
                [self.browserSegmentedControlView addSubview:self.extendedNavigationBar_view];
            }
            
            self.navigationController.toolbarHidden = YES;
            break;
        }
    }
    
    [self addSearchController];
}

- (void)setupDefaultElements {
    if (self.parentBrowser) {
        [self.browserSegmentedControl setTitle:AMLocalizedString(@"cloudDrive", @"Title of the Cloud Drive section") forSegmentAtIndex:0];
        [self.browserSegmentedControl setTitle:AMLocalizedString(@"incoming", @"Title of the 'Incoming' Shared Items.") forSegmentAtIndex:1];
    } else {
        self.browserSegmentedControlView.hidden = YES;
        self.tableViewTopConstraint.constant = -self.browserSegmentedControlView.frame.size.height;
    }
    
    self.toolBarNewFolderBarButtonItem.title = AMLocalizedString(@"newFolder", @"Menu option from the `Add` section that allows you to create a 'New Folder'");
    [self.toolBarNewFolderBarButtonItem setTitleTextAttributes:@{NSFontAttributeName:[UIFont mnz_SFUIRegularWithSize:17.0f]} forState:UIControlStateNormal];
}

- (void)reloadUI {
    [self setParentNodeForBrowserAction];
    [self setNavigationBarTitle];
    
    BOOL enableToolbarItems = YES;
    switch (self.browserSegmentedControl.selectedSegmentIndex) {
        case 0: { //Cloud Drive
            if (self.browserAction == BrowserActionSendFromCloudDrive) {
                enableToolbarItems = self.selectedNodesMutableDictionary.count > 0;
            } else {
                self.parentShareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:self.parentNode];
                enableToolbarItems = self.parentShareType > MEGAShareTypeAccessRead;
            }
            break;
        }
            
        case 1: { //Incoming
            if (self.browserAction == BrowserActionSendFromCloudDrive) {
                enableToolbarItems = self.selectedNodesMutableDictionary.count > 0;
            } else {
                enableToolbarItems = NO;
            }
            break;
        }
    }
    [self setToolbarItemsEnabled:enableToolbarItems];
    
    [self.tableView reloadData];
}

- (void)setParentNodeForBrowserAction {
    switch (self.browserSegmentedControl.selectedSegmentIndex) {
        case 0: { //Cloud Drive
            if (self.isParentBrowser) {
                self.parentNode = [[MEGASdkManager sharedMEGASdk] rootNode];
                self.nodes = [[MEGASdkManager sharedMEGASdk] childrenForParent:[[MEGASdkManager sharedMEGASdk] rootNode]];
            } else {
                self.nodes = [[MEGASdkManager sharedMEGASdk] childrenForParent:self.parentNode];
            }
            break;
        }
            
        case 1: { //Incoming
            if (self.isParentBrowser) {
                self.parentNode = nil;
                self.nodes = [[MEGASdkManager sharedMEGASdk] inShares];
                self.shares = [[MEGASdkManager sharedMEGASdk] inSharesList];
            } else {
                self.nodes = [[MEGASdkManager sharedMEGASdk] childrenForParent:self.parentNode];
            }
            break;
        }
    }
}

- (void)setNavigationBarTitle {
    [self updatePromptTitle];
    
    if (self.isParentBrowser) {
        if (self.browserAction == BrowserActionDocumentProvider) {
            self.navigationItem.title = @"MEGA";
            self.extendedNavigationBar_label.text = AMLocalizedString(@"cloudDrive", @"Title of the Cloud Drive section");
        } else {
            self.navigationItem.title = (self.browserSegmentedControl.selectedSegmentIndex == 0) ? AMLocalizedString(@"cloudDrive", @"Title of the Cloud Drive section") : AMLocalizedString(@"sharedItems", @"Title of Shared Items section");
        }
    } else {
        if (self.isChildBrowserFromIncoming) {
            NSString *accessTypeString;
            switch (self.parentShareType) {
                case MEGAShareTypeAccessRead:
                    accessTypeString = AMLocalizedString(@"readOnly", @"Permissions given to the user you share your folder with");
                    break;
                    
                case MEGAShareTypeAccessReadWrite:
                    accessTypeString = AMLocalizedString(@"readAndWrite", @"Permissions given to the user you share your folder with");
                    break;
                    
                case MEGAShareTypeAccessFull:
                    accessTypeString = AMLocalizedString(@"fullAccess", @"Permissions given to the user you share your folder with");
                    break;
                    
                default:
                    accessTypeString = @"";
                    break;
            }
            
            if ([self.parentNode name] != nil) {
                UILabel *label = [Helper customNavigationBarLabelWithTitle:self.parentNode.name subtitle:accessTypeString];
                label.frame = CGRectMake(0, 0, self.navigationItem.titleView.bounds.size.width, 44);
                self.navigationItem.titleView = label;
            } else {
                self.navigationItem.title = [NSString stringWithFormat:@"(%@)", accessTypeString];
            }
        } else {
            if (self.browserAction == BrowserActionDocumentProvider) {
                self.navigationItem.title = @"MEGA";
                self.extendedNavigationBar_label.text = self.parentNode.name;
            } else {
                self.navigationItem.title = self.parentNode.name;
            }
        }
    }
}

- (void)updatePromptTitle {
    if (self.browserAction == BrowserActionSendFromCloudDrive) {
        NSString *promptString;
        if (self.selectedNodesMutableDictionary.count == 0) {
            promptString = AMLocalizedString(@"selectFiles", @"Text of the button for user to select files in MEGA.");
        } else {
            promptString = (self.selectedNodesMutableDictionary.count == 1) ? [NSString stringWithFormat:AMLocalizedString(@"oneItemSelected", @"Title shown on the Camera Uploads section when the edit mode is enabled and you have selected one photo"), self.selectedNodesMutableDictionary.count] : [NSString stringWithFormat:AMLocalizedString(@"itemsSelected", @"Title shown on the Camera Uploads section when the edit mode is enabled and you have selected more than one photo"), self.selectedNodesMutableDictionary.count];
        }
        self.navigationItem.prompt = promptString;
    } else if (self.browserAction != BrowserActionDocumentProvider && self.browserAction != BrowserActionShareExtension) {
        self.navigationItem.prompt = AMLocalizedString(@"selectDestination", @"Title shown on the navigation bar to explain that you have to choose a destination for the files and/or folders in case you copy, move, import or do some action with them.");
    }
}

- (void)internetConnectionChanged {
    [self reloadUI];
}

- (NSString *)successMessageForCopyAction {
    NSInteger files = 0;
    NSInteger folders = 0;
    for (MEGANode *n in self.selectedNodesArray) {
        if ([n type] == MEGANodeTypeFolder) {
            folders++;
        } else {
            files++;
        }
    }
    
    NSString *message;
    if (files == 0) {
        if (folders == 1) {
            message = AMLocalizedString(@"copyFolderMessage", nil);
        } else { //folders > 1
            message = [NSString stringWithFormat:AMLocalizedString(@"copyFoldersMessage", nil), folders];
        }
    } else if (files == 1) {
        if (folders == 0) {
            message = AMLocalizedString(@"copyFileMessage", nil);
        } else if (folders == 1) {
            message = AMLocalizedString(@"copyFileFolderMessage", nil);
        } else {
            message = [NSString stringWithFormat:AMLocalizedString(@"copyFileFoldersMessage", nil), folders];
        }
    } else {
        if (folders == 0) {
            message = [NSString stringWithFormat:AMLocalizedString(@"copyFilesMessage", nil), files];
        } else if (folders == 1) {
            message = [NSString stringWithFormat:AMLocalizedString(@"copyFilesFolderMessage", nil), files];
        } else {
            message = AMLocalizedString(@"copyFilesFoldersMessage", nil);
            NSString *filesString = [NSString stringWithFormat:@"%ld", (long)files];
            NSString *foldersString = [NSString stringWithFormat:@"%ld", (long)folders];
            message = [message stringByReplacingOccurrencesOfString:@"[A]" withString:filesString];
            message = [message stringByReplacingOccurrencesOfString:@"[B]" withString:foldersString];
        }
    }
    
    return message;
}

- (void)setToolbarItemsEnabled:(BOOL)boolValue {
    boolValue = boolValue && [MEGAReachabilityManager isReachable];
    
    self.toolBarNewFolderBarButtonItem.enabled = boolValue;
    
    MEGANode *firstNode = self.selectedNodesArray.firstObject;
    if ((self.browserAction == BrowserActionMove || self.browserAction == BrowserActionCopy) && self.parentNode.handle == firstNode.parentHandle) {
        self.toolBarMoveBarButtonItem.enabled = NO;
        self.toolBarCopyBarButtonItem.enabled = NO;
    } else {
        self.toolBarMoveBarButtonItem.enabled = boolValue;
        self.toolBarCopyBarButtonItem.enabled = boolValue;
    }
    self.toolBarSaveInMegaBarButtonItem.enabled = boolValue;
    self.toolbarSendBarButtonItem.enabled = boolValue;
}

- (void)setNodeTableViewCell:(NodeTableViewCell *)cell enabled:(BOOL)boolValue {
    cell.userInteractionEnabled = boolValue;
    cell.nameLabel.enabled = boolValue;
    cell.infoLabel.enabled = boolValue;
    boolValue ? (cell.thumbnailImageView.alpha = 1.0) : (cell.thumbnailImageView.alpha = 0.5);
}

- (void)pushBrowserWithParentNode:(MEGANode *)parentNode {
    BrowserViewController *browserVC = [self.storyboard instantiateViewControllerWithIdentifier:@"BrowserViewControllerID"];
    browserVC.browserAction = self.browserAction;
    browserVC.childBrowser = YES;
    browserVC.childBrowserFromIncoming = ((self.browserSegmentedControl.selectedSegmentIndex == 1) || self.isChildBrowserFromIncoming) ? YES : NO;
    browserVC.localpath = self.localpath;
    browserVC.parentNode = parentNode;
    browserVC.selectedNodesMutableDictionary = self.selectedNodesMutableDictionary;
    browserVC.selectedNodesArray = self.selectedNodesArray;
    browserVC.browserViewControllerDelegate = self.browserViewControllerDelegate;
    
    [self.navigationController pushViewController:browserVC animated:YES];

    if (self.searchController.isActive) {
        self.searchController.active = NO;
    }
}

- (void)attachNodes {
    self.selectedNodes(self.selectedNodesMutableDictionary.allValues.copy);
    [self dismiss];
}

- (void)newFolderAlertTextFieldDidChange:(UITextField *)textField {
    UIAlertController *alertController = (UIAlertController *)self.presentedViewController;
    if (alertController) {
        BOOL containsInvalidChars = textField.text.mnz_containsInvalidChars;
        textField.textColor = containsInvalidChars ? UIColor.mnz_redMain : UIColor.darkTextColor;
        UIAlertAction *rightButtonAction = alertController.actions.lastObject;
        rightButtonAction.enabled = !textField.text.mnz_isEmpty && !containsInvalidChars;
    }
}

- (void)addSearchController {
    self.searchController = [Helper customSearchControllerWithSearchResultsUpdaterDelegate:self searchBarDelegate:self];
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    self.searchController.delegate = self;
    self.tableView.tableHeaderView = self.searchController.searchBar;
    [self.tableView setContentOffset:CGPointMake(0, CGRectGetHeight(self.searchController.searchBar.frame))];
    self.definesPresentationContext = YES;
}

- (MEGANode *)nodeAtIndexPath:(NSIndexPath *)indexPath {
    return self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
}

- (void)dismiss {
    if (self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - IBActions

- (IBAction)browserSegmentedControl:(UISegmentedControl *)sender {
    [self reloadUI];
}

- (IBAction)moveNode:(UIBarButtonItem *)sender {
    if ([MEGAReachabilityManager isReachableHUDIfNot]) {
        NSMutableArray *selectedNodesMutableArray = self.selectedNodesArray.mutableCopy;
        NSArray *filesAndFolders = selectedNodesMutableArray.mnz_numberOfFilesAndFolders;
        MEGAMoveRequestDelegate *moveRequestDelegate = [[MEGAMoveRequestDelegate alloc] initWithFiles:[filesAndFolders[0] unsignedIntegerValue] folders:[filesAndFolders[1] unsignedIntegerValue] completion:^{
            [self dismiss];
        }];
        
        for (MEGANode *n in self.selectedNodesArray) {
            [[MEGASdkManager sharedMEGASdk] moveNode:n newParent:self.parentNode delegate:moveRequestDelegate];
        }
    }
}

- (IBAction)copyNode:(UIBarButtonItem *)sender {
    if ([MEGAReachabilityManager isReachableHUDIfNot]) {
        [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeClear];
        [SVProgressHUD show];
        for (MEGANode *node in self.selectedNodesArray) {
            self.remainingOperations++;
            MEGANode *tempNode = (self.browserAction == BrowserActionImportFromFolderLink) ? [[MEGASdkManager sharedMEGASdkFolder] authorizeNode:node] : node;
            [[MEGASdkManager sharedMEGASdk] copyNode:tempNode newParent:self.parentNode];
        }
    }
}

- (IBAction)newFolder:(UIBarButtonItem *)sender {
    UIAlertController *newFolderAlertController = [UIAlertController alertControllerWithTitle:AMLocalizedString(@"newFolder", @"Menu option from the `Add` section that allows you to create a 'New Folder'") message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [newFolderAlertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = AMLocalizedString(@"newFolderMessage", @"Hint text shown on the create folder alert.");
        [textField addTarget:self action:@selector(newFolderAlertTextFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        textField.shouldReturnCompletion = ^BOOL(UITextField *textField) {
            return (!textField.text.mnz_isEmpty && !textField.text.mnz_containsInvalidChars);
        };
    }];
    
    [newFolderAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
    
    UIAlertAction *createFolderAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"createFolderButton", @"Title button for the create folder alert.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if ([MEGAReachabilityManager isReachableHUDIfNot]) {
            UITextField *textField = [[newFolderAlertController textFields] firstObject];
            MEGANodeList *childrenNodeList = [[MEGASdkManager sharedMEGASdk] nodeListSearchForNode:self.parentNode searchString:textField.text recursive:NO];
            if ([childrenNodeList mnz_existsFolderWithName:textField.text]) {
                [SVProgressHUD showErrorWithStatus:AMLocalizedString(@"There is already a folder with the same name", @"A tooltip message which is shown when a folder name is duplicated during renaming or creation.")];
            } else {
                MEGACreateFolderRequestDelegate *createFolderRequestDelegate = [[MEGACreateFolderRequestDelegate alloc] initWithCompletion:^(MEGARequest *request) {
                    MEGANode *newFolderNode = [[MEGASdkManager sharedMEGASdk] nodeForHandle:request.nodeHandle];
                    [self pushBrowserWithParentNode:newFolderNode];
                }];
                
                [[MEGASdkManager sharedMEGASdk] createFolderWithName:textField.text parent:self.parentNode delegate:createFolderRequestDelegate];
            }
        }
    }];
    createFolderAlertAction.enabled = NO;
    [newFolderAlertController addAction:createFolderAlertAction];
    
    [self presentViewController:newFolderAlertController animated:YES completion:nil];
}

- (IBAction)cancel:(UIBarButtonItem *)sender {
    if (self.browserAction == BrowserActionOpenIn) {
        NSString *inboxDirectory = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Inbox"];
        [NSFileManager.defaultManager mnz_removeFolderContentsAtPath:inboxDirectory];
    }
    
    [self dismiss];
}

- (IBAction)uploadToMega:(UIBarButtonItem *)sender {
    if (self.browserAction == BrowserActionOpenIn) {
        if ([MEGAReachabilityManager isReachableHUDIfNot]) {
            NSError *error = nil;
            NSString *localFilePath = [[[NSFileManager defaultManager] uploadsDirectory] stringByAppendingPathComponent:self.localpath.lastPathComponent];
            if ([[NSFileManager defaultManager] moveItemAtPath:self.localpath toPath:localFilePath error:&error]) {
                [SVProgressHUD showSuccessWithStatus:AMLocalizedString(@"uploadStarted_Message", @"Message shown when uploading a file from the Open In Browser")];
                
                NSString *appData = [[NSString new] mnz_appDataToSaveCoordinates:localFilePath.mnz_coordinatesOfPhotoOrVideo];
                [[MEGASdkManager sharedMEGASdk] startUploadWithLocalPath:localFilePath.mnz_relativeLocalPath parent:self.parentNode appData:appData isSourceTemporary:YES];
            } else {
                MEGALogError(@"Move item at path failed with error: %@", error);
                NSString *status = [NSString stringWithFormat:@"Move item failed with error %@", error];
                [SVProgressHUD showErrorWithStatus:status];
            }
            
            [self dismiss];
        }
    } else if (self.browserAction == BrowserActionShareExtension) {
        [self.browserViewControllerDelegate uploadToParentNode:self.parentNode];
    }
}

- (IBAction)extendedNavigationBar_backButtonTapped:(UIButton *)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)sendNodes:(UIBarButtonItem *)sender {
    if ([MEGAReachabilityManager isReachableHUDIfNot]) {
        if (self.selectedNodesMutableDictionary.count > 0) {
            if (self.isParentBrowser) {
                [self attachNodes];
            } else {
                BrowserViewController *browserVC = self.navigationController.viewControllers.firstObject;
                [browserVC attachNodes];
            }
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger numberOfRows = 0;
    if ([MEGAReachabilityManager isReachable]) {
        numberOfRows = self.searchController.isActive ? self.searchNodesArray.count : self.nodes.size.integerValue;
    }
    
    return numberOfRows;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellIdentifier;
    if (self.browserSegmentedControl.selectedSegmentIndex == 0) {
        cellIdentifier = @"nodeCell";
    } else if (self.browserSegmentedControl.selectedSegmentIndex == 1) {
        cellIdentifier = @"incomingNodeCell";
    }
    
    NodeTableViewCell *cell;
    cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    if (cell == nil) {
        cell = [[NodeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    MEGANode *node = [self nodeAtIndexPath:indexPath];
    MEGAShareType shareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:node];
    
    if (self.browserAction == BrowserActionSendFromCloudDrive) {
        [self.selectedNodesMutableDictionary objectForKey:node.base64Handle] ? [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone] : [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
    } else if (self.browserAction == BrowserActionDocumentProvider) {
        //TODO: Document Provider
    } else {
        if (node.isFile) {
            [self setNodeTableViewCell:cell enabled:NO];
        } else {
            (shareType == MEGAShareTypeAccessRead) ? [self setNodeTableViewCell:cell enabled:NO] : [self setNodeTableViewCell:cell enabled:YES];
        }
    }
    
    if (node.hasThumbnail) {
        [Helper thumbnailForNode:node api:[MEGASdkManager sharedMEGASdk] cell:cell];
    } else {
        [cell.thumbnailImageView mnz_imageForNode:node];
    }
    
    cell.nameLabel.text = node.name;
    
    cell.node = node;
    
    if (self.browserSegmentedControl.selectedSegmentIndex == 0) {
        if (node.isFile) {
            cell.infoLabel.text = [Helper sizeAndDateForNode:node api:[MEGASdkManager sharedMEGASdk]];
        } else {
            cell.infoLabel.text = [Helper filesAndFoldersInFolderNode:node api:[MEGASdkManager sharedMEGASdk]];
        }
    } else if (self.browserSegmentedControl.selectedSegmentIndex == 1) {
        MEGAShare *share = [self.shares shareAtIndex:indexPath.row];
        cell.infoLabel.text = [share user];
        [cell.cancelButton setImage:[Helper permissionsButtonImageForShareType:shareType] forState:UIControlStateNormal];
    }
    
    if (@available(iOS 11.0, *)) {
        cell.thumbnailImageView.accessibilityIgnoresInvertColors = YES;
        cell.thumbnailPlayImageView.accessibilityIgnoresInvertColors = YES;
    }
    
    if (tableView.isEditing) {
        UIView *view = [[UIView alloc] init];
        view.backgroundColor = UIColor.clearColor;
        cell.selectedBackgroundView = view;
    }
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.browserAction == BrowserActionSendFromCloudDrive) {
        MEGANode *node = [self nodeAtIndexPath:indexPath];
        return node.isFile;
    } else {
        return YES;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MEGANode *selectedNode = [self nodeAtIndexPath:indexPath];
    
    if (selectedNode.isFolder) {
        [self pushBrowserWithParentNode:selectedNode];
    } else {
        switch (self.browserAction) {
            case BrowserActionSendFromCloudDrive: {
                [self.selectedNodesMutableDictionary setObject:selectedNode forKey:selectedNode.base64Handle];
                [self updatePromptTitle];
                [self setToolbarItemsEnabled:YES];
                return;
            }
                
            case BrowserActionDocumentProvider: {
                [SVProgressHUD setViewForExtension:self.view];
                [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeClear];
                [SVProgressHUD show];
                [self.browserViewControllerDelegate didSelectNode:selectedNode];
                break;
            }
                
            default:
                break;
        }
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    if (self.browserAction == BrowserActionSendFromCloudDrive) {
        MEGANode *deselectedNode = [self nodeAtIndexPath:indexPath];
        if ([self.selectedNodesMutableDictionary objectForKey:deselectedNode.base64Handle]) {
            [self.selectedNodesMutableDictionary removeObjectForKey:deselectedNode.base64Handle];
            [self updatePromptTitle];
            [self setToolbarItemsEnabled:self.selectedNodesMutableDictionary.count];
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.browserAction == BrowserActionSendFromCloudDrive) {
        MEGANode *node = [self nodeAtIndexPath:indexPath];
        return node.isFile;
    } else {
        return YES;
    }
}

#pragma mark - UISearchBarDelegate

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    self.searchNodesArray = nil;
    self.browserSegmentedControl.enabled = YES;
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchString = searchController.searchBar.text;
    if (searchController.isActive) {
        if ([searchString isEqualToString:@""]) {
            self.searchNodesArray = [self.nodes.mnz_nodesArrayFromNodeList mutableCopy];
        } else {
            if (self.browserSegmentedControl.selectedSegmentIndex == 0) {
                MEGANodeList *allNodeList = [[MEGASdkManager sharedMEGASdk] nodeListSearchForNode:self.parentNode searchString:searchString recursive:NO];
                self.searchNodesArray = [allNodeList.mnz_nodesArrayFromNodeList mutableCopy];
            } else {
                NSPredicate *resultPredicate = [NSPredicate predicateWithFormat:@"SELF.name contains[c] %@", searchString];
                self.searchNodesArray = [[self.nodes.mnz_nodesArrayFromNodeList filteredArrayUsingPredicate:resultPredicate] mutableCopy];
            }
        }
        self.browserSegmentedControl.enabled = NO;
    }
    
    [self.tableView reloadData];
}

#pragma mark - UISearchControllerDelegate

- (void)didPresentSearchController:(UISearchController *)searchController {
    float yPosition = self.browserSegmentedControlView.hidden ? 0 : 44;
    self.searchController.searchBar.superview.frame = CGRectMake(0, yPosition, self.searchController.searchBar.superview.frame.size.width, self.searchController.searchBar.superview.frame.size.height);
}

#pragma mark - UIViewControllerPreviewingDelegate

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location {
    CGPoint rowPoint = [self.tableView convertPoint:location fromView:self.view];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:rowPoint];
    if (!indexPath || ![self.tableView numberOfRowsInSection:indexPath.section]) {
        return nil;
    }
    
    MEGANode *node = [self.nodes nodeAtIndex:indexPath.row];
    previewingContext.sourceRect = [self.tableView convertRect:[self.tableView cellForRowAtIndexPath:indexPath].frame toView:self.view];
    
    switch (node.type) {
        case MEGANodeTypeFolder: {
            BrowserViewController *browserVC = [self.storyboard instantiateViewControllerWithIdentifier:@"BrowserViewControllerID"];
            browserVC.browserAction = self.browserAction;
            browserVC.childBrowser = YES;
            browserVC.childBrowserFromIncoming = ((self.browserSegmentedControl.selectedSegmentIndex == 1) || self.isChildBrowserFromIncoming) ? YES : NO;
            browserVC.localpath = self.localpath;
            browserVC.parentNode = node;
            browserVC.selectedNodesMutableDictionary = self.selectedNodesMutableDictionary;
            browserVC.selectedNodesArray = self.selectedNodesArray;
            browserVC.browserViewControllerDelegate = self.browserViewControllerDelegate;
            
            return browserVC;
        }
            
        default:
            break;
    }
    
    return nil;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit {
    if (viewControllerToCommit.class == BrowserViewController.class) {
        [self.navigationController pushViewController:viewControllerToCommit animated:YES];
    }
}

#pragma mark - DZNEmptyDataSetSource

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView {
    NSString *text = @"";
    if ([MEGAReachabilityManager isReachable]) {
        if (self.searchController.isActive) {
            if (self.searchController.searchBar.text.length > 0) {
                text = AMLocalizedString(@"noResults", @"Title shown when you make a search and there is 'No Results'");
            }
        } else {
            if ((self.browserSegmentedControl.selectedSegmentIndex == 1) && self.isParentBrowser) {
                text = AMLocalizedString(@"noIncomingSharedItemsEmptyState_text", @"Title shown when there's no incoming Shared Items");
            } else {
                text = AMLocalizedString(@"emptyFolder", @"Title shown when a folder doesn't have any files");
            }
        }
    } else {
        text = AMLocalizedString(@"noInternetConnection",  @"Text shown on the app when you don't have connection to the internet or when you have lost it");
    }
    
    return [[NSAttributedString alloc] initWithString:text attributes:[Helper titleAttributesForEmptyState]];
}

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView {
    UIImage *image = nil;
    if ([MEGAReachabilityManager isReachable]) {
        if (self.searchController.isActive) {
            if (self.searchController.searchBar.text.length > 0) {
                return [UIImage imageNamed:@"searchEmptyState"];
            } else {
                return nil;
            }
        } else {
            if ((self.browserSegmentedControl.selectedSegmentIndex == 1) && self.isParentBrowser) {
                image = [UIImage imageNamed:@"incomingEmptyState"];
            } else {
                image = [UIImage imageNamed:@"folderEmptyState"];
            }
        }
    } else {
        image = [UIImage imageNamed:@"noInternetEmptyState"];
    }
    
    return image;
}

- (UIColor *)backgroundColorForEmptyDataSet:(UIScrollView *)scrollView {
    return [UIColor whiteColor];
}

- (CGFloat)verticalOffsetForEmptyDataSet:(UIScrollView *)scrollView {
    return [Helper verticalOffsetForEmptyStateWithNavigationBarSize:self.navigationController.navigationBar.frame.size searchBarActive:self.searchController.isActive];
}

- (CGFloat)spaceHeightForEmptyDataSet:(UIScrollView *)scrollView {
    return [Helper spaceHeightForEmptyState];
}

#pragma mark - MEGARequestDelegate

- (void)onRequestStart:(MEGASdk *)api request:(MEGARequest *)request {
    switch ([request type]) {
        case MEGARequestTypeCopy: {
            [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeClear];
            if (self.browserAction != BrowserActionSendFromCloudDrive) {
                [SVProgressHUD show];
            }
            break;
        }
            
        default:
            break;
    }
}

- (void)onRequestFinish:(MEGASdk *)api request:(MEGARequest *)request error:(MEGAError *)error {
    if ([error type]) {
        if (request.type == MEGARequestTypeCopy) {
            if (error.type == MEGAErrorTypeApiEOverQuota || error.type == MEGAErrorTypeApiEgoingOverquota) {
                [SVProgressHUD dismiss];
            } else {
                [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeNone];
                [SVProgressHUD showErrorWithStatus:error.name];
            }
        }
        return;
    }
    
    switch ([request type]) {
        case MEGARequestTypeCopy: {
            self.remainingOperations--;
            
            if (self.remainingOperations == 0) {
                [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeNone];
                
                if (self.browserAction == BrowserActionCopy) {
                    NSString *message = [self successMessageForCopyAction];
                    [SVProgressHUD showSuccessWithStatus:message];
                } else if (self.browserAction == BrowserActionImport) {
                    [SVProgressHUD showSuccessWithStatus:AMLocalizedString(@"fileImported", @"Message shown when a file has been imported")];
                } else if (self.browserAction == BrowserActionImportFromFolderLink) {
                    if ((_selectedNodesArray.count == 1) && ([[_selectedNodesArray objectAtIndex:0] isFile])) {
                        [SVProgressHUD showSuccessWithStatus:AMLocalizedString(@"fileImported", @"Message shown when a file has been imported")];
                    } else {
                        [SVProgressHUD showSuccessWithStatus:AMLocalizedString(@"filesImported", @"Message shown when some files have been imported")];
                    }
                    
                    [[MEGASdkManager sharedMEGASdkFolder] logout];
                }
                
                [self dismiss];
            }
            break;
        }
            
        case MEGARequestTypeGetAttrFile: {
            for (NodeTableViewCell *nodeTableViewCell in self.tableView.visibleCells) {
                if (request.nodeHandle == nodeTableViewCell.node.handle) {
                    MEGANode *node = [api nodeForHandle:request.nodeHandle];
                    [Helper setThumbnailForNode:node api:api cell:nodeTableViewCell reindexNode:YES];
                }
            }
            break;
        }
            
        default:
            break;
    }
}

#pragma mark - MEGAGlobalDelegate

- (void)onNodesUpdate:(MEGASdk *)api nodeList:(MEGANodeList *)nodeList {
    [self reloadUI];
}

@end


#import "MessagesViewController.h"

#import <UserNotifications/UserNotifications.h>

#import <PureLayout/PureLayout.h>
#import "NSDate+DateTools.h"
#import "SVProgressHUD.h"
#import "UIImage+GKContact.h"
#import "UIScrollView+EmptyDataSet.h"

#import "Helper.h"
#import "DevicePermissionsHelper.h"
#import "DisplayMode.h"
#import "MEGAChatGenericRequestDelegate.h"
#import "MEGAChatMessage+MNZCategory.h"
#import "MEGACreateFolderRequestDelegate.h"
#import "MEGACopyRequestDelegate.h"
#import "MEGAGetAttrUserRequestDelegate.h"
#import "MEGAInviteContactRequestDelegate.h"
#import "MEGANode+MNZCategory.h"
#import "MEGANodeList+MNZCategory.h"
#import "MEGALinkManager.h"
#import "MEGAOpenMessageHeaderView.h"
#import "MEGAProcessAsset.h"
#import "MEGAReachabilityManager.h"
#import "MEGAStartUploadTransferDelegate.h"
#import "MEGAStore.h"
#import "MEGAToolbarContentView.h"
#import "MEGATransfer+MNZCategory.h"
#import "NSAttributedString+MNZCategory.h"
#import "NSDate+MNZCategory.h"
#import "NSString+MNZCategory.h"
#import "UIImage+MNZCategory.h"
#import "UIApplication+MNZCategory.h"

#import "BrowserViewController.h"
#import "CallViewController.h"
#import "GroupCallViewController.h"
#import "ChatAttachedContactsViewController.h"
#import "ChatAttachedNodesViewController.h"
#import "ContactsViewController.h"
#import "ContactDetailsViewController.h"
#import "CustomModalAlertViewController.h"
#import "GroupChatDetailsViewController.h"
#import "MainTabBarController.h"
#import "MEGAPhotoBrowserViewController.h"
#import "MEGAImagePickerController.h"
#import "MEGANavigationController.h"
#import "OnboardingViewController.h"
#import "SendToViewController.h"

const CGFloat kGroupChatCellLabelHeightBuffer = 12.0f;
const CGFloat k1on1CellLabelHeightBuffer = 5.0f;
const CGFloat kAvatarImageDiameter = 24.0f;

const NSUInteger kMaxMessagesToLoad = 256;

static NSMutableSet<NSString *> *tapForInfoSet;

@interface MessagesViewController () <MEGAPhotoBrowserDelegate, JSQMessagesViewAccessoryButtonDelegate, JSQMessagesComposerTextViewPasteDelegate, DZNEmptyDataSetSource, MEGAChatDelegate, MEGAChatRequestDelegate, MEGARequestDelegate, MEGAChatCallDelegate>

@property (nonatomic, strong) MEGAOpenMessageHeaderView *openMessageHeaderView;

@property (strong, nonatomic) NSMutableArray <MEGAChatMessage *> *messages;

@property (strong, nonatomic) JSQMessagesBubbleImage *outgoingBubbleImageData;
@property (strong, nonatomic) JSQMessagesBubbleImage *incomingBubbleImageData;

@property (nonatomic, strong) MEGAChatMessage *editMessage;

@property (nonatomic, assign) BOOL areAllMessagesSeen;
@property (nonatomic, assign) BOOL isFirstLoad;
@property (nonatomic) BOOL loadMessagesLater;

@property (nonatomic, strong) NSTimer *sendTypingTimer;
@property (nonatomic, strong) NSTimer *tapForInfoTimer;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, NSTimer *> *whoIsTypingTimersMutableDictionary;

@property (nonatomic, strong) UIBarButtonItem *unreadBarButtonItem;

@property (nonatomic, getter=shouldStopInvitingContacts) BOOL stopInvitingContacts;

@property (strong, nonatomic) NSMutableDictionary *participantsMutableDictionary;
@property (strong, nonatomic) NSMutableArray<MEGAChatMessage *> *attachmentMessages;

@property (strong, nonatomic) UIProgressView *navigationBarProgressView;

@property (strong, nonatomic) UIBarButtonItem *videoCallBarButtonItem;
@property (strong, nonatomic) UIBarButtonItem *audioCallBarButtonItem;

@property (nonatomic) long long totalBytesToUpload;
@property (nonatomic) long long remainingBytesToUpload;
@property (nonatomic) float totalProgressOfTransfersCompleted;

@property (nonatomic) JSQMessagesAvatarImageFactory *avatarImageFactory;
@property (nonatomic) NSMutableDictionary *avatarImages;

@property (nonatomic) NSString *lastChatRoomStateString;
@property (nonatomic) UIColor *lastChatRoomStateColor;
@property (nonatomic) UIImage *peerAvatar;

@property (nonatomic) NSInteger unreadMessages;

@property (nonatomic) CGFloat lastBottomInset;
@property (nonatomic) CGFloat lastVerticalOffset;
@property (nonatomic) CGFloat initialToolbarHeight;

@property (nonatomic) NSMutableSet<MEGAChatMessage *> *observedDialogMessages;
@property (nonatomic) NSMutableSet<MEGAChatMessage *> *observedNodeMessages;
@property (nonatomic) NSUInteger richLinkWarningCounterValue;

@property (nonatomic) BOOL selectingMessages;
@property (nonatomic) NSMutableArray<MEGAChatMessage *> *selectedMessages;
@property (nonatomic) ToolbarType toolbarType;

@property (nonatomic, getter=shouldShowJoinView) BOOL showJoinView;

@property (strong, nonatomic) UIButton *activeCallButton;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) NSDate *baseDate;
@property (assign, nonatomic) int64_t initDuration;

@property UIStackView *mainStackView;
@property UILabel *navigationTitleLabel;
@property UILabel *navigationSubtitleLabel;
@property UIView *navigationStatusView;

@property (nonatomic) BOOL chatLinkBeenClosed;

@property (nonatomic) BOOL loadingState;

@property (nonatomic) NSString *lastGreenString;

@end

@implementation MessagesViewController

#pragma mark - Class properties

+ (NSMutableSet *)tapForInfoSet {
    return tapForInfoSet;
}

+ (void)setTapForInfoSet:(NSMutableSet *)newTapForInfoSet {
    tapForInfoSet = newTapForInfoSet;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _messages = [[NSMutableArray alloc] init];
    
    self.isFirstLoad = YES;
    
    [self setupCollectionView];
    [self setupMenuController:[UIMenuController sharedMenuController]];
    [self customToolbarContentView];
    
    self.showLoadEarlierMessagesHeader = YES;
    self.areAllMessagesSeen = NO;
    self.stopInvitingContacts = NO;
    self.unreadMessages = self.chatRoom.unreadCount;
    self.attachmentMessages = [[NSMutableArray<MEGAChatMessage *> alloc] init];

    // Avatar images
    self.avatarImageFactory = [[JSQMessagesAvatarImageFactory alloc] initWithDiameter:kAvatarImageDiameter];
    self.avatarImages = [[NSMutableDictionary alloc] init];
    
    _lastChatRoomStateString = @"";
    _lastChatRoomStateColor = UIColor.whiteColor;
    if (self.chatRoom.isGroup) {
        self.peerAvatar = [UIImage imageForName:self.chatRoom.title.uppercaseString size:CGSizeMake(80.0f, 80.0f) backgroundColor:UIColor.mnz_gray999999 textColor:UIColor.whiteColor font:[UIFont mnz_SFUIRegularWithSize:40.0f]];
    } else {
        uint64_t userHandle = [self.chatRoom peerHandleAtIndex:0];
        self.peerAvatar = [UIImage mnz_imageForUserHandle:userHandle name:self.chatRoom.title size:CGSizeMake(80.0f, 80.0f) delegate:nil];
        [MEGASdkManager.sharedMEGAChatSdk requestLastGreen:userHandle];
    }
    
    // Add an observer to get notified when going to background:
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    // Add an observer to get notified when coming back to foreground:
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    if (@available(iOS 10.0, *)) {
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[[MEGASdk base64HandleForUserHandle:self.chatRoom.chatId]]];
        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[[MEGASdk base64HandleForUserHandle:self.chatRoom.chatId]]];
        self.collectionView.prefetchingEnabled = NO;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(internetConnectionChanged) name:kReachabilityChangedNotification object:nil];

    // Tap gesture for Jump to bottom view:
    UITapGestureRecognizer *jumpButtonTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(jumpToBottomPressed:)];
    [self.jumpToBottomView addGestureRecognizer:jumpButtonTap];
    
    _whoIsTypingTimersMutableDictionary = [[NSMutableDictionary alloc] init];
    
    // Array of observed messages:
    self.observedDialogMessages = [[NSMutableSet<MEGAChatMessage *> alloc] init];
    self.observedNodeMessages = [[NSMutableSet<MEGAChatMessage *> alloc] init];
    
    // Selection:
    self.selectingMessages = NO;
    self.selectedMessages = [[NSMutableArray<MEGAChatMessage *> alloc] init];
    
    [self.inputToolbar.contentView.joinButton setTitle:AMLocalizedString(@"Join", @"Button text in public chat previews that allows the user to join the chat") forState:UIControlStateNormal];
    
    if (!MessagesViewController.tapForInfoSet) {
        MessagesViewController.tapForInfoSet = [[NSMutableSet alloc] init];
    }
    if (![MessagesViewController.tapForInfoSet containsObject:[MEGASdk base64HandleForUserHandle:self.chatRoom.chatId]]) {
        self.tapForInfoTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(hideTapForInfoLabel) userInfo:nil repeats:NO];
        [MessagesViewController.tapForInfoSet addObject:[MEGASdk base64HandleForUserHandle:self.chatRoom.chatId]];
    }
    [self configureNavigationBar];
    
    self.loadingState = YES;
    self.collectionView.emptyDataSetSource = self;
    [self.collectionView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (self.isMovingToParentViewController) {
        if ([[MEGASdkManager sharedMEGAChatSdk] openChatRoom:self.chatRoom.chatId delegate:self]) {
            MEGALogDebug(@"Chat room opened: %@", self.chatRoom);
            if (self.isFirstLoad) {
                [self loadMessages];
            }
        } else {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:AMLocalizedString(@"error", nil) message:AMLocalizedString(@"chatNotFound", nil) preferredStyle:UIAlertControllerStyleAlert];
            [alertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                [self.navigationController popViewControllerAnimated:YES];
            }]];
            [self presentViewController:alertController animated:YES completion:nil];
            MEGALogError(@"The delegate is NULL or the chatroom is not found");
        }
    }
    
    [[MEGASdkManager sharedMEGAChatSdk] addChatDelegate:self];
    [[MEGASdkManager sharedMEGAChatSdk] addChatCallDelegate:self];

    [[MEGAReachabilityManager sharedManager] retryPendingConnections];
    
    self.inputToolbar.contentView.textView.text = [[MEGAStore shareInstance] fetchChatDraftWithChatId:self.chatRoom.chatId].text;
    
    __weak MessagesViewController *weakSelf = self;

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
        NSString *base64ChatId = [MEGASdk base64HandleForUserHandle:weakSelf.chatRoom.chatId];
        for (UNNotification *notification in notifications) {
            if ([notification.request.identifier containsString:base64ChatId]) {
                [center removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];
            }
        }
    }];
    
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
        NSString *base64ChatId = [MEGASdk base64HandleForUserHandle:weakSelf.chatRoom.chatId];
        for (UNNotificationRequest *request in requests) {
            if ([request.identifier containsString:base64ChatId]) {
                [center removePendingNotificationRequestsWithIdentifiers:@[request.identifier]];
            }
        }
    }];
    
    [self setLastMessageAsSeen];
    
    if (!self.isMovingToParentViewController) {
        [self customNavigationBarLabel];
    }
    
    if (!self.activeCallButton) {
        [self createJoinActiveCallButton];
        [self.view addSubview:self.activeCallButton];
    }
    
    
    [self updateUIbasedOnChatConnectionAndReachability];
        
    self.previewersView.hidden = self.chatRoom.previewersCount == 0;
    self.previewersLabel.text = [NSString stringWithFormat:@"%tu", self.chatRoom.previewersCount];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self showOrHideJumpToBottom];
    self.initialToolbarHeight = self.inputToolbar.frame.size.height;
    
    if (self.presentingViewController && self.parentViewController) {
        UIBarButtonItem *chatBackBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:AMLocalizedString(@"close", nil) style:UIBarButtonItemStylePlain target:self action:@selector(dismissChatRoom)];
        
        self.navigationItem.leftBarButtonItem = chatBackBarButtonItem;
    }
    
    if (self.isPublicChatWithLinkCreated) {
        CustomModalAlertViewController *customModalAlertVC = [[CustomModalAlertViewController alloc] init];
        customModalAlertVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        customModalAlertVC.image = [UIImage imageNamed:@"chatLinkCreation"];
        customModalAlertVC.viewTitle = self.chatRoom.title;
        customModalAlertVC.detail = AMLocalizedString(@"People can join your group by using this link.", @"Text explaining users how the chat links work.");
        customModalAlertVC.firstButtonTitle = AMLocalizedString(@"share", @"Button title which, if tapped, will trigger the action of sharing with the contact or contacts selected");
        customModalAlertVC.link = self.publicChatLink.absoluteString;
        customModalAlertVC.secondButtonTitle = AMLocalizedString(@"delete", nil);
        customModalAlertVC.dismissButtonTitle = AMLocalizedString(@"dismiss", @"Label for any 'Dismiss' button, link, text, title, etc. - (String as short as possible).");
        __weak typeof(CustomModalAlertViewController) *weakCustom = customModalAlertVC;
        customModalAlertVC.firstCompletion = ^{
            [weakCustom dismissViewControllerAnimated:YES completion:^{
                UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[self.publicChatLink.absoluteString] applicationActivities:nil];
                self.publicChatWithLinkCreated = NO;
                if (UIDevice.currentDevice.iPadDevice) {
                    activityVC.popoverPresentationController.sourceView = self.view;
                    activityVC.popoverPresentationController.sourceRect = self.view.frame;
                    
                }
                [self presentViewController:activityVC animated:YES completion:nil];
            }];
        };
        
        customModalAlertVC.secondCompletion = ^{
            [weakCustom dismissViewControllerAnimated:YES completion:^{
                MEGAChatGenericRequestDelegate *delegate = [[MEGAChatGenericRequestDelegate alloc] initWithCompletion:^(MEGAChatRequest * _Nonnull request, MEGAChatError * _Nonnull error) {
                    if (!error.type) {
                        [SVProgressHUD showSuccessWithStatus:AMLocalizedString(@"linkRemoved", @"Message shown when the link to a file or folder has been removed")];
                    }
                }];
                [[MEGASdkManager sharedMEGAChatSdk] removeChatLink:self.chatRoom.chatId delegate:delegate];
            }];
        };
        
        customModalAlertVC.dismissCompletion = ^{
            self.publicChatWithLinkCreated = NO;
            [weakCustom dismissViewControllerAnimated:YES completion:nil];
        };
        
        [self presentViewController:customModalAlertVC animated:YES completion:nil];
    }
}

- (void)willEnterForeground {
    // Workaround to avoid wrong collection view height when coming back to foreground
    if ([self.inputToolbar.contentView.textView isFirstResponder]) {
        [self jsq_setCollectionViewInsetsTopValue:0.0f bottomValue:self.lastBottomInset];
        CGPoint offset = self.collectionView.contentOffset;
        offset.y = self.lastVerticalOffset;
        self.collectionView.contentOffset = offset;
    }
    self.unreadMessages = self.chatRoom.unreadCount;
}

- (void)didBecomeActive {
    if (UIApplication.mnz_visibleViewController == self) {
        [self setLastMessageAsSeen];
    }
}

- (void)willResignActive {
    [self saveChatDraft];
    
    self.lastBottomInset = self.collectionView.scrollIndicatorInsets.bottom;
    self.lastVerticalOffset = self.collectionView.contentOffset.y;
    
    self.unreadMessages = 0;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    
    // Don't close the chat room when pushing the group details view controller
    if (self.isMovingFromParentViewController || (self.presentingViewController && self.navigationController.viewControllers.count == 1)) {
        [[MEGASdkManager sharedMEGAChatSdk] closeChatRoom:self.chatRoom.chatId delegate:self];
    }
    
    // The chat preview is closed here in case of dismiss and in viewDidDisappear in case of pop
    if (self.chatRoom.isPreview && self.presentingViewController && self.navigationController.viewControllers.count == 1) {
        [[MEGASdkManager sharedMEGAChatSdk] closeChatPreview:self.chatRoom.chatId];
    }
    
    [[MEGASdkManager sharedMEGAChatSdk] removeChatDelegate:self];
    [[MEGASdkManager sharedMEGAChatSdk] removeChatCallDelegate:self];
    
    [self saveChatDraft];
    
    [SVProgressHUD dismiss];
    [self hideTapForInfoLabel];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // The chat preview is closed here in case of pop and in viewWillDisappear in case of dismiss
    if (self.chatRoom.isPreview && self.isMovingFromParentViewController) {
        [[MEGASdkManager sharedMEGAChatSdk] closeChatPreview:self.chatRoom.chatId];
    }
}

- (BOOL)hidesBottomBarWhenPushed {
    return YES;
}

- (void)popViewController {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)dismissChatRoom {
    [self.inputToolbar removeFromSuperview];
    [self dismissViewControllerAnimated:YES completion:^{
        if ([[MEGASdkManager sharedMEGAChatSdk] initState] == MEGAChatInitAnonymous) {
            MEGAChatGenericRequestDelegate *delegate = [[MEGAChatGenericRequestDelegate alloc] initWithCompletion:^(MEGAChatRequest * _Nonnull request, MEGAChatError * _Nonnull error) {
                [MEGASdkManager destroySharedMEGAChatSdk];
            }];
            [[MEGASdkManager sharedMEGAChatSdk] logoutWithDelegate:delegate];
            
            if (MEGALinkManager.selectedOption == LinkOptionJoinChatLink) {
                OnboardingViewController *onboardingVC = (OnboardingViewController *) UIApplication.mnz_visibleViewController;
                [onboardingVC presentLoginViewController];
            }
        }
    }];
}

- (void)dealloc {
    for (MEGAChatMessage *message in self.observedDialogMessages) {
        [message removeObserver:self forKeyPath:@"warningDialog"];
    }
    [self.observedDialogMessages removeAllObjects];
    for (MEGAChatMessage *message in self.observedNodeMessages) {
        [message removeObserver:self forKeyPath:@"richNumber"];
    }
    [self.observedNodeMessages removeAllObjects];
    [NSNotificationCenter.defaultCenter removeObserver:self name:kReachabilityChangedNotification object:nil];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self configureNavigationBar];
    } completion:nil];
}

#pragma mark - Private

- (void)configureNavigationBar {    
    [self createRightBarButtonItems];
    if (@available(iOS 11.0, *)) {
        [self initNavigationTitleViews];
        [self instantiateNavigationTitle];
    }
    [self customNavigationBarLabel];
}

- (void)initNavigationTitleViews {
    self.navigationTitleLabel = [[UILabel alloc] init];
    self.navigationTitleLabel.font = [UIFont mnz_SFUISemiBoldWithSize:15];
    self.navigationTitleLabel.textColor = UIColor.whiteColor;
    
    self.navigationStatusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    [[self.navigationStatusView.widthAnchor constraintEqualToConstant:10] setActive:YES];
    [[self.navigationStatusView.heightAnchor constraintEqualToConstant:10] setActive:YES];
    self.navigationStatusView.layer.cornerRadius = 5;
    self.navigationStatusView.layer.borderColor = UIColor.whiteColor.CGColor;
    self.navigationStatusView.layer.borderWidth = 1;
    self.navigationStatusView.backgroundColor = UIColor.mnz_green00BFA5;
    
    self.navigationSubtitleLabel = [[UILabel alloc] init];
    self.navigationSubtitleLabel.font = [UIFont mnz_SFUIRegularWithSize:12];
    self.navigationSubtitleLabel.textColor = UIColor.mnz_grayE3E3E3;
}

- (void)instantiateNavigationTitle {
    
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.distribution = UIStackViewDistributionEqualSpacing;
    self.mainStackView.alignment = UIStackViewAlignmentLeading;
    self.mainStackView.spacing = 4;
    self.mainStackView.userInteractionEnabled = YES;
    [self.mainStackView setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    
    UIInterfaceOrientation orientation = UIApplication.sharedApplication.statusBarOrientation;
    if (UIInterfaceOrientationIsPortrait(orientation)) {
        UIStackView *titleView = [[UIStackView alloc] init];
        titleView.axis = UILayoutConstraintAxisHorizontal;
        titleView.distribution = UIStackViewDistributionEqualSpacing;
        titleView.alignment = UIStackViewAlignmentCenter;
        titleView.spacing = 8;
        [titleView addArrangedSubview:self.navigationTitleLabel];
        [titleView addArrangedSubview:self.navigationStatusView];
        
        self.mainStackView.axis = UILayoutConstraintAxisVertical;
        [self.mainStackView addArrangedSubview:titleView];
        [self.mainStackView addArrangedSubview:self.navigationSubtitleLabel];
        
        CGFloat width = self.navigationController.navigationBar.bounds.size.width - 80 - 50 * (self.navigationItem.rightBarButtonItems.count);
        
        [self.mainStackView addConstraint:[NSLayoutConstraint constraintWithItem:self.mainStackView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
                                                                          toItem:nil
                                                                       attribute: NSLayoutAttributeNotAnAttribute
                                                                      multiplier:1
                                                                        constant:width]];
    } else {
        self.mainStackView.axis = UILayoutConstraintAxisHorizontal;
        self.mainStackView.alignment = UIStackViewAlignmentCenter;
        self.mainStackView.spacing = 8;
        [self.mainStackView addArrangedSubview:self.navigationTitleLabel];
        [self.mainStackView addArrangedSubview:self.navigationStatusView];
        [self.mainStackView addArrangedSubview:self.navigationSubtitleLabel];
    }
    
    [self.navigationItem setTitleView:self.mainStackView];
}

- (void)loadMessages {
    NSUInteger messagesToLoad = 32;
    if (self.isFirstLoad && (self.unreadMessages > 32 || self.unreadMessages < 0)) {
        messagesToLoad = ABS(self.unreadMessages);
    }
    NSInteger loadMessage = [[MEGASdkManager sharedMEGAChatSdk] loadMessagesForChat:self.chatRoom.chatId count:messagesToLoad];
    switch (loadMessage) {
        case -1:
            MEGALogDebug(@"loadMessagesForChat: history has to be fetched from server, but we are not logged in yet");
            self.loadMessagesLater = YES;
            break;
            
        case 0:
            MEGALogDebug(@"loadMessagesForChat: there's no more history available (not even in the server)");
            break;
            
        case 1:
            MEGALogDebug(@"loadMessagesForChat: messages will be fetched locally");
            break;
            
        case 2:
            if (!self.isFirstLoad) {
                [SVProgressHUD show];
            }
            MEGALogDebug(@"loadMessagesForChat: messages will be requested to the server");
            break;
            
        default:
            break;
    }
}

- (void)customNavigationBarLabel {
    if (self.selectingMessages) {
        self.inputToolbar.hidden = YES;

        UILabel *label = [Helper customNavigationBarLabelWithTitle:[NSString stringWithFormat:AMLocalizedString(@"xSelected", nil), self.selectedMessages.count] subtitle:@""];
        
        [self.navigationItem setTitleView:label];
        self.navigationItem.hidesBackButton = YES;
    } else {
        self.navigationItem.hidesBackButton = NO;
        self.inputToolbar.hidden = self.chatRoom.ownPrivilege <= MEGAChatRoomPrivilegeRo && !self.shouldShowJoinView;
        [self updateJoinView];
        
        if (self.chatRoom.isGroup) {
            self.navigationStatusView.hidden = YES;
        } else {
            MEGAChatStatus userStatus = [MEGASdkManager.sharedMEGAChatSdk userOnlineStatus:[self.chatRoom peerHandleAtIndex:0]];
            if (userStatus == MEGAChatStatusInvalid) {
                self.navigationStatusView.hidden = YES;
            } else {
                self.navigationStatusView.backgroundColor = [UIColor mnz_colorForStatusChange:userStatus];
                self.navigationStatusView.hidden = NO;
            }
        }
        
        NSString *chatRoomTitle = self.chatRoom.title ?: @"";
        NSString *chatRoomState;
        if (self.tapForInfoTimer.isValid) {
            chatRoomState = AMLocalizedString(@"Tap here for info", @"Subtitle shown in a chat to inform where to tap to enter in the chat details view");
        } else if (self.chatRoom.archived) {
            self.navigationStatusView.hidden = YES;
            chatRoomState = AMLocalizedString(@"archived", @"Title of flag of archived chats.");
        } else {
            if (self.chatRoom.isGroup) {
                if (self.chatRoom.hasCustomTitle) {
                    chatRoomState = [self participantsNames];
                } else {
                    if (self.chatRoom.peerCount) {
                        chatRoomState = [NSString stringWithFormat:AMLocalizedString(@"%d participants", @"Plural of participant. 2 participants").capitalizedString, self.chatRoom.peerCount + 1];
                    } else {
                        chatRoomState = [NSString stringWithFormat:AMLocalizedString(@"%d participant", @"Singular of participant. 1 participant").capitalizedString, 1];
                    }
                }
                self.navigationSubtitleLabel.hidden = NO;
            } else {
                uint64_t userHandle = [self.chatRoom peerHandleAtIndex:0];
                MEGAChatStatus userStatus = [MEGASdkManager.sharedMEGAChatSdk userOnlineStatus:userHandle];
                if (userStatus == MEGAChatStatusInvalid) {
                    self.navigationSubtitleLabel.hidden = YES;
                } else {
                    if (self.lastGreenString && userStatus < MEGAChatStatusOnline) {
                        chatRoomState = self.lastGreenString;
                    } else {
                        chatRoomState = [NSString chatStatusString:userStatus];
                    }
                    self.navigationSubtitleLabel.hidden = NO;
                }
            }
        }
        
        UITapGestureRecognizer *titleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chatRoomTitleDidTap)];
        
        if (@available(iOS 11.0, *)) {
            self.navigationTitleLabel.text = chatRoomTitle;
            self.navigationSubtitleLabel.text = chatRoomState;
            self.mainStackView.gestureRecognizers = @[titleTapRecognizer];
        } else {
            self.navigationTitleLabel = [UILabel new];
            if (chatRoomState && !self.chatRoom.isGroup) {
                self.navigationTitleLabel = [Helper customNavigationBarLabelWithTitle:chatRoomTitle subtitle:chatRoomState];
            } else {
                self.navigationTitleLabel = [Helper customNavigationBarLabelWithTitle:chatRoomTitle subtitle:@""];
            }
            
            self.navigationTitleLabel.userInteractionEnabled = YES;
            self.navigationTitleLabel.superview.userInteractionEnabled = YES;
            self.navigationTitleLabel.gestureRecognizers = @[titleTapRecognizer];
            self.navigationTitleLabel.adjustsFontSizeToFitWidth = YES;
            self.navigationTitleLabel.minimumScaleFactor = 0.8f;
            self.navigationTitleLabel.frame = CGRectMake(0, 0, self.navigationItem.titleView.bounds.size.width, 44);
            
            [self.navigationItem setTitleView:self.navigationTitleLabel];
        }
        
        self.lastChatRoomStateString = chatRoomState;
    }
    
    [self updateCollectionViewInsets];
}

- (void)createRightBarButtonItems {
    if (self.selectingMessages) {
        UIBarButtonItem *cancelBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:AMLocalizedString(@"cancel", nil) style:UIBarButtonItemStyleDone target:self action:@selector(cancelSelecting:)];
        self.navigationItem.rightBarButtonItems = @[cancelBarButtonItem];
    } else {
        NSMutableArray *barButtons = [NSMutableArray new];
        
        self.videoCallBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"videoCall"] style:UIBarButtonItemStyleDone target:self action:@selector(startAudioVideoCall:)];
        self.audioCallBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"audioCall"] style:UIBarButtonItemStyleDone target:self action:@selector(startAudioVideoCall:)];
        self.videoCallBarButtonItem.tag = 1;
        
        if (self.chatRoom.isGroup) {
            if (self.chatRoom.ownPrivilege == MEGAChatRoomPrivilegeModerator) {
                UIBarButtonItem *addContactBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"addContact"] style:UIBarButtonItemStyleDone target:self action:@selector(presentAddOrAttachParticipantToGroup:)];
                [barButtons addObject:addContactBarButtonItem];
            }
            [barButtons addObject:self.audioCallBarButtonItem];
        } else {
            [barButtons addObjectsFromArray:@[self.videoCallBarButtonItem, self.audioCallBarButtonItem]];
        }
        
        self.navigationItem.rightBarButtonItems = barButtons;
        [self updateNavigationBarButtonsState];
    }
}

- (void)updateUIbasedOnChatConnectionAndReachability {
    MEGAChatConnection chatConnection = [[MEGASdkManager sharedMEGAChatSdk] chatConnectionState:self.chatRoom.chatId];
    [self updateNavigationBarButtonsState];
    
    if (self.chatRoom.ownPrivilege >= MEGAChatRoomPrivilegeStandard && chatConnection == MEGAChatConnectionOnline && MEGAReachabilityManager.isReachable) {
        if ([[MEGASdkManager sharedMEGAChatSdk] hasCallInChatRoom:self.chatRoom.chatId]) {
            MEGAChatCall *call = [[MEGASdkManager sharedMEGAChatSdk] chatCallForChatId:self.chatRoom.chatId];
            if (call.status == MEGAChatCallStatusInProgress) {
                [self showTapToReturnCall:call];
            } else if (self.chatRoom.group || call.status == MEGAChatCallStatusRequestSent) {
                MEGAHandleList *chatRoomIDsWithCallInProgress = [MEGASdkManager.sharedMEGAChatSdk chatCallsWithState:MEGAChatCallStatusInProgress];
                if (chatRoomIDsWithCallInProgress.size == 0) {
                    [self showActiveCallButton];
                }
            }
        }
    } else {
        if (!self.activeCallButton.hidden) {
            [self hideActiveCallButton];
        }
    }
}

- (void)updateNavigationBarButtonsState {
    MEGAChatConnection chatConnection = [[MEGASdkManager sharedMEGAChatSdk] chatConnectionState:self.chatRoom.chatId];
    
    if (self.chatRoom.ownPrivilege < MEGAChatRoomPrivilegeStandard || chatConnection != MEGAChatConnectionOnline || !MEGAReachabilityManager.isReachable || self.chatRoom.peerCount == 0) {
        self.audioCallBarButtonItem.enabled = self.videoCallBarButtonItem.enabled = NO;
        return;
    }
    
    MEGAHandleList *chatRoomIDsWithCallInProgress = [MEGASdkManager.sharedMEGAChatSdk chatCallsWithState:MEGAChatCallStatusInProgress];
    if (chatRoomIDsWithCallInProgress.size > 0) {
        self.audioCallBarButtonItem.enabled = self.videoCallBarButtonItem.enabled = NO;
        return;
    }
    
    self.audioCallBarButtonItem.enabled = self.videoCallBarButtonItem.enabled = YES;
}

- (void)createJoinActiveCallButton {
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(0, -44, self.view.frame.size.width, 44)];
    button.backgroundColor = UIColor.mnz_green00BFA5;
    NSString *title;
    if (self.chatRoom.isGroup) {
        title = AMLocalizedString(@"There is an active group call. Tap to join.", @"Message shown in a chat room when there is an active group call");
    } else {
        title = AMLocalizedString(@"There is an active call. Tap to join.", @"Message shown in a chat room when there is an active call");
    }
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    [button addTarget:self action:@selector(joinActiveCall:) forControlEvents:UIControlEventTouchUpInside];
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    button.hidden = YES;
    self.activeCallButton = button;
}

- (void)showTapToReturnCall:(MEGAChatCall *)call {
    self.initDuration = call.duration;
    self.baseDate = [NSDate date];
    [self updateDuration];
    self.timer = [NSTimer timerWithTimeInterval:1.0f target:self selector:@selector(updateDuration) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    if (self.activeCallButton.hidden) {
        self.activeCallButton.hidden = NO;
        [UIView animateWithDuration:.5f animations:^ {
            self.activeCallButton.frame = CGRectMake(0, 0, self.activeCallButton.frame.size.width, self.activeCallButton.frame.size.height);
        } completion:nil];
    }
}

- (void)updateDuration {
    NSTimeInterval interval = ([NSDate date].timeIntervalSince1970 - self.baseDate.timeIntervalSince1970 + self.initDuration);
    [self.activeCallButton setTitle:[NSString stringWithFormat:AMLocalizedString(@"Touch to return to call %@", @"Message shown in a chat room for a group call in progress displaying the duration of the call"), [NSString mnz_stringFromTimeInterval:interval]] forState:UIControlStateNormal];
}

- (void)showActiveCallButton {
    [self.timer invalidate];
    NSString *title;
    if (self.chatRoom.isGroup) {
        title = AMLocalizedString(@"There is an active group call. Tap to join.", @"Message shown in a chat room when there is an active group call");
    } else {
        title = AMLocalizedString(@"There is an active call. Tap to join.", @"Message shown in a chat room when there is an active call");
    }
    [self.activeCallButton setTitle:title forState:UIControlStateNormal];
    if (self.activeCallButton.hidden) {
        self.activeCallButton.hidden = NO;
        [UIView animateWithDuration:.5f animations:^ {
            self.activeCallButton.frame = CGRectMake(0, 0, self.activeCallButton.frame.size.width, self.activeCallButton.frame.size.height);
        } completion:nil];
    }
}

- (void)hideActiveCallButton {
    if (!self.activeCallButton.hidden) {
        [UIView animateWithDuration:.5f animations:^ {
            self.activeCallButton.frame = CGRectMake(0, -44, self.activeCallButton.frame.size.width, self.activeCallButton.frame.size.height);
        } completion:^(BOOL finished) {
            if (finished) {
                self.activeCallButton.hidden = YES;
            }
        }];
    }
}

- (IBAction)joinActiveCall:(id)sender {
    [self.timer invalidate];
    [self openCallViewWithVideo:NO active:YES];
}

- (void)startAudioVideoCall:(UIBarButtonItem *)sender {
    [DevicePermissionsHelper audioPermissionModal:YES forIncomingCall:NO withCompletionHandler:^(BOOL granted) {
        if (granted) {
            if (sender.tag) {
                [DevicePermissionsHelper videoPermissionWithCompletionHandler:^(BOOL granted) {
                    if (granted) {
                        [self openCallViewWithVideo:sender.tag active:[[MEGASdkManager sharedMEGAChatSdk] hasCallInChatRoom:self.chatRoom.chatId]];
                    } else {
                        [DevicePermissionsHelper alertVideoPermissionWithCompletionHandler:nil];
                    }
                }];
            } else {
                [self openCallViewWithVideo:sender.tag active:[[MEGASdkManager sharedMEGAChatSdk] hasCallInChatRoom:self.chatRoom.chatId]];
            }
        } else {
            [DevicePermissionsHelper alertAudioPermissionForIncomingCall:NO];
        }
    }];
}

- (void)openCallViewWithVideo:(BOOL)videoCall active:(BOOL)active {
    if ([[UIDevice currentDevice] orientation] != UIInterfaceOrientationPortrait) {
        NSNumber *value = [NSNumber numberWithInt:UIInterfaceOrientationPortrait];
        [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
    }
    if (self.chatRoom.isGroup) {
        GroupCallViewController *groupCallVC = [[UIStoryboard storyboardWithName:@"Chat" bundle:nil] instantiateViewControllerWithIdentifier:@"GroupCallViewControllerID"];
        groupCallVC.callType = active ? CallTypeActive : [[MEGASdkManager sharedMEGAChatSdk] chatCallForChatId:self.chatRoom.chatId] ? CallTypeActive : CallTypeOutgoing;
        groupCallVC.videoCall = videoCall;
        groupCallVC.chatRoom = self.chatRoom;
        groupCallVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

        if (@available(iOS 10.0, *)) {
            groupCallVC.megaCallManager = [(MainTabBarController *)UIApplication.sharedApplication.keyWindow.rootViewController megaCallManager];
        }
        [self presentViewController:groupCallVC animated:YES completion:nil];
    } else {
        CallViewController *callVC = [[UIStoryboard storyboardWithName:@"Chat" bundle:nil] instantiateViewControllerWithIdentifier:@"CallViewControllerID"];
        callVC.chatRoom = self.chatRoom;
        callVC.videoCall = videoCall;
        callVC.callType = active ? CallTypeActive : CallTypeOutgoing;
        callVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        
        if (@available(iOS 10.0, *)) {
            callVC.megaCallManager = [(MainTabBarController *)UIApplication.sharedApplication.keyWindow.rootViewController megaCallManager];
        }
        [self presentViewController:callVC animated:YES completion:nil];
    }
}

- (void)presentAddOrAttachParticipantToGroup:(UIBarButtonItem *)sender {
    BOOL addParticipant = sender ? YES : NO;
    MEGANavigationController *navigationController = [[UIStoryboard storyboardWithName:@"Contacts" bundle:nil] instantiateViewControllerWithIdentifier:@"ContactsNavigationControllerID"];
    ContactsViewController *contactsVC = navigationController.viewControllers.firstObject;
    contactsVC.contactsMode = addParticipant ? ContactsModeChatAddParticipant : ContactsModeChatAttachParticipant;
    self.participantsMutableDictionary = [[NSMutableDictionary alloc] init];
    NSUInteger peerCount = self.chatRoom.peerCount;
    for (NSUInteger i = 0; i < peerCount; i++) {
        uint64_t peerHandle = [self.chatRoom peerHandleAtIndex:i];
        if ([self.chatRoom peerPrivilegeByHandle:peerHandle] > MEGAChatRoomPrivilegeRm) {
            [self.participantsMutableDictionary setObject:[NSNumber numberWithUnsignedLongLong:peerHandle] forKey:[NSNumber numberWithUnsignedLongLong:peerHandle]];
        }
    }
    contactsVC.participantsMutableDictionary = self.participantsMutableDictionary.copy;
    
    contactsVC.userSelected = ^void(NSArray *users) {
        if (addParticipant) {
            for (NSInteger i = 0; i < users.count; i++) {
                if (self.shouldStopInvitingContacts) {
                    break;
                }
                MEGAUser *user = [users objectAtIndex:i];
                [[MEGASdkManager sharedMEGAChatSdk] inviteToChat:self.chatRoom.chatId user:user.handle privilege:MEGAChatRoomPrivilegeStandard delegate:self];
            }
        } else {
            MEGAChatMessage *message = [[MEGASdkManager sharedMEGAChatSdk] attachContactsToChat:self.chatRoom.chatId contacts:users];
            message.chatId = self.chatRoom.chatId;
            [self.messages addObject:message];
            [self.collectionView insertItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:self.messages.count-1 inSection:0]]];
            [self updateUnreadMessagesLabel:0];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishSendingMessageAnimated:YES];
            });
        }
    };
    
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)updateUnreadLabel {
    NSInteger unreadChats = [[MEGASdkManager sharedMEGAChatSdk] unreadChats];
    NSString *unreadChatsString = unreadChats ? [NSString stringWithFormat:@"(%td)", unreadChats] : @"";
    
    UIBarButtonItem *backBarButton = [[UIBarButtonItem alloc] initWithTitle:unreadChatsString style:UIBarButtonItemStylePlain target:nil action:nil];
    self.navigationController.viewControllers[0].navigationItem.backBarButtonItem = backBarButton;
}

- (void)setupCollectionView {
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideInputToolbar)];
    tapGesture.cancelsTouchesInView = NO;
    [self.collectionView addGestureRecognizer:tapGesture];
    
    [self customiseCollectionViewLayout];
    
    [self.collectionView registerNib:[MEGAOpenMessageHeaderView nib] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:[MEGAOpenMessageHeaderView headerReuseIdentifier]];
    
    self.collectionView.accessoryDelegate = self;
    self.collectionView.backgroundColor = UIColor.whiteColor;
    
    //Register custom menu actions for cells.
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(edit:message:)];
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(forward:message:)];
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(import:message:)];
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(download:message:)];
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(addContact:message:)];
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(removeRichPreview:message:indexPath:)];
    [JSQMessagesCollectionViewCell registerMenuAction:@selector(delete:)];
    
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] initWithBubbleImage:[UIImage imageNamed:@"bubble_tailless"] capInsets:UIEdgeInsetsZero layoutDirection:UIApplication.sharedApplication.userInterfaceLayoutDirection];
    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:UIColor.mnz_green00BFA5];
    self.incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:UIColor.mnz_grayE2EAEA];
}

- (void)customiseCollectionViewLayout {
    self.collectionView.collectionViewLayout.messageBubbleFont = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.collectionView.collectionViewLayout.messageBubbleTextViewFrameInsets = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f);
    self.collectionView.collectionViewLayout.messageBubbleTextViewTextContainerInsets = UIEdgeInsetsMake(10.0f, 10.0f, 10.0f, 10.0f);
    
    self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeMake(kAvatarImageDiameter, kAvatarImageDiameter);
    self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeMake(0.0f, 0.0f);
    
    self.collectionView.collectionViewLayout.minimumLineSpacing = 5.0f;
    
    self.collectionView.collectionViewLayout.sectionInset = UIEdgeInsetsMake(10.0f, 17.0f, 10.0f, 17.0f);
    self.collectionView.collectionViewLayout.messageBubbleLeftRightMargin = 10.0f;
}

- (void)customToolbarContentView {
    self.inputToolbar.contentView.textView.jsq_pasteDelegate = self;
    self.inputToolbar.contentView.textView.placeHolderTextColor = UIColor.mnz_grayCCCCCC;
    self.inputToolbar.contentView.textView.font = [UIFont mnz_SFUIRegularWithSize:15.0f];
    self.inputToolbar.contentView.textView.textColor = UIColor.mnz_black333333;
    self.inputToolbar.contentView.textView.tintColor = UIColor.mnz_green00BFA5;
    [self updateToolbarPlaceHolder];
    self.inputToolbar.contentView.textView.delegate = self;
    self.inputToolbar.contentView.textView.text = [[MEGAStore shareInstance] fetchChatDraftWithChatId:self.chatRoom.chatId].text;
}

- (void)updateToolbarPlaceHolder {
    NSString *title = self.chatRoom.hasCustomTitle ? [NSString stringWithFormat:@"\"%@\"", self.chatRoom.title] : self.chatRoom.title;
    NSString *placeholder = [AMLocalizedString(@"writeAMessage", @"This is shown in the typing area in chat, as a placeholder before the user starts typing anything in the field. The format is: Write a message to Contact Name... Write a message to \"Chat room topic\"... Write a message to Contact Name1, Contact Name2, Contact Name3") stringByReplacingOccurrencesOfString:@"%s" withString:title];
    self.inputToolbar.contentView.textView.placeHolder = placeholder;
}

- (BOOL)showDateBetweenMessage:(MEGAChatMessage *)message previousMessage:(MEGAChatMessage *)previousMessage {
    if ((previousMessage.senderId != message.senderId) || (previousMessage.date != message.date)) {
        NSDateComponents *previousDateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear fromDate:previousMessage.date];
        NSDateComponents *currentDateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear fromDate:message.date];
        if (previousDateComponents.day != currentDateComponents.day || previousDateComponents.month != currentDateComponents.month || previousDateComponents.year != currentDateComponents.year) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)showHourForMessage:(MEGAChatMessage *)message withIndexPath:(NSIndexPath *)indexPath {
    if (message.managementMessage || indexPath.item == 0) {
        return YES;
    }
    
    MEGAChatMessage *previousMessage = [self.messages objectAtIndex:(indexPath.item - 1)];
    if (previousMessage.isManagementMessage) {
        return YES;
    }
    
    BOOL showHour = NO;
    if ([message.senderId isEqualToString:previousMessage.senderId]) {
        if ([self showHourBetweenDate:message.date previousDate:previousMessage.date]) {
            showHour = YES;
        } else {
            JSQMessagesCollectionViewCell *previousMessageCell = (JSQMessagesCollectionViewCell *)[self.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:(indexPath.item - 1) inSection:0]];
            if (previousMessageCell.messageBubbleTopLabel.attributedText == nil) {
                NSUInteger count = self.messages.count;
                for (NSUInteger i = 1; i < count; i++) {
                    NSInteger index = (indexPath.item - (i + 1));
                    if (index > 0) {
                        MEGAChatMessage *messagePriorToThePreviousOne = [self.messages objectAtIndex:index];
                        if (messagePriorToThePreviousOne.messageIndex < 0) {
                            break;
                        }
                        
                        if ([message.senderId isEqualToString:messagePriorToThePreviousOne.senderId]) {
                            if ([self showHourBetweenDate:message.date previousDate:messagePriorToThePreviousOne.date]) {
                                JSQMessagesCollectionViewCell *messagePriorToThePreviousOneCell = (JSQMessagesCollectionViewCell *)[self.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
                                if (messagePriorToThePreviousOneCell.messageBubbleTopLabel.attributedText) {
                                    break;
                                }
                            }
                        } else { //The timestamp should not appear because is already shown on the message prior to the previous message, that has a different sender
                            break;
                        }
                    }
                }
            }
        }
    } else { //If the previous message is from other sender, show timestamp
        showHour = YES;
    }
    
    return showHour;
}

- (BOOL)showHourBetweenDate:(NSDate *)date previousDate:(NSDate *)previousDate {
    NSUInteger numberOfSecondsToShowHour = (60 * 6) - 1;
    NSTimeInterval timeDifferenceBetweenMessages = [date timeIntervalSinceDate:previousDate];
    if (timeDifferenceBetweenMessages > numberOfSecondsToShowHour) {
        return YES;
    }

    return NO;
}

- (void)chatRoomTitleDidTap {
    UIBarButtonItem *backBarButton = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    self.navigationItem.backBarButtonItem = backBarButton;
    
    if (self.chatRoom.isGroup) {
        GroupChatDetailsViewController *groupChatDetailsVC = [[UIStoryboard storyboardWithName:@"Chat" bundle:nil] instantiateViewControllerWithIdentifier:@"GroupChatDetailsViewControllerID"];
        groupChatDetailsVC.chatRoom = self.chatRoom;
        
        [self.navigationController pushViewController:groupChatDetailsVC animated:YES];
    } else {
        NSString *peerEmail = [[MEGASdkManager sharedMEGAChatSdk] contacEmailByHandle:[self.chatRoom peerHandleAtIndex:0]];
        NSString *peerFirstname = [self.chatRoom peerFirstnameAtIndex:0];
        NSString *peerLastname = [self.chatRoom peerLastnameAtIndex:0];
        NSString *peerName = [NSString stringWithFormat:@"%@ %@", peerFirstname, peerLastname];
        uint64_t peerHandle = [self.chatRoom peerHandleAtIndex:0];
        
        ContactDetailsViewController *contactDetailsVC = [[UIStoryboard storyboardWithName:@"Contacts" bundle:nil] instantiateViewControllerWithIdentifier:@"ContactDetailsViewControllerID"];
        contactDetailsVC.contactDetailsMode = ContactDetailsModeFromChat;
        contactDetailsVC.chatId = self.chatRoom.chatId;
        contactDetailsVC.userEmail = peerEmail;
        contactDetailsVC.userName = peerName;
        contactDetailsVC.userHandle = peerHandle;
        [self.navigationController pushViewController:contactDetailsVC animated:YES];
    }
}

- (NSString *)participantsNames {
    NSString *participantsNames = @"";
    for (NSUInteger i = 0; i < self.chatRoom.peerCount; i++) {
        NSString *peerName;
        NSString *peerFirstname = [self.chatRoom peerFirstnameAtIndex:i];
        if (peerFirstname.length > 0 && ![[peerFirstname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""]) {
            peerName = peerFirstname;
        } else {
            NSString *peerLastname = [self.chatRoom peerLastnameAtIndex:i];
            if (peerLastname.length > 0 && ![[peerLastname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""]) {
                peerName = peerLastname;
            }
        }
        
        if (!peerName.length) {
            peerName = [self.chatRoom peerEmailByHandle:[self.chatRoom peerHandleAtIndex:i]];
        }
        
        if (self.chatRoom.peerCount == 1 || (i + 1) == self.chatRoom.peerCount) {
            participantsNames = [participantsNames stringByAppendingString:peerName ? peerName : @"Unknown user"];
        } else {
            participantsNames = [participantsNames stringByAppendingString:[NSString stringWithFormat:@"%@, ", peerName]];
        }
    }
    return participantsNames;
}

- (void)setChatOpenMessageForIndexPath:(NSIndexPath *)indexPath {
    if (self.openMessageHeaderView == nil) {
        self.openMessageHeaderView = [self.collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"MEGAOpenMessageHeaderViewID" forIndexPath:indexPath];
    }
    
    self.openMessageHeaderView.chattingWithLabel.text = AMLocalizedString(@"chattingWith", @"Title show above the name of the persons with whom you're chatting");
    self.openMessageHeaderView.conversationWithLabel.text = [self participantsNames];
    self.openMessageHeaderView.onlineStatusLabel.text = self.lastChatRoomStateString;
    self.openMessageHeaderView.onlineStatusView.backgroundColor = self.lastChatRoomStateColor;
    self.openMessageHeaderView.conversationWithAvatar.image = self.chatRoom.isGroup ? nil : self.peerAvatar;
    self.openMessageHeaderView.introductionLabel.text = AMLocalizedString(@"chatIntroductionMessage", @"Full text: MEGA protects your chat with end-to-end (user controlled) encryption providing essential safety assurances: Confidentiality - Only the author and intended recipients are able to decipher and read the content. Authenticity - There is an assurance that the message received was authored by the stated sender, and its content has not been tampered with during transport or on the server.");
    
    NSString *confidentialityExplanationString = AMLocalizedString(@"confidentialityExplanation", @"Chat advantages information. Full text: Mega protects your chat with end-to-end (user controlled) encryption providing essential safety assurances: [S]Confidentiality.[/S] Only the author and intended recipients are able to decipher and read the content. [S]Authenticity.[/S] The system ensures that the data received is from the sender displayed, and its content has not been manipulated during transit.");
    NSString *confidentialityString = [confidentialityExplanationString mnz_stringBetweenString:@"[S]" andString:@"[/S]"];
    confidentialityExplanationString = [confidentialityExplanationString stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"[S]%@[/S]", confidentialityString] withString:@""];
    
    NSMutableAttributedString *confidentialityAttributedString = [[NSMutableAttributedString alloc] initWithString:confidentialityString attributes:@{NSFontAttributeName:[UIFont mnz_SFUIRegularWithSize:15.0f], NSForegroundColorAttributeName:UIColor.mnz_redMain}];
    NSMutableAttributedString *confidentialityExplanationAttributedString = [[NSMutableAttributedString alloc] initWithString:confidentialityExplanationString attributes:@{NSFontAttributeName:[UIFont mnz_SFUIRegularWithSize:15.0f], NSForegroundColorAttributeName:UIColor.mnz_gray777777}];
    [confidentialityAttributedString appendAttributedString:confidentialityExplanationAttributedString];
    self.openMessageHeaderView.confidentialityLabel.attributedText = confidentialityAttributedString;
    
    NSString *authenticityExplanationString = AMLocalizedString(@"authenticityExplanation", @"Chat advantages information. Full text: Mega protects your chat with end-to-end (user controlled) encryption providing essential safety assurances: [S]Confidentiality.[/S] Only the author and intended recipients are able to decipher and read the content. [S]Authenticity.[/S] The system ensures that the data received is from the sender displayed, and its content has not been manipulated during transit.");
    NSString *authenticityString = [authenticityExplanationString mnz_stringBetweenString:@"[S]" andString:@"[/S]"];
    authenticityExplanationString = [authenticityExplanationString stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"[S]%@[/S]", authenticityString] withString:@""];

    NSMutableAttributedString *authenticityAttributedString = [[NSMutableAttributedString alloc] initWithString:authenticityString attributes:@{NSFontAttributeName:[UIFont mnz_SFUIRegularWithSize:15.0f], NSForegroundColorAttributeName:UIColor.mnz_redMain}];
    NSMutableAttributedString *authenticityExplanationAttributedString = [[NSMutableAttributedString alloc] initWithString:authenticityExplanationString attributes:@{NSFontAttributeName:[UIFont mnz_SFUIRegularWithSize:15.0f], NSForegroundColorAttributeName:UIColor.mnz_gray777777}];
    [authenticityAttributedString appendAttributedString:authenticityExplanationAttributedString];
    self.openMessageHeaderView.authenticityLabel.attributedText = authenticityAttributedString;
}

- (void)userTypingTimerFireMethod:(NSTimer *)timer {
    [self removeUserHandleFromTypingIndicator:timer.userInfo];
}

- (void)doNothing {}

- (void)hideTapForInfoLabel {
    [self.tapForInfoTimer invalidate];
    [self customNavigationBarLabel];
}

- (void)setupMenuController:(UIMenuController *)menuController {
    UIMenuItem *editMenuItem = [[UIMenuItem alloc] initWithTitle:AMLocalizedString(@"edit", @"Caption of a button to edit the files that are selected") action:@selector(edit:message:)];
    UIMenuItem *forwardMenuItem = [[UIMenuItem alloc] initWithTitle:AMLocalizedString(@"forward", @"Item of a menu to forward a message chat to another chatroom") action:@selector(forward:message:)];
    UIMenuItem *importMenuItem = [[UIMenuItem alloc] initWithTitle:AMLocalizedString(@"import", @"Caption of a button to edit the files that are selected") action:@selector(import:message:)];
    UIMenuItem *downloadMenuItem = [[UIMenuItem alloc] initWithTitle:AMLocalizedString(@"saveForOffline", @"Caption of a button to edit the files that are selected") action:@selector(download:message:)];
    UIMenuItem *addContactMenuItem = [[UIMenuItem alloc] initWithTitle:AMLocalizedString(@"addContact", @"Alert title shown when you select to add a contact inserting his/her email") action:@selector(addContact:message:)];
    UIMenuItem *removeRichLinkMenuItem = [[UIMenuItem alloc] initWithTitle:AMLocalizedString(@"removePreview", @"Once a preview is generated for a message which contains URLs, the user can remove it. Same button is also shown during loading of the preview - and would cancel the loading (text of the button is the same in both cases).") action:@selector(removeRichPreview:message:indexPath:)];
    menuController.menuItems = @[forwardMenuItem, importMenuItem, editMenuItem, downloadMenuItem, addContactMenuItem, removeRichLinkMenuItem];
}

- (void)loadNodesFromMessage:(MEGAChatMessage *)message atTheBeginning:(BOOL)atTheBeginning {
    if (message.type == MEGAChatMessageTypeAttachment) {
        if (message.nodeList.size.unsignedIntegerValue == 1) {
            MEGANode *node = [message.nodeList nodeAtIndex:0];
            if (node.name.mnz_isImagePathExtension || node.name.mnz_isVideoPathExtension) {
                if (atTheBeginning) {
                    [self.attachmentMessages insertObject:message atIndex:0];
                } else {
                    [self.attachmentMessages addObject:message];
                }
            }
        }
    }
}

- (void)showImagePickerForSourceType:(UIImagePickerControllerSourceType)sourceType {
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        MEGAImagePickerController *imagePickerController = [[MEGAImagePickerController alloc] initToShareThroughChatWithSourceType:sourceType filePathCompletion:^(NSString *filePath, UIImagePickerControllerSourceType sourceType) {
            MEGANode *parentNode = [[MEGASdkManager sharedMEGASdk] nodeForPath:@"/My chat files"];
            if (filePath.mnz_isImagePathExtension) {
                [self startUploadAndAttachWithPath:filePath parentNode:parentNode appData:nil];
            }
            if (filePath.mnz_isVideoPathExtension) {
                NSURL *videoURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:filePath]];
                MEGAProcessAsset *processAsset = [[MEGAProcessAsset alloc] initToShareThroughChatWithVideoURL:videoURL filePath:^(NSString *filePath) {
                    NSString *appData = [[NSString new] mnz_appDataToSaveCoordinates:[filePath mnz_coordinatesOfPhotoOrVideo]];
                    [self startUploadAndAttachWithPath:filePath parentNode:parentNode appData:appData];
                } node:nil error:^(NSError *error) {
                    NSString *title = AMLocalizedString(@"error", nil);
                    NSString *message = error.localizedDescription;
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
                    [alertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", nil) style:UIAlertActionStyleCancel handler:nil]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self presentViewController:alertController animated:YES completion:nil];
                    });
                }];
                [processAsset prepare];
            }
        }];
        
        [self presentViewController:imagePickerController animated:YES completion:nil];
    }
}

- (void)startUploadAndAttachWithPath:(NSString *)path parentNode:(MEGANode *)parentNode appData:(NSString *)appData {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showProgressViewUnderNavigationBar];
    });
    
    MEGAStartUploadTransferDelegate *startUploadTransferDelegate = [[MEGAStartUploadTransferDelegate alloc] initToUploadToChatWithTotalBytes:^(MEGATransfer *transfer) {
        long long totalBytes = transfer.totalBytes.longLongValue;
        self.totalBytesToUpload += totalBytes;
        self.remainingBytesToUpload += totalBytes;
    } progress:^(MEGATransfer *transfer) {
        float transferredBytes = transfer.transferredBytes.floatValue;
        float totalBytes = transfer.totalBytes.floatValue;
        float asignableProgresRegardWithTotal = (totalBytes / self.totalBytesToUpload);
        float transferProgress = (transferredBytes / totalBytes);
        float currentAsignableProgressForThisTransfer = (transferProgress * asignableProgresRegardWithTotal);
        
        if (currentAsignableProgressForThisTransfer < asignableProgresRegardWithTotal) {
            if (self.totalProgressOfTransfersCompleted != 0) {
                currentAsignableProgressForThisTransfer += self.totalProgressOfTransfersCompleted;
            }
            
            if (currentAsignableProgressForThisTransfer > self.navigationBarProgressView.progress) {
                [self.navigationBarProgressView setProgress:currentAsignableProgressForThisTransfer animated:YES];
            }
        }
    } completion:^(MEGATransfer *transfer) {
        long long totalBytes = transfer.totalBytes.longLongValue;
        float progressCompletedRegardWithTotal = ((float)totalBytes / self.totalBytesToUpload);
        self.totalProgressOfTransfersCompleted += progressCompletedRegardWithTotal;
        self.remainingBytesToUpload -= totalBytes;
        
        if (self.remainingBytesToUpload == 0) {
            [self resetAndHideProgressView];
        }
    }];
    
    if (!appData) {
        appData = [NSString new];
    }
    appData = [appData mnz_appDataToAttachToChatID:self.chatRoom.chatId];
    
    [[MEGASdkManager sharedMEGASdk] startUploadWithLocalPath:path parent:parentNode appData:appData isSourceTemporary:YES delegate:startUploadTransferDelegate];
}

- (void)attachOrCopyAndAttachNode:(MEGANode *)node toParentNode:(MEGANode *)parentNode {
    if (node) {
        if (node.parentHandle == parentNode.handle) {
            // The file is already in the folder, attach node.
            [[MEGASdkManager sharedMEGAChatSdk] attachNodeToChat:self.chatRoom.chatId node:node.handle delegate:self];
        } else {
            MEGACopyRequestDelegate *copyRequestDelegate = [[MEGACopyRequestDelegate alloc] initWithCompletion:^(MEGARequest *request) {
                [[MEGASdkManager sharedMEGAChatSdk] attachNodeToChat:self.chatRoom.chatId node:node.handle delegate:self];
            }];
            // The file is already in MEGA, in other folder, has to be copied to this folder.
            [[MEGASdkManager sharedMEGASdk] copyNode:node newParent:parentNode delegate:copyRequestDelegate];
        }
    }
}

- (void)showProgressViewUnderNavigationBar {
    if (self.navigationBarProgressView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationBarProgressView.hidden = NO;
        });
    } else {
        self.navigationBarProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        self.navigationBarProgressView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
        self.navigationBarProgressView.frame = CGRectMake(self.navigationController.navigationBar.bounds.origin.x, self.navigationController.navigationBar.bounds.size.height, self.navigationController.navigationBar.bounds.size.width, 2.0f);
        self.navigationBarProgressView.transform = CGAffineTransformScale(self.navigationBarProgressView.transform, 1, 2);
        self.navigationBarProgressView.progressTintColor = UIColor.mnz_green00BFA5;
        self.navigationBarProgressView.trackTintColor = UIColor.clearColor;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationBarProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
            self.navigationBarProgressView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
            self.navigationBarProgressView.frame = CGRectMake(self.navigationController.navigationBar.bounds.origin.x, self.navigationController.navigationBar.bounds.size.height, self.navigationController.navigationBar.bounds.size.width, 2.0f);
            self.navigationBarProgressView.progressTintColor = UIColor.mnz_green00BFA5;
            self.navigationBarProgressView.trackTintColor = UIColor.clearColor;
            
            [self.navigationController.navigationBar addSubview:self.navigationBarProgressView];
        });
    }
}

- (void)resetAndHideProgressView {
    self.totalBytesToUpload = 0.0;
    self.totalProgressOfTransfersCompleted = 0.0f;
    self.navigationBarProgressView.progress = 0.0f;
    self.navigationBarProgressView.hidden = YES;
}

- (void)handleTruncateMessage:(MEGAChatMessage *)message {
    [self.messages removeAllObjects];
    [self.messages addObject:message];
    [self.collectionView reloadData];
    [self updateUnreadMessagesLabel:0];
    [self.attachmentMessages removeAllObjects];
}

- (void)internetConnectionChanged {
    [self updateUIbasedOnChatConnectionAndReachability];
    
    [self customNavigationBarLabel];

    if (self.openMessageHeaderView) {
        self.openMessageHeaderView.onlineStatusLabel.text = self.lastChatRoomStateString;
        self.openMessageHeaderView.onlineStatusView.backgroundColor = self.lastChatRoomStateColor;
    }
}

- (void)showOrHideJumpToBottom {
    CGFloat verticalIncrementToShow = self.view.frame.size.height * 1.5;
    if (self.collectionView.contentSize.height - self.collectionView.contentOffset.y < verticalIncrementToShow) {
        [self hideJumpToBottom];
    } else {
        [self showJumpToBottomWithMessage:AMLocalizedString(@"jumpToLatest", @"Label in a button that allows to jump to the latest item")];
    }
}

- (void)showJumpToBottomWithMessage:(NSString *)message {
    UILabel *label = self.jumpToBottomView.subviews.lastObject;
    label.text = message;
    [label sizeToFit];
    if (self.jumpToBottomView.alpha > 0) {
        return;
    }
    [UIView animateWithDuration:0.2 delay:0.3 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.jumpToBottomView.alpha = 1.0f;
    } completion:nil];
}

- (void)hideJumpToBottom {
    if (self.jumpToBottomView.alpha < 1) {
        return;
    }
    [UIView animateWithDuration:0.2 animations:^{
        self.jumpToBottomView.alpha = 0.0f;
    }];
}

- (void)jumpToBottomPressed:(UITapGestureRecognizer *)recognizer {
    [self scrollToBottomAnimated:YES];
    [self hideJumpToBottom];
}

- (void)setTypingIndicator {
    NSString *typingString = nil;
    NSMutableAttributedString *typingAttributedString = nil;
    if (self.whoIsTypingTimersMutableDictionary.allKeys.count >= 2) {
        typingAttributedString = [self twoOrMoreUsersAreTypingString];
    } else if (self.whoIsTypingTimersMutableDictionary.allKeys.count == 1) {
        NSNumber *firstUserHandle = [self.whoIsTypingTimersMutableDictionary.allKeys objectAtIndex:0];
        NSString *firstUserName = [self.chatRoom peerFirstnameByHandle:firstUserHandle.unsignedLongLongValue];
        NSString *whoIsTypingString = firstUserName.length ? firstUserName : [self.chatRoom peerEmailByHandle:firstUserHandle.unsignedLongLongValue];
        
        typingString = [NSString stringWithFormat:AMLocalizedString(@"isTyping", @"A typing indicator in the chat. Please leave the %@ which will be automatically replaced with the user's name at runtime."), whoIsTypingString];
        
        typingAttributedString = [[NSMutableAttributedString alloc] initWithString:typingString];
        [typingAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10 weight:UIFontWeightBold] range:NSMakeRange(0, whoIsTypingString.length)];
    }
    
    [self.inputToolbar mnz_setTypingIndicatorAttributedText:typingAttributedString];
}

- (NSMutableAttributedString *)twoOrMoreUsersAreTypingString {
    NSNumber *firstUserHandle = [self.whoIsTypingTimersMutableDictionary.allKeys objectAtIndex:0];
    NSNumber *secondUserHandle = [self.whoIsTypingTimersMutableDictionary.allKeys objectAtIndex:1];
    
    NSString *firstUserFirstName = [self.chatRoom peerFirstnameByHandle:firstUserHandle.unsignedLongLongValue];
    NSString *whoIsTypingString = firstUserFirstName.length ? firstUserFirstName : [self.chatRoom peerEmailByHandle:firstUserHandle.unsignedLongLongValue];
    
    NSString *secondUserFirstName = [self.chatRoom peerFirstnameByHandle:secondUserHandle.unsignedLongLongValue];
    whoIsTypingString = [whoIsTypingString stringByAppendingString:[NSString stringWithFormat:@", %@", (secondUserFirstName.length ? secondUserFirstName : [self.chatRoom peerEmailByHandle:firstUserHandle.unsignedLongLongValue])]];
    
    NSString *twoOrMoreUsersAreTypingString;
    if (self.whoIsTypingTimersMutableDictionary.allKeys.count == 2) {
        twoOrMoreUsersAreTypingString = [AMLocalizedString(@"twoUsersAreTyping", @"Plural, a hint that appears when two users are typing in a group chat at the same time. The parameter will be the concatenation of both user names. Please do not translate or modify the tags or placeholders.") mnz_removeWebclientFormatters];
    } else if (self.whoIsTypingTimersMutableDictionary.allKeys.count > 2) {
        twoOrMoreUsersAreTypingString = [AMLocalizedString(@"moreThanTwoUsersAreTyping", @"text that appear when there are more than 2 people writing at that time in a chat. For example User1, user2 and more are typing... The parameter will be the concatenation of the first two user names. Please do not translate or modify the tags or placeholders.") mnz_removeWebclientFormatters];
    }
    
    NSString *typingString = [twoOrMoreUsersAreTypingString stringByReplacingOccurrencesOfString:@"%1$s" withString:whoIsTypingString];
    NSMutableAttributedString *typingAttributedString = [[NSMutableAttributedString alloc] initWithString:typingString];
    [typingAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10 weight:UIFontWeightBold] range:NSMakeRange(0, whoIsTypingString.length)];
    
    return typingAttributedString;
}

- (void)removeUserHandleFromTypingIndicator:(NSNumber *)userHandle {
    NSTimer *userTypingTimer = [self.whoIsTypingTimersMutableDictionary objectForKey:userHandle];
    if (userTypingTimer) {
        [userTypingTimer invalidate];
    }
    [self.whoIsTypingTimersMutableDictionary removeObjectForKey:userHandle];
    [self setTypingIndicator];
}

- (NSIndexPath *)indexPathForCellWithUnreadMessagesLabel {
    return [NSIndexPath indexPathForItem:(self.messages.count - self.unreadMessages) inSection:0];
}

- (void)updateUnreadMessagesLabel:(NSUInteger)unreads {
    if (!self.unreadMessages) {
        return;
    }
    
    NSIndexPath *unreadMessagesIndexPath;
    if (unreads == 0) {
        unreadMessagesIndexPath = [self indexPathForCellWithUnreadMessagesLabel];
        self.unreadMessages = unreads;
    } else {
        self.unreadMessages = unreads;
        unreadMessagesIndexPath = [self indexPathForCellWithUnreadMessagesLabel];
    }
    [self.collectionView reloadItemsAtIndexPaths:@[unreadMessagesIndexPath]];
}

- (void)updateOffsetForCellAtIndexPath:(NSIndexPath *)indexPath previousHeight:(CGFloat)previousHeight {
    if ([self.collectionView.indexPathsForVisibleItems containsObject:indexPath]) {
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        CGFloat currentHeight = cell.frame.size.height;
        CGFloat verticalIncrement = currentHeight - previousHeight;
        if (verticalIncrement > 0) {
            CGPoint newOffset = CGPointMake(self.collectionView.contentOffset.x, self.collectionView.contentOffset.y + verticalIncrement);
            [self.collectionView setContentOffset:newOffset animated:YES];
        }
    }
}

- (void)updateCollectionViewInsets {
    [self jsq_setCollectionViewInsetsTopValue:0.0f bottomValue:self.lastBottomInset];
}

- (BOOL)shouldShowJoinView {
    return self.chatRoom.isPublicChat && self.chatRoom.isPreview && !self.chatLinkBeenClosed;
}

- (void)updateJoinView {
    BOOL hidden = !self.shouldShowJoinView;
    [self.inputToolbar mnz_setJoinViewHidden:hidden];
}

- (void)setLastMessageAsSeen {
    if (self.messages.count > 0) {
        MEGAChatMessage *lastMessage = self.messages.lastObject;
        if (lastMessage.userHandle != [MEGASdkManager sharedMEGAChatSdk].myUserHandle && [[MEGASdkManager sharedMEGAChatSdk] lastChatMessageSeenForChat:self.chatRoom.chatId].messageId != lastMessage.messageId) {
            [[MEGASdkManager sharedMEGAChatSdk] setMessageSeenForChat:self.chatRoom.chatId messageId:lastMessage.messageId];
        }
    }
}

- (void)saveChatDraft {
    NSString *chatDraftText = self.editMessage ? @"" : self.inputToolbar.contentView.textView.text;
    [[MEGAStore shareInstance] insertOrUpdateChatDraftWithChatId:self.chatRoom.chatId text:chatDraftText];
}

#pragma mark - Gesture recognizer

- (void)hideInputToolbar {
    if (self.inputToolbar.imagePickerView) {
        [self.inputToolbar mnz_accesoryButtonPressed:self.inputToolbar.imagePickerView.accessoryImageButton];
    } else if (self.inputToolbar.contentView.textView.isFirstResponder) {
        [self.inputToolbar mnz_accesoryButtonPressed:self.inputToolbar.contentView.accessoryTextButton];
    }
}

#pragma mark - Custom menu actions for cells

- (void)didReceiveMenuWillShowNotification:(NSNotification *)notification {
     //Display custom menu actions for cells.
    [self setupMenuController:[notification object]];
    
    [super didReceiveMenuWillShowNotification:notification];
}

#pragma mark - Rich links support

- (MEGAChatMessage *)sendMessage:(NSString *)text {
    MEGAChatMessage *message;
    
    if (self.editMessage) {
        if ([self.editMessage.content isEqualToString:self.inputToolbar.contentView.textView.text]) {
            //If the user didn't change anything on the message that was editing, just go out of edit mode.
        } else {
            uint64_t messageId = (self.editMessage.status == MEGAChatMessageStatusSending) ? self.editMessage.temporalId : self.editMessage.messageId;
            message = [[MEGASdkManager sharedMEGAChatSdk] editMessageForChat:self.chatRoom.chatId messageId:messageId message:text];
            message.chatId = self.chatRoom.chatId;
            NSUInteger index = [self.messages indexOfObject:self.editMessage];
            if (index != NSNotFound) {
                [self.messages replaceObjectAtIndex:index withObject:message];
                [self.collectionView reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index inSection:0]]];
            }
        }
        
        self.editMessage = nil;
    } else {
        message = [[MEGASdkManager sharedMEGAChatSdk] sendMessageToChat:self.chatRoom.chatId message:text];
        message.chatId = self.chatRoom.chatId;
        [self.messages addObject:message];
        [self.collectionView insertItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:self.messages.count-1 inSection:0]]];
        [self updateUnreadMessagesLabel:0];
    }
    
    MEGALogInfo(@"didPressSendButton %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finishSendingMessageAnimated:YES];
    });
    
    [[MEGASdkManager sharedMEGAChatSdk] sendStopTypingNotificationForChat:self.chatRoom.chatId];
    
    [self hideJumpToBottom];
    return message;
}

- (void)reloadMessage:(MEGAChatMessage *)messageToReload skippedDialogs:(NSNumber *)skippedDialogs {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSUInteger i = 0; i < self.messages.count; i++) {
            MEGAChatMessage *message = [self.messages objectAtIndex:i];
            if ([message.senderId isEqualToString:self.senderId] && message.temporalId == messageToReload.temporalId && [message.date isEqualToDate:messageToReload.date]) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:0];
                UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
                CGFloat previousHeight = cell.frame.size.height;
                message.warningDialog = skippedDialogs.integerValue >= 3 ? MEGAChatMessageWarningDialogStandard : MEGAChatMessageWarningDialogInitial;
                [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
                if (![self.observedDialogMessages containsObject:message]) {
                    [self.observedDialogMessages addObject:message];
                    [message addObserver:self forKeyPath:@"warningDialog" options:NSKeyValueObservingOptionNew context:nil];
                }
                if (self.inputToolbar.contentView.textView.isFirstResponder) {
                    [self.inputToolbar.contentView.textView resignFirstResponder];
                } else {
                    [self updateOffsetForCellAtIndexPath:indexPath previousHeight:previousHeight];
                }
            }
        }
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    MEGAChatMessage *messageToReload = (MEGAChatMessage *)object;
    
    if ([keyPath isEqualToString:@"warningDialog"]) {
        if (messageToReload.warningDialog == MEGAChatMessageWarningDialogDismiss) {
            [[MEGASdkManager sharedMEGASdk] setRichLinkWarningCounterValue:++self.richLinkWarningCounterValue];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSUInteger i = 0; i < self.messages.count; i++) {
            MEGAChatMessage *message = [self.messages objectAtIndex:i];
            if (message.messageId == messageToReload.messageId) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:0];
                UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
                CGFloat previousHeight = cell.frame.size.height;
                [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
                [self updateOffsetForCellAtIndexPath:indexPath previousHeight:previousHeight];
            }
        }
    });
}

#pragma mark - Selection

- (void)startSelecting:(MEGAChatMessage *)message {
    self.selectingMessages = YES;
    [self.selectedMessages addObject:message];
    [self.collectionView reloadItemsAtIndexPaths:self.collectionView.indexPathsForVisibleItems];
    [self createRightBarButtonItems];
    
    if (self.inputToolbar.contentView.textView.isFirstResponder) {
        [self.inputToolbar.contentView.textView resignFirstResponder];
    }
    
    [self customToolbar];
    [self.navigationController setToolbarHidden:NO animated:YES];
    
    [self customNavigationBarLabel];
    [self updateToolbarState];
}

- (void)customToolbar {
    switch (self.toolbarType) {
        case ToolbarTypeForward: {
            UIBarButtonItem *shareBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareSelectedMessages:)];
            UIBarButtonItem *flexibleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
            UIBarButtonItem *forwardBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"forwardToolbar"] style:UIBarButtonItemStyleDone target:self action:@selector(forwardSelectedMessages)];
            [self setToolbarItems:@[shareBarButtonItem, flexibleItem, forwardBarButtonItem]];
            
            break;
        }
            
        case ToolbarTypeDelete: {
            UIBarButtonItem *deleteBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteSelectedMessages)];
            [self setToolbarItems:@[deleteBarButtonItem]];
            
            break;
        }
    }
}

- (void)updateToolbarState {
    switch (self.toolbarType) {
        case ToolbarTypeForward:
            for (UIBarButtonItem *item in self.toolbarItems) {
                item.enabled = self.selectedMessages.count > 0;
            }
            
            break;
            
        case ToolbarTypeDelete: {
            UIBarButtonItem *deleteBarButtonItem = self.toolbarItems.firstObject;
            for (MEGAChatMessage *message in self.selectedMessages) {
                if (!message.isDeletable || message.userHandle != [MEGASdkManager sharedMEGAChatSdk].myUserHandle) {
                    deleteBarButtonItem.enabled = NO;
                    return;
                }
            }
            deleteBarButtonItem.enabled = self.selectedMessages.count > 0;
            
            break;
        }
    }

}

- (void)cancelSelecting:(id)sender {
    self.selectingMessages = NO;
    [self.selectedMessages removeAllObjects];
    [self.collectionView reloadItemsAtIndexPaths:self.collectionView.indexPathsForVisibleItems];
    [self createRightBarButtonItems];
    
    [self.navigationController setToolbarHidden:YES animated:YES];
    
    [self instantiateNavigationTitle];
    [self customNavigationBarLabel];
}

- (void)toggleSelectedMessage:(MEGAChatMessage *)message atIndexPath:(NSIndexPath *)indexPath {
    if (message.type == MEGAChatMessageTypeNormal || message.type == MEGAChatMessageTypeContainsMeta || message.type == MEGAChatMessageTypeContact || message.type == MEGAChatMessageTypeAttachment) {
        if ([self.selectedMessages containsObject:message]) {
            [self.selectedMessages removeObject:message];
        } else {
            NSUInteger index = [self.selectedMessages indexOfObject:message inSortedRange:(NSRange){0, self.selectedMessages.count} options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(MEGAChatMessage *obj1, MEGAChatMessage *obj2) {
                return [obj1.date compare:obj2.date];
            }];
            [self.selectedMessages insertObject:message atIndex:index];
        }
        [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
        
        [self customNavigationBarLabel];
        [self updateToolbarState];
    }
}

- (void)forwardSelectedMessages {
    UIStoryboard *chatStoryboard = [UIStoryboard storyboardWithName:@"Chat" bundle:nil];
    UINavigationController *sendToNC = [chatStoryboard instantiateViewControllerWithIdentifier:@"SendToNavigationControllerID"];
    SendToViewController *sendToViewController = sendToNC.viewControllers.firstObject;
    sendToViewController.sendMode = SendModeForward;
    sendToViewController.messages = self.selectedMessages.copy;
    sendToViewController.sourceChatId = self.chatRoom.chatId;
    sendToViewController.completion = ^(NSArray<NSNumber *> *chatIdNumbers, NSArray<MEGAChatMessage *> *sentMessages) {
        BOOL selfForwarded = NO, showSuccess = NO;
        
        for (NSNumber *chatIdNumber in chatIdNumbers) {
            uint64_t chatId = chatIdNumber.unsignedLongLongValue;
            if (chatId == self.chatRoom.chatId) {
                selfForwarded = YES;
                break;
            }
        }
        
        if (selfForwarded) {
            for (MEGAChatMessage *message in sentMessages) {
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"temporalId == %" PRIu64, message.temporalId];
                NSArray *filteredArray = [self.messages filteredArrayUsingPredicate:predicate];
                if (filteredArray.count) {
                    MEGALogWarning(@"Forwarded message was already added to the array, probably onMessageUpdate received before now.");
                } else {
                    message.chatId = self.chatRoom.chatId;
                    [self.messages addObject:message];
                    [self finishReceivingMessage];
                    
                    [self updateUnreadMessagesLabel:0];
                    [self scrollToBottomAnimated:YES];

                    if (message.type == MEGAChatMessageTypeAttachment) {
                        [self loadNodesFromMessage:message atTheBeginning:YES];
                    }
                }
            }
            showSuccess = chatIdNumbers.count > 1;
        } else if (chatIdNumbers.count == 1 && !self.chatRoom.isPreview) {
            uint64_t chatId = chatIdNumbers.firstObject.unsignedLongLongValue;
            MEGAChatRoom *chatRoom = [[MEGASdkManager sharedMEGAChatSdk] chatRoomForChatId:chatId];
            MessagesViewController *messagesVC = [[MessagesViewController alloc] init];
            messagesVC.chatRoom = chatRoom;
            
            UINavigationController *chatNC = (UINavigationController *)self.parentViewController;
            [chatNC pushViewController:messagesVC animated:YES];
            [[MEGASdkManager sharedMEGAChatSdk] closeChatRoom:self.chatRoom.chatId delegate:self];
            NSMutableArray *viewControllers = chatNC.viewControllers.mutableCopy;
            [viewControllers removeObjectAtIndex:(viewControllers.count - 2)];
            chatNC.viewControllers = viewControllers;
        } else {
            showSuccess = YES;
        }
        
        if (showSuccess) {
            [SVProgressHUD showSuccessWithStatus:AMLocalizedString(@"messagesSent", @"Success message shown after forwarding messages to other chats")];
        }
    };
    [self presentViewController:sendToNC animated:YES completion:nil];
    [self cancelSelecting:nil];
}

- (void)shareSelectedMessages:(UIBarButtonItem *)sender {
    [SVProgressHUD show];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIActivityViewController *activityViewController = [Helper activityViewControllerForChatMessages:self.selectedMessages sender:sender];
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD dismiss];
            if (activityViewController) {
                [self presentViewController:activityViewController animated:YES completion:nil];
            } else {
                [SVProgressHUD showErrorWithStatus:AMLocalizedString(@"linkUnavailable", nil)];
            }
        });
    });
}

- (void)deleteSelectedMessages {
    NSMutableArray<NSIndexPath *> *indexPaths = [[NSMutableArray alloc] init];
    for (MEGAChatMessage *message in self.selectedMessages) {
        if (message.type == MEGAChatMessageTypeAttachment) {
            [[MEGASdkManager sharedMEGAChatSdk] revokeAttachmentMessageForChat:self.chatRoom.chatId messageId:message.messageId];
        } else {
            NSUInteger index = [self.messages indexOfObject:message];
            if (message.status == MEGAChatMessageStatusSending) {
                [self.messages removeObjectAtIndex:index];
                [indexPaths addObject:[NSIndexPath indexPathForItem:index inSection:0]];
            } else {
                uint64_t messageId = message.status == MEGAChatMessageStatusSending ? message.temporalId : message.messageId;
                MEGAChatMessage *deleteMessage = [[MEGASdkManager sharedMEGAChatSdk] deleteMessageForChat:self.chatRoom.chatId messageId:messageId];
                deleteMessage.chatId = self.chatRoom.chatId;
                [self.messages replaceObjectAtIndex:index withObject:deleteMessage];
            }

        }
    }
    [self.collectionView deleteItemsAtIndexPaths:indexPaths];
    
    [self cancelSelecting:nil];
}

#pragma mark - JSQMessagesViewController method overrides

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)messageText
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date {
    
    if (messageText.mnz_isEmpty) {
        return;
    }
    
    // Emoji replacement:
    NSString *text = messageText;
    NSDictionary<NSString *, NSString *> *emojiDict = @{@":\\)"  : @"🙂", // :)
                                                        @":-\\)" : @"🙂", // :-)
                                                        @":d"    : @"😀",
                                                        @":-d"   : @"😀",
                                                        @";\\)"  : @"😉", // ;)
                                                        @";-\\)" : @"😉", // ;-)
                                                        @";p"    : @"😜",
                                                        @";-p"   : @"😜",
                                                        @":p"    : @"😛",
                                                        @":-p"   : @"😛",
                                                        @":\\("  : @"🙁", // :(
                                                        @":\\\\" : @"😕", // colon+backslash
                                                        @":/"    : @"😕",
                                                        @":\\|"  : @"😐", // :|
                                                        @"d:"    : @"😧",
                                                        @":o"    : @"😮"};
    for (NSString *key in emojiDict.allKeys) {
        NSString *replacement = [emojiDict objectForKey:key];
        NSString *pattern = [NSString stringWithFormat:@"(?>\\s+|^)(%@)(?>\\s+|$)", key];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:(NSRegularExpressionAnchorsMatchLines | NSRegularExpressionCaseInsensitive) error:nil];
        NSUInteger padding = 0;
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
        for (NSTextCheckingResult *result in matches) {
            if (result.numberOfRanges > 1) {
                NSRange range = [result rangeAtIndex:1];
                range.location -= padding;
                padding += range.length - replacement.length;
                text = [text stringByReplacingCharactersInRange:range withString:replacement];
            }
        }
    }
    
    MEGAChatMessage *message = [self sendMessage:text];
    
    if ([MEGAChatSdk hasUrl:text]) {
        MEGAGetAttrUserRequestDelegate *delegate = [[MEGAGetAttrUserRequestDelegate alloc] initWithCompletion:^(MEGARequest *request) {
            if (request.flag) {
                [self reloadMessage:message skippedDialogs:request.number];
                self.richLinkWarningCounterValue = request.number.unsignedIntegerValue;
            }
        } error:^(MEGARequest *request, MEGAError *error) {
            if (request.flag) {
                [self reloadMessage:message skippedDialogs:request.number];
                self.richLinkWarningCounterValue = request.number.unsignedIntegerValue;
            }
        }];
        [[MEGASdkManager sharedMEGASdk] shouldShowRichLinkWarningWithDelegate:delegate];
    }
}

- (void)messagesInputToolbar:(MEGAInputToolbar *)toolbar didPressSendButton:(UIButton *)sender toAttachAssets:(NSArray<PHAsset *> *)assets {
    MEGALogDebug(@"[Chat] Did press send button to attach assets %@", assets);
    MEGANode *parentNode = [[MEGASdkManager sharedMEGASdk] nodeForPath:@"/My chat files"];
    if (parentNode) {
        [self uploadAssets:assets toParentNode:parentNode];
    } else {
        MEGACreateFolderRequestDelegate *createFolderRequestDelegate = [[MEGACreateFolderRequestDelegate alloc] initWithCompletion:^(MEGARequest *request) {
            MEGANode *node = [[MEGASdkManager sharedMEGASdk] nodeForHandle:request.nodeHandle];
            [self uploadAssets:assets toParentNode:node];
        }];
        [[MEGASdkManager sharedMEGASdk] createFolderWithName:@"My chat files" parent:[[MEGASdkManager sharedMEGASdk] rootNode] delegate:createFolderRequestDelegate];
    }
}

- (void)uploadAssets:(NSArray<PHAsset *> *)assets toParentNode:(MEGANode *)parentNode {
    MEGAProcessAsset *processAsset = [[MEGAProcessAsset alloc] initToShareThroughChatWithAssets:assets filePaths:^(NSArray <NSString *> *filePaths) {
        for (NSString *filePath in filePaths) {
            NSString *appData = [[NSString new] mnz_appDataToSaveCoordinates:[filePath mnz_coordinatesOfPhotoOrVideo]];
            [self startUploadAndAttachWithPath:filePath parentNode:parentNode appData:appData];
        }
    } nodes:^(NSArray <MEGANode *> *nodes) {
        for (MEGANode *node in nodes) {
            [self attachOrCopyAndAttachNode:node toParentNode:parentNode];
        }
    } errors:^(NSArray <NSError *> *errors) {
        NSString *title = AMLocalizedString(@"error", nil);
        NSString *message;
        if (errors.count == 1) {
            NSError *error = errors[0];
            message = error.localizedDescription;
        } else {
            message = AMLocalizedString(@"shareExtensionUnsupportedAssets", nil);
        }
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", nil) style:UIAlertActionStyleCancel handler:nil]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alertController animated:YES completion:nil];
        });
    }];
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void) {
        processAsset.originalName = YES;
        [processAsset prepare];
    });
}

- (void)didPressAccessoryButton:(UIButton *)sender {
    switch (sender.tag) {
        case MEGAChatAccessoryButtonCamera: {
            self.inputToolbar.hidden = YES;
            [DevicePermissionsHelper videoPermissionWithCompletionHandler:^(BOOL granted) {
                if (granted) {
                    [DevicePermissionsHelper photosPermissionWithCompletionHandler:^(BOOL granted) {
                        if (granted) {
                            [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                        } else {
                            [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"isSaveMediaCapturedToGalleryEnabled"];
                            [NSUserDefaults.standardUserDefaults synchronize];
                            [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                        }
                    }];
                } else {
                    [DevicePermissionsHelper alertVideoPermissionWithCompletionHandler:nil];
                    self.inputToolbar.hidden = NO;
                }
            }];
            
            break;
        }
            
        case MEGAChatAccessoryButtonUpload: {
            self.inputToolbar.hidden = YES;
            NSString *alertControllerTitle = AMLocalizedString(@"send", @"Label for any 'Send' button, link, text, title, etc. - (String as short as possible).");
            UIAlertController *selectOptionAlertController = [UIAlertController alertControllerWithTitle:alertControllerTitle message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            [selectOptionAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                self.inputToolbar.hidden = self.chatRoom.ownPrivilege <= MEGAChatRoomPrivilegeRo;
            }]];
            
            UIAlertAction *sendFromCloudDriveAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"fromCloudDrive", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                MEGANavigationController *navigationController = [[UIStoryboard storyboardWithName:@"Cloud" bundle:nil] instantiateViewControllerWithIdentifier:@"BrowserNavigationControllerID"];
                [self presentViewController:navigationController animated:YES completion:nil];
                
                BrowserViewController *browserVC = navigationController.viewControllers.firstObject;
                browserVC.browserAction = BrowserActionSendFromCloudDrive;
                browserVC.selectedNodes = ^void(NSArray *selectedNodes) {
                    for (MEGANode *node in selectedNodes) {
                        [Helper importNode:node toShareWithCompletion:^(MEGANode *node) {
                            [[MEGASdkManager sharedMEGAChatSdk] attachNodeToChat:self.chatRoom.chatId node:node.handle delegate:self];
                        }];
                    }
                };
            }];
            [sendFromCloudDriveAlertAction setValue:UIColor.mnz_black333333 forKey:@"titleTextColor"];
            [selectOptionAlertController addAction:sendFromCloudDriveAlertAction];
            
            UIAlertAction *sendContactAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"contact", @"referring to a contact in the contact list of the user") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self presentAddOrAttachParticipantToGroup:nil];
            }];
            [sendContactAlertAction setValue:UIColor.mnz_black333333 forKey:@"titleTextColor"];
            [selectOptionAlertController addAction:sendContactAlertAction];
            
            selectOptionAlertController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
            selectOptionAlertController.popoverPresentationController.sourceView = self.inputToolbar.contentView;
            selectOptionAlertController.popoverPresentationController.sourceRect = self.inputToolbar.contentView.accessoryUploadButton.frame;
            selectOptionAlertController.popoverPresentationController.sourceView = self.inputToolbar.contentView;
            
            [self presentViewController:selectOptionAlertController animated:YES completion:nil];
            selectOptionAlertController.view.tintColor = UIColor.mnz_redMain;

            break;
        }
            
        default:
            break;
    }
    [self updateToolbarPlaceHolder];
}

- (void)didPressJoinButton:(UIButton *)sender {
    if ([[MEGASdkManager sharedMEGAChatSdk] initState] == MEGAChatInitAnonymous) {
        MEGALinkManager.secondaryLinkURL = self.publicChatLink;
        MEGALinkManager.selectedOption = LinkOptionJoinChatLink;
        [self dismissChatRoom];
    } else {
        MEGAChatGenericRequestDelegate *delegate = [[MEGAChatGenericRequestDelegate alloc] initWithCompletion:^(MEGAChatRequest * _Nonnull request, MEGAChatError * _Nonnull error) {
            self.chatRoom = [[MEGASdkManager sharedMEGAChatSdk] chatRoomForChatId:request.chatHandle];
            sender.enabled = YES;
            [self updateJoinView];
        }];
        [[MEGASdkManager sharedMEGAChatSdk] autojoinPublicChat:self.chatRoom.chatId delegate:delegate];
        sender.enabled = NO;
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    [super scrollToBottomAnimated:animated];
    [self hideJumpToBottom];
}

- (void)jsq_setCollectionViewInsetsTopValue:(CGFloat)top bottomValue:(CGFloat)bottom {
    if (self.inputToolbar.frame.size.height < self.initialToolbarHeight) {
        return;
    }
    
    CGRect bounds = self.collectionView.bounds;
    CGFloat increment = bottom - self.collectionView.contentInset.bottom;
    
    UIEdgeInsets insets = UIEdgeInsetsMake(0.0f, 0.0f, bottom, 0.0f);
    self.collectionView.contentInset = insets;
    self.collectionView.scrollIndicatorInsets = insets;
    self.jumpToBottomConstraint.constant = bottom + 27.0f;
    self.lastBottomInset = bottom;

    // If there are no messages, the increment may scroll the collection view beyond its bounds
    CGFloat maxIncrement = self.collectionView.contentSize.height - (bounds.size.height - bottom);
    if (increment > maxIncrement) {
        increment = maxIncrement;
    }
    
    bounds.origin.y += increment;
    bounds.size.height -= bottom;
    [self.collectionView scrollRectToVisible:bounds animated:NO];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showOrHideJumpToBottom];
    });
}

#pragma mark - JSQMessages CollectionView DataSource

- (NSString *)senderId {
    return [NSString stringWithFormat:@"%llu", [MEGASdkManager sharedMEGAChatSdk].myUserHandle];
}

- (NSString *)senderDisplayName {
    return [[MEGASdkManager sharedMEGAChatSdk] myEmail];
}

- (BOOL)isOutgoingMessage:(MEGAChatMessage *)messageItem {
    if (messageItem.isManagementMessage) {
        return NO;
    }
    return [super isOutgoingMessage:messageItem];
}

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    return message;
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didDeleteMessageAtIndexPath:(NSIndexPath *)indexPath {
    [self.messages removeObjectAtIndex:indexPath.item];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    if (message.isManagementMessage || message.isDeleted) {
        return nil;
    }
    
    if ([message.senderId isEqualToString:self.senderId]) {
        return self.outgoingBubbleImageData;
    }
    
    return self.incomingBubbleImageData;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    if (message.userHandle == [MEGASdkManager sharedMEGAChatSdk].myUserHandle || message.type == MEGAChatMessageTypeCallEnded || message.type == MEGAChatMessageTypeCallStarted) {
        return nil;
    }
    if (indexPath.item < self.messages.count-1) {
        MEGAChatMessage *nextMessage = [self.messages objectAtIndex:indexPath.item+1];
        if (nextMessage.userHandle == message.userHandle) {
            return nil;
        }
    }
    NSNumber *avatarKey = @(message.userHandle);
    UIImage *avatar = [self.avatarImages objectForKey:avatarKey];
    if (!avatar) {
        avatar = [UIImage mnz_imageForUserHandle:message.userHandle name:self.chatRoom.title size:CGSizeMake(kAvatarImageDiameter, kAvatarImageDiameter) delegate:nil];
        if (avatar) {
            [self.avatarImages setObject:avatar forKey:avatarKey];
        } else {
            return nil;
        }
    }
    return [self.avatarImageFactory avatarImageWithImage:avatar];
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForUnreadMessagesLabelAtIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *unreadMessagesIndexPath = [self indexPathForCellWithUnreadMessagesLabel];
    if (self.unreadMessages && indexPath.section == unreadMessagesIndexPath.section && indexPath.item == unreadMessagesIndexPath.item) {
        NSString *formatString = self.unreadMessages == 1 ? AMLocalizedString(@"unreadMessage", @"Label in chat rooms that indicates how many messages are unread. Singular and as short as possible.") : AMLocalizedString(@"unreadMessages", @"Label in chat rooms that indicates how many messages are unread. Plural and as short as possible.");
        return [[NSAttributedString alloc] initWithString:[[NSString stringWithFormat:formatString, (unsigned long)self.unreadMessages] uppercaseString]];
    }
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    BOOL showDayMonthYear = NO;
    if (indexPath.item == 0) {
        showDayMonthYear = YES;
    } else if (indexPath.item - 1 > 0) {
        MEGAChatMessage *previousMessage = [self.messages objectAtIndex:(indexPath.item -1)];
        showDayMonthYear = [self showDateBetweenMessage:message previousMessage:previousMessage];
    }
    
    if (showDayMonthYear) {
        NSString *dateString = message.date.mnz_formattedDateMediumStyle;
        NSAttributedString *dateAttributedString = [[NSAttributedString alloc] initWithString:dateString attributes:@{NSFontAttributeName:[UIFont mnz_SFUIMediumWithSize:12.0f], NSForegroundColorAttributeName:UIColor.mnz_black333333}];
        return dateAttributedString;
    }
    
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    
    BOOL showMessageBubbleTopLabel = [self showHourForMessage:message withIndexPath:indexPath];
    if (showMessageBubbleTopLabel) {
        NSString *hour = message.date.mnz_formattedHourAndMinutes;
        NSAttributedString *hourAttributed = [[NSAttributedString alloc] initWithString:hour attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1], NSForegroundColorAttributeName:UIColor.grayColor}];
        NSMutableAttributedString *topCellAttributed = [[NSMutableAttributedString alloc] init];
        
        if (self.chatRoom.isGroup && !message.isManagementMessage) {
            NSString *fullname = [self.chatRoom peerFullnameByHandle:message.userHandle];
            if (!fullname.length) {
                fullname = [self.chatRoom peerEmailByHandle:message.userHandle];
                if (!fullname) {
                    fullname = @"";
                }
            }
            NSAttributedString *fullnameAttributed = [[NSAttributedString alloc] initWithString:[fullname stringByAppendingString:@"   "] attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1], NSForegroundColorAttributeName:UIColor.grayColor}];
            [topCellAttributed appendAttributedString:fullnameAttributed];
            [topCellAttributed appendAttributedString:hourAttributed];
        } else {
            [topCellAttributed appendAttributedString:hourAttributed];
        }
        
        return topCellAttributed;
    }
    
    return nil;
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 8 && ![[MEGASdkManager sharedMEGAChatSdk] isFullHistoryLoadedForChat:self.chatRoom.chatId]) {
        [self loadMessages];
    }
    
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    
    if (message.containsMEGALink) {
        if (![self.observedNodeMessages containsObject:message]) {
            [self.observedNodeMessages addObject:message];
            [message addObserver:self forKeyPath:@"richNumber" options:NSKeyValueObservingOptionNew context:nil];
        }
    }
    
    cell.accessoryButton.hidden = YES;
    
    if (message.isDeleted) {
        cell.textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline].italic;
        cell.textView.textColor = UIColor.mnz_blue2BA6DE;
    } else if (message.isManagementMessage) {
        cell.textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        cell.textView.linkTextAttributes = @{NSForegroundColorAttributeName: UIColor.mnz_black333333,
                                             NSUnderlineColorAttributeName: UIColor.mnz_black333333,
                                             NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone)};
        cell.textView.attributedText = message.attributedText;
    } else if (!message.isMediaMessage) {
        cell.textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        cell.textView.textColor = [message.senderId isEqualToString:self.senderId] ? UIColor.whiteColor : UIColor.mnz_black333333;
        
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : cell.textView.textColor,
                                              NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }
    
    if (message.status == MEGAChatMessageStatusSending || message.status == MEGAChatMessageStatusSendingManual) {
        cell.contentView.alpha = 0.7f;
        if (message.status == MEGAChatMessageStatusSendingManual) {
            [cell.accessoryButton setImage:[UIImage imageNamed:@"sending_manual"] forState:UIControlStateNormal];
            cell.accessoryButton.hidden = NO;
        }
    } else {
        cell.contentView.alpha = 1.0f;
    }
    
    if (cell.textView.text.mnz_isPureEmojiString) {
        cell.messageBubbleImageView.image = nil;
        cell.textView.font = [UIFont mnz_defaultFontForPureEmojiStringWithEmojis:[cell.textView.text mnz_emojiCount]];
    } else if (message.attributedText.length > 0) {
        cell.textView.attributedText = message.attributedText;
    }
    
    if (self.selectingMessages) {
        cell.accessoryButton.hidden = YES;
        cell.avatarImageView.hidden = YES;
        cell.selectionImageView.hidden = !(message.type == MEGAChatMessageTypeNormal || message.type == MEGAChatMessageTypeContainsMeta || message.type == MEGAChatMessageTypeContact || message.type == MEGAChatMessageTypeAttachment);
        cell.selectionImageView.image = [self.selectedMessages containsObject:message] ? [UIImage imageNamed:@"checkBoxSelected"] : [UIImage imageNamed:@"checkBoxUnselected"];
    } else {
        cell.avatarImageView.hidden = NO;
        cell.selectionImageView.hidden = YES;
        if (message.shouldShowForwardAccessory && [MEGASdkManager sharedMEGAChatSdk].initState != MEGAChatInitAnonymous) {
            [cell.accessoryButton setImage:[UIImage imageNamed:@"forward"] forState:UIControlStateNormal];
            cell.accessoryButton.hidden = NO;
        }
    }
    
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    UICollectionReusableView *reusableview = nil;
    
    if (kind == UICollectionElementKindSectionHeader) {
        [self setChatOpenMessageForIndexPath:indexPath];
        return self.openMessageHeaderView;
    }

    return reusableview;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    BOOL isiPhone4XOr5X = ([[UIDevice currentDevice] iPhone4X] || [[UIDevice currentDevice] iPhone5X]);
    CGFloat height = (isiPhone4XOr5X ? 490.0f : 470.0f);
    CGFloat minimumHeight = self.loadingState || self.isFirstLoad ? 0.0f : height;
    
    return CGSizeMake(self.view.frame.size.width, minimumHeight);
}

#pragma mark - UICollectionViewDelegate

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self showOrHideJumpToBottom];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [self showOrHideJumpToBottom];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self hideJumpToBottom];
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
    [self hideJumpToBottom];
}

#pragma mark - Custom menu items

- (BOOL)collectionView:(UICollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (self.selectingMessages) return NO;
    if ([MEGASdkManager sharedMEGAChatSdk].initState == MEGAChatInitAnonymous && action != @selector(copy:)) return NO;
    
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    switch (message.type) {
        case MEGAChatMessageTypeInvalid:
        case MEGAChatMessageTypeRevokeAttachment:
            break;
            
        case MEGAChatMessageTypeNormal: {
            //All messages
            if (action == @selector(copy:)) return YES;
            if (action == @selector(forward:message:)) return YES;

            //Your messages
            if ([message.senderId isEqualToString:self.senderId]) {
                if (action == @selector(delete:)) {
                    if (message.isDeletable) {
                        if (!self.editMessage || self.editMessage.messageId != message.messageId) {
                            return YES;
                        }
                    }
                }
                
                if (action == @selector(edit:message:)) {
                    if (message.isEditable) return YES;
                }
            }
            break;
        }
            
        case MEGAChatMessageTypeContainsMeta: {
            //All messages
            if (action == @selector(copy:)) return YES;
            if (action == @selector(forward:message:)) return YES;

            //Your messages
            if ([message.senderId isEqualToString:self.senderId]) {
                if (action == @selector(delete:)) {
                    if (message.isDeletable) {
                        if (!self.editMessage || self.editMessage.messageId != message.messageId) {
                            return YES;
                        }
                    }
                }
                
                if (action == @selector(edit:message:)) {
                    if (message.isEditable) return YES;
                }
                
                if (action == @selector(removeRichPreview:message:indexPath:)) {
                    if (message.isEditable) return YES;
                }
            }
            break;
        }
            
        case MEGAChatMessageTypeAlterParticipants:
        case MEGAChatMessageTypeTruncate:
        case MEGAChatMessageTypePrivilegeChange:
        case MEGAChatMessageTypeChatTitle: {
            if (action == @selector(copy:)) return YES;
            break;
        }
            
        case MEGAChatMessageTypeAttachment: {
            if (action == @selector(download:message:)) return YES;
            if (action == @selector(forward:message:)) return YES;

            if ([message.senderId isEqualToString:self.senderId]) {
                if (action == @selector(delete:) && message.isDeletable) return YES;
            } else {
                if (action == @selector(import:message:)) return YES;
            }
            break;
        }
            
        case MEGAChatMessageTypeContact: {
            if (action == @selector(forward:message:)) return YES;

            if ([message.senderId isEqualToString:self.senderId]) {
                if (action == @selector(delete:)) {
                    if (message.isDeletable) return YES;
                }
                //TODO: Send Message
            }
                        
            if (action == @selector(addContact:message:)) {
                if (message.usersCount == 1) {
                    NSString *email = [message userEmailAtIndex:0];
                    MEGAUser *user = [[MEGASdkManager sharedMEGASdk] contactForEmail:email];
                    if (user.visibility != MEGAUserVisibilityVisible) return YES;
                } else {
                    for (NSInteger i = 0; i < message.usersCount; i++) {
                        NSString *email = [message userEmailAtIndex:i];
                        MEGAUser *user = [[MEGASdkManager sharedMEGASdk] contactForEmail:email];
                        if (user.visibility == MEGAUserVisibilityVisible) return NO;
                    }
                    return YES;
                }
            }
            break;
        }
            
        default:
            return NO;
            break;
    }
    
    return NO;
}

- (void)collectionView:(UICollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    if (action == @selector(edit:message:)) {
        [self edit:sender message:message];
        return;
    }
    if (action == @selector(forward:message:)) {
        [self forward:sender message:message];
        return;
    }
    if (action == @selector(import:message:)) {
        [self import:sender message:message];
        return;
    }
    if (action == @selector(download:message:)) {
        [self download:sender message:message];
        return;
    }
    if (action == @selector(addContact:message:)) {
        [self addContact:sender message:message];
        return;
    }
    if (action == @selector(removeRichPreview:message:indexPath:)) {
        [self removeRichPreview:sender message:message indexPath:indexPath];
        return;
    }
    if (action == @selector(delete:)) {
        [self delete:sender message:message indexPath:indexPath];
        return;
    }
    
    [super collectionView:collectionView performAction:action forItemAtIndexPath:indexPath withSender:sender];
}

- (void)edit:(id)sender message:(MEGAChatMessage *)message {
    [self.inputToolbar.contentView.textView becomeFirstResponder];
    self.inputToolbar.contentView.textView.text = message.content;
    self.editMessage = message;
}

- (void)forward:(id)sender message:(MEGAChatMessage *)message {
    self.toolbarType = ToolbarTypeForward;
    [self startSelecting:message];
}

- (void)delete:(id)sender message:(MEGAChatMessage *)message indexPath:(NSIndexPath *)indexPath {
    self.toolbarType = ToolbarTypeDelete;
    [self startSelecting:message];
}

- (void)import:(id)sender message:(MEGAChatMessage *)message {
    NSMutableArray *nodesArray = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < message.nodeList.size.unsignedIntegerValue; i++) {
        MEGANode *node = [message.nodeList nodeAtIndex:i];
        if (self.chatRoom.isPreview) {
            node = [[MEGASdkManager sharedMEGASdk] authorizeChatNode:node cauth:self.chatRoom.authorizationToken];
        }
        if (node) {
            [nodesArray addObject:node];
        }
    }
    MEGANavigationController *navigationController = [[UIStoryboard storyboardWithName:@"Cloud" bundle:nil] instantiateViewControllerWithIdentifier:@"BrowserNavigationControllerID"];
    [self presentViewController:navigationController animated:YES completion:nil];
    BrowserViewController *browserVC = navigationController.viewControllers.firstObject;
    browserVC.selectedNodesArray = nodesArray;
    browserVC.browserAction = BrowserActionImport;
}

- (void)download:(id)sender message:(MEGAChatMessage *)message {
    BOOL downloading = NO;
    for (NSUInteger i = 0; i < message.nodeList.size.unsignedIntegerValue; i++) {
        MEGANode *node = [message.nodeList nodeAtIndex:i];
        if (self.chatRoom.isPreview) {
            node = [[MEGASdkManager sharedMEGASdk] authorizeChatNode:node cauth:self.chatRoom.authorizationToken];
        }
        if (node) {
            [Helper downloadNode:node folderPath:[Helper relativePathForOffline] isFolderLink:NO shouldOverwrite:NO];
            downloading = YES;
        }
    }
    if (downloading) {
        [SVProgressHUD showImage:[UIImage imageNamed:@"hudDownload"] status:AMLocalizedString(@"downloadStarted", @"Message shown when a download starts")];
    }
}

- (void)addContact:(id)sender message:(MEGAChatMessage *)message {
    NSUInteger usersCount = message.usersCount;
    MEGAInviteContactRequestDelegate *inviteContactRequestDelegate = [[MEGAInviteContactRequestDelegate alloc] initWithNumberOfRequests:usersCount];
    for (NSUInteger i = 0; i < usersCount; i++) {
        NSString *email = [message userEmailAtIndex:i];
        [[MEGASdkManager sharedMEGASdk] inviteContactWithEmail:email message:@"" action:MEGAInviteActionAdd delegate:inviteContactRequestDelegate];
    }
}

- (void)removeRichPreview:(id)sender message:(MEGAChatMessage *)message indexPath:(NSIndexPath *)indexPath {
    [[MEGASdkManager sharedMEGAChatSdk] removeRichLinkForChat:self.chatRoom.chatId messageId:message.messageId];
}

#pragma mark - JSQMessages collection view flow layout delegate

#pragma mark - Adjusting cell label heights

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForUnreadMessagesLabelAtIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *unreadMessagesIndexPath = [self indexPathForCellWithUnreadMessagesLabel];
    return (self.unreadMessages && indexPath.section == unreadMessagesIndexPath.section && indexPath.item == unreadMessagesIndexPath.item) ? 44.0f : 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    BOOL showDayMonthYear = NO;
    if (indexPath.item == 0) {
        showDayMonthYear = YES;
    } else if (indexPath.item - 1 > 0) {
        MEGAChatMessage *previousMessage = [self.messages objectAtIndex:(indexPath.item - 1)];
        showDayMonthYear = [self showDateBetweenMessage:message previousMessage:previousMessage];
    }
    
    if (showDayMonthYear) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat height = 0.0f;
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    
    BOOL showMessageBubleTopLabel = [self showHourForMessage:message withIndexPath:indexPath];
    if (showMessageBubleTopLabel) {
        NSAttributedString *bubbleTopString = [self collectionView:collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:indexPath];
        CGFloat boundingWidth = collectionViewLayout.itemWidth - 28;
        NSInteger boundingHeight = CGRectIntegral([bubbleTopString boundingRectWithSize:CGSizeMake(boundingWidth, CGFLOAT_MAX)
                                                                                options:NSStringDrawingUsesLineFragmentOrigin
                                                                                context:nil]).size.height;
        if (self.chatRoom.isGroup) {
            height = boundingHeight + kGroupChatCellLabelHeightBuffer;
        } else {
            height = boundingHeight + k1on1CellLabelHeightBuffer;
        }
    }
    
    return height;
}

#pragma mark - Responding to collection view tap events

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
                header:(JSQMessagesLoadEarlierHeaderView *)headerView didTapLoadEarlierMessagesButton:(UIButton *)sender {
    NSLog(@"Load earlier messages!");
    [self loadMessages];
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapAvatarImageView:(UIImageView *)avatarImageView atIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"Tapped avatar!");
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath {
    [self hideInputToolbar];
    
    MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    
    if (self.selectingMessages) {
        [self toggleSelectedMessage:message atIndexPath:indexPath];
    } else {
        if (message.type == MEGAChatMessageTypeAttachment) {
            if (message.nodeList.size.unsignedIntegerValue == 1) {
                MEGANode *node = [message.nodeList nodeAtIndex:0];
                if (self.chatRoom.isPreview) {
                    node = [[MEGASdkManager sharedMEGASdk] authorizeChatNode:node cauth:self.chatRoom.authorizationToken];
                }
                if (!node) {
                    return;
                }
                if (node.name.mnz_isImagePathExtension || node.name.mnz_isVideoPathExtension) {
                    NSArray<MEGAChatMessage *> *reverseArray = [[self.attachmentMessages reverseObjectEnumerator] allObjects];
                    NSMutableArray<MEGANode *> *mediaNodesArray = [[NSMutableArray<MEGANode *> alloc] initWithCapacity:reverseArray.count];
                    for (MEGAChatMessage *attachmentMessage in reverseArray) {
                        MEGANode *tempNode = [attachmentMessage.nodeList nodeAtIndex:0];
                        if (self.chatRoom.isPreview) {
                            tempNode = [[MEGASdkManager sharedMEGASdk] authorizeChatNode:tempNode cauth:self.chatRoom.authorizationToken];
                        }
                        if (tempNode) {
                            [mediaNodesArray addObject:tempNode];
                        }
                    }
                    
                    MEGAPhotoBrowserViewController *photoBrowserVC = [MEGAPhotoBrowserViewController photoBrowserWithMediaNodes:mediaNodesArray api:[MEGASdkManager sharedMEGASdk] displayMode:DisplayModeSharedItem presentingNode:nil preferredIndex:[reverseArray indexOfObject:message]];
                    photoBrowserVC.delegate = self;
                    
                    [self.navigationController presentViewController:photoBrowserVC animated:YES completion:nil];
                } else {
                    [node mnz_openNodeInNavigationController:self.navigationController folderLink:NO];
                }
            } else {
                ChatAttachedNodesViewController *chatAttachedNodesVC = [[UIStoryboard storyboardWithName:@"Chat" bundle:nil] instantiateViewControllerWithIdentifier:@"ChatAttachedNodesViewControllerID"];
                chatAttachedNodesVC.message = message;
                [self.navigationController pushViewController:chatAttachedNodesVC animated:YES];
            }
        } else if (message.type == MEGAChatMessageTypeContact) {
            if (message.usersCount == 1) {
                NSString *userEmail = [message userEmailAtIndex:0];
                NSString *userName = [message userNameAtIndex:0];
                uint64_t userHandle = [message userHandleAtIndex:0];
                ContactDetailsViewController *contactDetailsVC = [[UIStoryboard storyboardWithName:@"Contacts" bundle:nil] instantiateViewControllerWithIdentifier:@"ContactDetailsViewControllerID"];
                contactDetailsVC.contactDetailsMode = ContactDetailsModeDefault;
                contactDetailsVC.userEmail          = userEmail;
                contactDetailsVC.userName           = userName;
                contactDetailsVC.userHandle         = userHandle;
                [self.navigationController pushViewController:contactDetailsVC animated:YES];
            } else {
                ChatAttachedContactsViewController *chatAttachedContactsVC = [[UIStoryboard storyboardWithName:@"Chat" bundle:nil] instantiateViewControllerWithIdentifier:@"ChatAttachedContactsViewControllerID"];
                chatAttachedContactsVC.message = message;
                [self.navigationController pushViewController:chatAttachedContactsVC animated:YES];
            }
        } else if (message.type == MEGAChatMessageTypeContainsMeta) {
            NSURL *url = [NSURL URLWithString:message.containsMeta.richPreview.url];
            MEGALinkManager.linkURL = url;
            [MEGALinkManager processLinkURL:url];
        } else if (message.node) {
            MEGALinkManager.linkURL = message.MEGALink;
            [MEGALinkManager processLinkURL:message.MEGALink];
        }
    }
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapCellAtIndexPath:(NSIndexPath *)indexPath touchLocation:(CGPoint)touchLocation {
    if (self.selectingMessages) {
        MEGAChatMessage *message = [self.messages objectAtIndex:indexPath.item];
        [self toggleSelectedMessage:message atIndexPath:indexPath];
    } else {
        [self hideInputToolbar];
    }
}

#pragma mark - JSQMessagesComposerTextViewPasteDelegate methods

- (BOOL)composerTextView:(JSQMessagesComposerTextView *)textView shouldPasteWithSender:(id)sender {
    if (UIPasteboard.generalPasteboard.image) {
        return NO;
    }
    return YES;
}

#pragma mark - JSQMessagesViewAccessoryDelegate methods

- (void)messageView:(JSQMessagesCollectionView *)view didTapAccessoryButtonAtIndexPath:(NSIndexPath *)path {
    __block MEGAChatMessage *message = [self.messages objectAtIndex:path.item];
    if (message.status == MEGAChatMessageStatusSendingManual) {
        if ([[UIDevice currentDevice] iPhoneDevice]) {
            [self.inputToolbar.contentView.textView resignFirstResponder];
        }
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        
        [alertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
        
        UIAlertAction *retryAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"retry", @"Button which allows to retry send message in chat conversation.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSLog(@"retry tapped"); // sent message + discard || delete
            [[MEGASdkManager sharedMEGAChatSdk] removeUnsentMessageForChat:self.chatRoom.chatId rowId:message.rowId];
            
            switch (message.type) {
                case MEGAChatMessageTypeNormal: {
                    MEGAChatMessage *retryMessage = [[MEGASdkManager sharedMEGAChatSdk] sendMessageToChat:self.chatRoom.chatId message:message.text];
                    [self.messages replaceObjectAtIndex:path.item withObject:retryMessage];
                    break;
                }
                    
                case MEGAChatMessageTypeAttachment: {
                    MEGANode *node = [message.nodeList nodeAtIndex:0];
                    [[MEGASdkManager sharedMEGAChatSdk] attachNodeToChat:self.chatRoom.chatId node:node.handle delegate:self];
                    [self.messages removeObjectAtIndex:path.item];
                    [self.collectionView deleteItemsAtIndexPaths:@[path]];
                    break;
                }
                    
                case MEGAChatMessageTypeContact: {
                    NSMutableArray *users = [[NSMutableArray alloc] init];
                    for (NSUInteger i = 0; i < message.usersCount; i++) {
                        MEGAUser *user = [[MEGASdkManager sharedMEGASdk] contactForEmail:[message userEmailAtIndex:i]];
                        if (user) {
                            [users addObject:user];
                        }
                    }
                    
                    MEGAChatMessage *retryMessage = [[MEGASdkManager sharedMEGAChatSdk] attachContactsToChat:self.chatRoom.chatId contacts:users];
                    [self.messages replaceObjectAtIndex:path.item withObject:retryMessage];
                    break;
                }
                    
                default:
                    break;
            }
        }];
        [retryAlertAction setValue:UIColor.mnz_black333333 forKey:@"titleTextColor"];
        [alertController addAction:retryAlertAction];
        
        [alertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"deleteMessage", @"Button which allows to delete message in chat conversation.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[MEGASdkManager sharedMEGAChatSdk] removeUnsentMessageForChat:self.chatRoom.chatId rowId:message.rowId];
            [self.messages removeObjectAtIndex:path.item];
            [self.collectionView deleteItemsAtIndexPaths:@[path]];
        }]];
        
        alertController.modalPresentationStyle = UIModalPresentationPopover;
        UIPopoverPresentationController *popoverPresentationController = alertController.popoverPresentationController;
        CGRect deleteRect = [[view cellForItemAtIndexPath:path] bounds];
        popoverPresentationController.sourceRect = deleteRect;
        popoverPresentationController.sourceView = [view cellForItemAtIndexPath:path];
        popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        
        [self presentViewController:alertController animated:YES completion:nil];
    } else if (message.shouldShowForwardAccessory) {
        [self.selectedMessages addObject:message];
        [self forwardSelectedMessages];
    }
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    [super textViewDidChange:textView];
    NSInteger textLength =  textView.text.length;
    if (textLength > 0 && !self.sendTypingTimer.isValid) {
        self.sendTypingTimer = [NSTimer scheduledTimerWithTimeInterval:4.0 target:self selector:@selector(doNothing) userInfo:nil repeats:NO];
        [[MEGASdkManager sharedMEGAChatSdk] sendTypingNotificationForChat:self.chatRoom.chatId];
    } else if (textLength == 0) {
        [[MEGASdkManager sharedMEGAChatSdk] sendStopTypingNotificationForChat:self.chatRoom.chatId];
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    [self saveChatDraft];
}

#pragma mark - MEGAPhotoBrowserDelegate

- (void)photoBrowser:(MEGAPhotoBrowserViewController *)photoBrowser willDismissWithNode:(MEGANode *)node {
    [self setLastMessageAsSeen];
}

#pragma mark - DZNEmptyDataSetSource

- (UIView *)customViewForEmptyDataSet:(UIScrollView *)scrollView {
    UIImageView *skeletonImageView = nil;
    
    if (self.loadingState) {
        skeletonImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"chatroomLoading"]];
    }
    
    return skeletonImageView;
}

#pragma mark - MEGAChatRoomDelegate

- (void)onMessageReceived:(MEGAChatSdk *)api message:(MEGAChatMessage *)message {
    MEGALogInfo(@"onMessageReceived %@", message);
    message.chatId= self.chatRoom.chatId;
    
    if (message.type == MEGAChatMessageTypeCallEnded) {
        [self hideActiveCallButton];
    }

    switch (message.type) {
        case MEGAChatMessageTypeInvalid:
            break;
            
        case MEGAChatMessageTypeNormal:
        case MEGAChatMessageTypeAlterParticipants:
        case MEGAChatMessageTypePrivilegeChange:
        case MEGAChatMessageTypeChatTitle:
        case MEGAChatMessageTypeAttachment:
        case MEGAChatMessageTypeContact:
        case MEGAChatMessageTypeCallEnded:
        case MEGAChatMessageTypeCallStarted:
        case MEGAChatMessageTypeContainsMeta:
        case MEGAChatMessageTypePublicHandleCreate:
        case MEGAChatMessageTypePublicHandleDelete:
        case MEGAChatMessageTypeSetPrivateMode: {        
            NSUInteger unreads;
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive && UIApplication.mnz_visibleViewController == self) {
                [[MEGASdkManager sharedMEGAChatSdk] setMessageSeenForChat:self.chatRoom.chatId messageId:message.messageId];
                unreads = [message.senderId isEqualToString:self.senderId] ? 0 : self.unreadMessages + 1;
            } else {
                self.chatRoom = [api chatRoomForChatId:self.chatRoom.chatId];
                self.unreadMessages = self.chatRoom.unreadCount;
                unreads = [message.senderId isEqualToString:self.senderId] ? 0 : self.unreadMessages;
            }
            
            [self.messages addObject:message];
            [self finishReceivingMessage];
            
            [self updateUnreadMessagesLabel:unreads];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSUInteger items = [self.collectionView numberOfItemsInSection:0];
                NSUInteger visibleItems = self.collectionView.indexPathsForVisibleItems.count;
                if (items > 1 && visibleItems > 0) {
                    NSIndexPath *lastCellIndexPath = [NSIndexPath indexPathForItem:(items - 2) inSection:0];
                    if ([self.collectionView.indexPathsForVisibleItems containsObject:lastCellIndexPath]) {
                        [self scrollToBottomAnimated:YES];
                    } else {
                        [self showJumpToBottomWithMessage:AMLocalizedString(@"newMessages", @"Label in a button that allows to jump to the latest message")];
                    }
                } else {
                    [self scrollToBottomAnimated:YES];
                }
            });
            
            [self loadNodesFromMessage:message atTheBeginning:YES];
            break;
        }
        case MEGAChatMessageTypeTruncate:
            [self handleTruncateMessage:message];
            break;
            
        case MEGAChatMessageTypeRevokeAttachment:
            break;
            
        default:
            break;
    }
}

- (void)onMessageLoaded:(MEGAChatSdk *)api message:(MEGAChatMessage *)message {
    MEGALogInfo(@"onMessageLoaded %@", message);
    
    if (message) {
        message.chatId = self.chatRoom.chatId;
        
        switch (message.type) {
            case MEGAChatMessageTypeInvalid:
                break;
                
            case MEGAChatMessageTypeNormal:
            case MEGAChatMessageTypeAlterParticipants:
            case MEGAChatMessageTypeTruncate:
            case MEGAChatMessageTypePrivilegeChange:
            case MEGAChatMessageTypeChatTitle:
            case MEGAChatMessageTypeAttachment:
            case MEGAChatMessageTypeContact:
            case MEGAChatMessageTypeCallEnded:
            case MEGAChatMessageTypeCallStarted:
            case MEGAChatMessageTypeContainsMeta:
            case MEGAChatMessageTypePublicHandleCreate:
            case MEGAChatMessageTypePublicHandleDelete:
            case MEGAChatMessageTypeSetPrivateMode: {
                if (!message.isDeleted) {
                    [self.messages insertObject:message atIndex:0];
                }
                break;
            }
                
            case MEGAChatMessageTypeRevokeAttachment:
                break;
                
            default:
                break;
        }
        
        [self loadNodesFromMessage:message atTheBeginning:NO];
    
        if (!self.areAllMessagesSeen && message.userHandle != [MEGASdkManager sharedMEGAChatSdk].myUserHandle) {
            if ([[MEGASdkManager sharedMEGAChatSdk] lastChatMessageSeenForChat:self.chatRoom.chatId].messageId != message.messageId) {
                if (!self.isFirstLoad || self.unreadMessages >= 0) {
                    if ([[MEGASdkManager sharedMEGAChatSdk] setMessageSeenForChat:self.chatRoom.chatId messageId:message.messageId]) {
                        self.areAllMessagesSeen = YES;
                    } else {
                        MEGALogError(@"setMessageSeenForChat failed: The chatid is invalid or the message is older than last-seen-by-us message.");
                    }
                }
            } else {
                self.areAllMessagesSeen = YES;
            }
        }
    } else {
        if (!self.loadMessagesLater) {
            [SVProgressHUD dismiss];
            self.loadingState = NO;
        }
        if (self.isFirstLoad) {
            if (self.unreadMessages < 0 && self.unreadMessages > -kMaxMessagesToLoad) {
                if (self.chatRoom.unreadCount < 0) {
                    self.unreadMessages += self.chatRoom.unreadCount;
                } else {
                    self.unreadMessages = self.chatRoom.unreadCount;
                }
                [self loadMessages];
            } else {
                self.isFirstLoad = NO;
                MEGAChatMessage *lastMessage = self.messages.lastObject;
                if (lastMessage && [[MEGASdkManager sharedMEGAChatSdk] setMessageSeenForChat:self.chatRoom.chatId messageId:lastMessage.messageId]) {
                    self.areAllMessagesSeen = YES;
                } else {
                    MEGALogError(@"setMessageSeenForChat failed: There is no message, the chatid is invalid or the message is older than last-seen-by-us message.");
                }
                if (self.unreadMessages < 0) {
                    self.unreadMessages = 0;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.collectionView reloadData];
                });
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSInteger numberOfItemsInSection = [self.collectionView numberOfItemsInSection:0];
                    NSInteger item = numberOfItemsInSection - (self.unreadMessages + 1);
                    if (item < 0) {
                        item = 0;
                    }
                    NSIndexPath *lastUnreadIndexPath = [NSIndexPath indexPathForItem:item inSection:0];
                    if (numberOfItemsInSection) {
                        [self.collectionView scrollToItemAtIndexPath:lastUnreadIndexPath atScrollPosition:UICollectionViewScrollPositionTop animated:NO];
                    }
                    
                    if (self.unreadMessages) {
                        [self showOrHideJumpToBottom];
                    }
                });
            }
        } else {
            // TODO: improve load earlier messages
            CGFloat oldContentOffsetFromBottomY = self.collectionView.contentSize.height - self.collectionView.contentOffset.y;
            [self.collectionView reloadData];
            [self.collectionView layoutIfNeeded];
            CGPoint newContentOffset = CGPointMake(self.collectionView.contentOffset.x, self.collectionView.contentSize.height - oldContentOffsetFromBottomY);
            self.collectionView.contentOffset = newContentOffset;
        }
    }
}

- (void)onMessageUpdate:(MEGAChatSdk *)api message:(MEGAChatMessage *)message {
    MEGALogInfo(@"onMessageUpdate %@", message);
    
    message.chatId = self.chatRoom.chatId;
    if ([message hasChangedForType:MEGAChatMessageChangeTypeStatus]) {
        switch (message.status) {
            case MEGAChatMessageStatusUnknown:
                break;
                
            case MEGAChatMessageStatusSending:
                break;
                
            case MEGAChatMessageStatusSendingManual:
                break;
                
            case MEGAChatMessageStatusServerReceived: {
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"temporalId == %" PRIu64, message.temporalId];
                NSArray *filteredArray = [self.messages filteredArrayUsingPredicate:predicate];
                
                if (filteredArray.count) {
                    MEGAChatMessage *oldMessage = filteredArray.firstObject;
                    if (oldMessage.warningDialog > MEGAChatMessageWarningDialogNone) {
                        message.warningDialog = oldMessage.warningDialog;
                        if (![self.observedDialogMessages containsObject:message]) {
                            [self.observedDialogMessages addObject:message];
                            [message addObserver:self forKeyPath:@"warningDialog" options:NSKeyValueObservingOptionNew context:nil];
                        }
                    }
                    NSUInteger index = [self.messages indexOfObject:oldMessage];
                    [self.messages replaceObjectAtIndex:index withObject:message];
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                    if ([[self.collectionView indexPathsForVisibleItems] containsObject:indexPath]) {
                        [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
                    }
                } else {
                    message.chatId = self.chatRoom.chatId;
                    [self.messages addObject:message];
                    [self finishReceivingMessage];
                    
                    NSUInteger unreads = [message.senderId isEqualToString:self.senderId] ? 0 : self.unreadMessages + 1;
                    [self updateUnreadMessagesLabel:unreads];

                    if ([MEGASdkManager sharedMEGAChatSdk].myUserHandle == message.userHandle) {
                        [self scrollToBottomAnimated:YES];
                    }
                    
                    if (message.type == MEGAChatMessageTypeAttachment) {
                        [self loadNodesFromMessage:message atTheBeginning:YES];
                    } else {
                        MEGALogWarning(@"Message to update was not in the array of messages, probably forwarded, added.");
                    }
                }

                break;
            }
                
            case MEGAChatMessageStatusServerRejected: {
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageId == %" PRIu64, message.messageId];
                NSArray *filteredArray = [self.messages filteredArrayUsingPredicate:predicate];
                if (filteredArray.count) {
                    NSUInteger index = [self.messages indexOfObject:filteredArray[0]];
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                
                    [self.messages removeObjectAtIndex:index];
                    [self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
                }
                break;
            }
                
            case MEGAChatMessageStatusDelivered:
                break;
                
            case MEGAChatMessageStatusNotSeen:
                break;
                
            case MEGAChatMessageStatusSeen:
                break;
                
            default:
                break;
        }
    }
    
    if ([message hasChangedForType:MEGAChatMessageChangeTypeContent]) {
        if (message.isDeleted || message.isEdited) {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageId == %" PRIu64, message.messageId];
            NSArray *filteredArray = [self.messages filteredArrayUsingPredicate:predicate];
            if (filteredArray.count) {
                NSUInteger index = [self.messages indexOfObject:filteredArray[0]];
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                if (message.isEdited) {
                    UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
                    CGFloat previousHeight = cell.frame.size.height;
                    [self.messages replaceObjectAtIndex:index withObject:message];
                    [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
                    [self updateOffsetForCellAtIndexPath:indexPath previousHeight:previousHeight];
                }
                if (message.isDeleted) {
                    [self.messages removeObjectAtIndex:index];
                    [self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
                }
            } else {
                MEGALogWarning(@"Message to update is not in the array of messages");
                NSAssert(filteredArray.count, @"Message to update is not in the array of messages");
            }
        }
        
        if (message.type == MEGAChatMessageTypeTruncate) {
            [self handleTruncateMessage:message];
        }
    }
}

- (void)onChatRoomUpdate:(MEGAChatSdk *)api chat:(MEGAChatRoom *)chat {
    MEGALogInfo(@"onChatRoomUpdate %@", chat);
    self.chatRoom = chat;
    switch (chat.changes) {
        case MEGAChatRoomChangeTypeUnreadCount:
            break;
            
        case MEGAChatRoomChangeTypeParticipants: {
            [self customNavigationBarLabel];
            [self updateToolbarPlaceHolder];
            
            if (self.collectionView.indexPathsForVisibleItems.count > 0) {
                [self.collectionView performBatchUpdates:^{
                    [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
                    [self.collectionView reloadItemsAtIndexPaths:self.collectionView.indexPathsForVisibleItems];
                } completion:nil];
            }
            
            break;
        }
            
        case MEGAChatRoomChangeTypeTitle:
            [self customNavigationBarLabel];
            [self updateToolbarPlaceHolder];
            
            break;
            
        case MEGAChatRoomChangeTypeUserTyping: {
            if (chat.userTypingHandle != api.myUserHandle) {
                NSNumber *userTypingHandle = [NSNumber numberWithUnsignedLongLong:chat.userTypingHandle];
                NSTimer *userTypingTimer = [self.whoIsTypingTimersMutableDictionary objectForKey:userTypingHandle];
                if (userTypingTimer) {
                    [userTypingTimer invalidate];
                }
                userTypingTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(userTypingTimerFireMethod:) userInfo:userTypingHandle repeats:NO];
                [self.whoIsTypingTimersMutableDictionary setObject:userTypingTimer forKey:userTypingHandle];
                
                [self setTypingIndicator];
            }
            
            break;
        }
            
        case MEGAChatRoomChangeTypeClosed:
            if (self.chatRoom.preview) {
                self.chatLinkBeenClosed = YES;
                [api closeChatPreview:chat.chatId];
                [self updateJoinView];
                [SVProgressHUD showInfoWithStatus:AMLocalizedString(@"linkRemoved", @"Message shown when the link to a file or folder has been removed")];
            } else {
                [api closeChatRoom:chat.chatId delegate:self];
                [self.navigationController popToRootViewControllerAnimated:YES];
            }
            break;
            
        case MEGAChatRoomChangeTypeUserStopTyping: {
            if (chat.userTypingHandle != api.myUserHandle) {
                [self removeUserHandleFromTypingIndicator:[NSNumber numberWithUnsignedLongLong:chat.userTypingHandle]];
            }
            break;
        }
            
        case MEGAChatRoomChangeTypeArchive:
            [self customNavigationBarLabel];
            break;
            
        case MEGAChatRoomChangeTypeUpdatePreviewers:
            [self updateJoinView];
            
            self.previewersView.hidden = self.chatRoom.previewersCount == 0;
            self.previewersLabel.text = [NSString stringWithFormat:@"%tu", self.chatRoom.previewersCount];
            break;
            
        default:
            break;
    }
}

- (void)onChatOnlineStatusUpdate:(MEGAChatSdk *)api userHandle:(uint64_t)userHandle status:(MEGAChatStatus)onlineStatus inProgress:(BOOL)inProgress {
    if (inProgress || userHandle == api.myUserHandle || self.chatRoom.isGroup) {
        return;
    }
    
    if ([self.chatRoom peerHandleAtIndex:0] == userHandle && onlineStatus != MEGAChatStatusInvalid) {
        [self customNavigationBarLabel];
        
        if (self.openMessageHeaderView) {
            self.openMessageHeaderView.onlineStatusLabel.text = self.lastChatRoomStateString;
            self.openMessageHeaderView.onlineStatusView.backgroundColor = self.lastChatRoomStateColor;
        }
    }
}

- (void)onChatConnectionStateUpdate:(MEGAChatSdk *)api chatId:(uint64_t)chatId newState:(int)newState {
    if (chatId == self.chatRoom.chatId) {
        [self customNavigationBarLabel];
        
        if (newState == MEGAChatConnectionOnline) {
            [self updateUIbasedOnChatConnectionAndReachability];
            if (self.loadMessagesLater) {
                self.loadMessagesLater = NO;
                self.isFirstLoad = YES;
                [self loadMessages];
            }
        } else if (newState == MEGAChatConnectionOffline) {
            [self updateUIbasedOnChatConnectionAndReachability];
        }
    }
}

- (void)onChatPresenceLastGreen:(MEGAChatSdk *)api userHandle:(uint64_t)userHandle lastGreen:(NSInteger)lastGreen {
    if (self.chatRoom.isGroup) {
        return;
    } else {
        if ([self.chatRoom peerHandleAtIndex:0] == userHandle) {
            MEGAChatStatus chatStatus = [[MEGASdkManager sharedMEGAChatSdk] userOnlineStatus:[self.chatRoom peerHandleAtIndex:0]];
            if (chatStatus < MEGAChatStatusOnline) {
                self.lastGreenString = [NSString mnz_lastGreenStringFromMinutes:lastGreen];
                [self customNavigationBarLabel];
            }
        }
    }
}

#pragma mark - MEGAChatRequest

- (void)onChatRequestFinish:(MEGAChatSdk *)api request:(MEGAChatRequest *)request error:(MEGAChatError *)error {
    if (error.type) return;
    
    switch (request.type) {
        case MEGAChatRequestTypeInviteToChatRoom: {
            switch (error.type) {
                case MEGAChatErrorTypeArgs: //If the chat is not a group chat (cannot invite peers)
                case MEGAChatErrorTypeAccess: //If the logged in user doesn't have privileges to invite peers.
                case MEGAChatErrorTypeNoEnt: //If there isn't any chat with the specified chatid.
                    self.stopInvitingContacts = YES;
                    [SVProgressHUD showErrorWithStatus:error.name];
                    break;
                    
                default:
                    if (error.type) {
                        [SVProgressHUD showErrorWithStatus:error.name];
                    }
                    break;
            }
            break;
        }
            
        case MEGAChatRequestTypeNodeMessage: {
            if (error.type) {
                [SVProgressHUD showErrorWithStatus:error.name];
                return;
            }
            break;
        }
            
        default:
            break;
    }
}

#pragma mark - MEGAChatCallDelegate

- (void)onChatCallUpdate:(MEGAChatSdk *)api call:(MEGAChatCall *)call {
    if (call.status == MEGAChatCallStatusDestroyed) {
        [self updateNavigationBarButtonsState];
    }
}

@end

//
//  SKStatefulTableViewController
//  SKStatefulTableViewController
//
//  Created by Shiki on 10/24/13.
//  Copyright (c) 2013 Shiki. All rights reserved.
//


#import "SKStatefulTableViewController.h"

typedef enum {
  SKStatefulTableViewControllerViewModeStatic = 1,
  SKStatefulTableViewControllerViewModeTable,
} SKStatefulTableViewControllerViewMode;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@interface SKStatefulTableViewController ()

@property (readwrite, strong, nonatomic) UITableView *tableView;
@property (readwrite, strong, nonatomic) UIView *staticContainerView;
@property (strong, nonatomic) UIRefreshControl *refreshControl;

@property (nonatomic) BOOL watchForLoadMore;
@property (nonatomic) BOOL loadMoreViewIsErrorView;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation SKStatefulTableViewController

- (id)init {
  if ((self = [super init]))
    [self onInit];
  return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
  if ((self = [super initWithCoder:aDecoder]))
    [self onInit];
  return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
    [self onInit];
  return self;
}

- (void)onInit {
  self.delegate = self;
  self.loadMoreTriggerThreshold = 64.f;
  self.canLoadMore = YES;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
  tableView.dataSource = self;
  tableView.delegate = self;
  tableView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleHeight;
  // Insert to make sure it is the first in the view heirarchy so we can benefit from the iOS7
  // auto-setting of content insets.
  [self.view insertSubview:tableView atIndex:0];
  self.tableView = tableView;

  // Add UIRefreshControl without the need for self to be a UITableViewController.
  // http://stackoverflow.com/questions/12497940/uirefreshcontrol-without-uitableviewcontroller
  UITableViewController *tableViewController = [[UITableViewController alloc] init];
  tableViewController.tableView = tableView;
  UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
  [refreshControl addTarget:self action:@selector(refreshControlValueChanged:)
           forControlEvents:UIControlEventValueChanged];
  tableViewController.refreshControl = refreshControl;
  self.refreshControl = refreshControl;

  UIView *staticContentView = [[UIView alloc] initWithFrame:self.view.bounds];
  staticContentView.backgroundColor = [UIColor whiteColor];
  staticContentView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleHeight;
  [tableView addSubview:staticContentView];
  self.staticContainerView = staticContentView;
}

- (void)setState:(SKStatefulTableViewControllerState)state {
  [self setState:state updateViewMode:YES];
}

- (void)setState:(SKStatefulTableViewControllerState)state updateViewMode:(BOOL)updateViewMode {
  _state = state;

  if (updateViewMode) {
    SKStatefulTableViewControllerViewMode viewMode;
    switch (state) {
      case SKStatefulTableViewControllerStateInitialLoading:
      case SKStatefulTableViewControllerStateEmptyOrInitialLoadError:
        viewMode = SKStatefulTableViewControllerViewModeStatic;
        break;
      default:
        viewMode = SKStatefulTableViewControllerViewModeTable;
        break;
    }

    [self setViewMode:viewMode];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Initial Load

- (void)triggerInitialLoad {
  if ([self stateIsLoading])
    return;

  UIView *initialLoadView = [self viewForInitialLoad];
  [self resetStaticContentViewWithChildView:initialLoadView];

  [self setState:SKStatefulTableViewControllerStateInitialLoading];

  __weak typeof(self) wSelf = self;
  if ([self.delegate respondsToSelector:@selector(statefulTableViewWillBeginInitialLoad:completion:)]) {
    [self.delegate statefulTableViewWillBeginInitialLoad:self completion:^(BOOL tableIsEmpty, NSError *errorOrNil) {
      [wSelf setHasFinishedInitialLoad:tableIsEmpty withError:errorOrNil];
    }];
  }
}

- (void)setHasFinishedInitialLoad:(BOOL)tableIsEmpty withError:(NSError *)errorOrNil {
  if (self.state != SKStatefulTableViewControllerStateInitialLoading)
    return;

  if (errorOrNil || tableIsEmpty) {
    UIView *view = [self viewForEmptyInitialLoadWithError:errorOrNil];
    [self resetStaticContentViewWithChildView:view];
    [self setState:SKStatefulTableViewControllerStateEmptyOrInitialLoadError];
    [self setWatchForLoadMoreIfApplicable:NO];
  } else {
    [self setState:SKStatefulTableViewControllerStateIdle];
    [self setWatchForLoadMoreIfApplicable:YES];
  }
}

- (UIView *)viewForInitialLoad {
  if ([self.delegate respondsToSelector:@selector(statefulTableViewViewForInitialLoad:)]) {
    return [self.delegate statefulTableViewViewForInitialLoad:self];
  } else {
    UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    activityIndicatorView.frame = ({
      CGRect f = activityIndicatorView.frame;
      f.origin.x = self.staticContainerView.frame.size.width * 0.5f - f.size.width * 0.5f;
      f.origin.y = self.staticContainerView.frame.size.height * 0.5f - f.size.height * 0.5f;
      f;
    });
    [activityIndicatorView startAnimating];
    return activityIndicatorView;
  }
}

- (UIView *)viewForEmptyInitialLoadWithError:(NSError *)errorOrNil {
  if ([self.delegate respondsToSelector:@selector(statefulTableView:viewForEmptyInitialLoadWithError:)]) {
    return [self.delegate statefulTableView:self viewForEmptyInitialLoadWithError:errorOrNil];
  } else {
    UIView *container = [[UIView alloc] initWithFrame:({
      CGRect f = CGRectMake(0.f, 0.f, self.staticContainerView.bounds.size.width, 120.f);
      f.origin.y = self.staticContainerView.bounds.size.height * 0.5f - f.size.height * 0.5f;
      f;
    })];

    UILabel *label = [[UILabel alloc] init];
    label.textAlignment = NSTextAlignmentCenter;
    label.text = errorOrNil ? errorOrNil.localizedDescription : @"No records found.";
    [label sizeToFit];
    label.frame = ({
      CGRect f = label.frame;
      f.origin.x = container.bounds.size.width * 0.5f - label.bounds.size.width * 0.5f;
      f;
    });

    [container addSubview:label];
    if (errorOrNil) {
      UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
      [button setTitle:@"Try Again" forState:UIControlStateNormal];
      [button addTarget:self action:@selector(triggerInitialLoad) forControlEvents:UIControlEventTouchUpInside];
      button.frame = ({
        CGRect f = CGRectMake(0.f, 0.f, 130.f, 32.f);
        f.origin.x = container.bounds.size.width * 0.5f - f.size.width * 0.5f;
        f.origin.y = label.frame.origin.y + label.frame.size.height + 10.f;
        f;
      });
      [container addSubview:button];
    }

    return container;
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Pull To Refresh

- (void)refreshControlValueChanged:(id)sender {
  if (![self triggerPullToRefresh]) {
    [self.refreshControl endRefreshing];
  }
}

- (BOOL)triggerPullToRefresh {
  if ([self stateIsLoading])
    return NO;

  // We don't want to change the view mode since pulling may come from the static view mode as well.
  [self setState:SKStatefulTableViewControllerStateLoadingFromPullToRefresh updateViewMode:NO];

  __weak typeof(self) wSelf = self;
  if ([self.delegate respondsToSelector:@selector(statefulTableViewWillBeginLoadingFromPullToRefresh:completion:)]) {
    [self.delegate statefulTableViewWillBeginLoadingFromPullToRefresh:self
                                                           completion:^(BOOL tableIsEmpty, NSError *errorOrNil) {
      [wSelf setHasFinishedLoadingFromPullToRefresh:tableIsEmpty withError:errorOrNil];
    }];
  }

  [self.refreshControl beginRefreshing];
  return YES;
}

- (void)setHasFinishedLoadingFromPullToRefresh:(BOOL)tableIsEmpty withError:(NSError *)errorOrNil {
  if (self.state != SKStatefulTableViewControllerStateLoadingFromPullToRefresh)
    return;

  [self.refreshControl endRefreshing];

  if (errorOrNil || tableIsEmpty) {
    UIView *view = [self viewForEmptyInitialLoadWithError:errorOrNil];
    [self resetStaticContentViewWithChildView:view];
    [self setState:SKStatefulTableViewControllerStateEmptyOrInitialLoadError];
    [self setWatchForLoadMoreIfApplicable:NO];
  } else {
    [self setState:SKStatefulTableViewControllerStateIdle];
    [self setWatchForLoadMoreIfApplicable:YES];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Load More

- (void)triggerLoadMore {
  if ([self stateIsLoading])
    return;

  self.loadMoreViewIsErrorView = NO;
  self.lastLoadMoreError = nil;
  [self updateLoadMoreView];

  [self setState:SKStatefulTableViewControllerStateLoadingMore];

  __weak typeof(self) wSelf = self;
  if ([self.delegate respondsToSelector:@selector(statefulTableViewWillBeginLoadingMore:completion:)]) {
    [self.delegate statefulTableViewWillBeginLoadingMore:self completion:^(BOOL canLoadMore,
      NSError *errorOrNil, BOOL showErrorView) {

      [wSelf setHasFinishedLoadingMore:canLoadMore withError:errorOrNil showErrorView:showErrorView];
    }];
  }
}

- (void)setWatchForLoadMoreIfApplicable:(BOOL)watch {
  // We will only watch if -canLoadMore is enabled
  if (watch && !self.canLoadMore)
    watch = NO;

  self.watchForLoadMore = watch;
  [self updateLoadMoreView];
  [self triggerLoadMoreIfApplicable:self.tableView];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  [self triggerLoadMoreIfApplicable:scrollView];
}

- (void)triggerLoadMoreIfApplicable:(UIScrollView *)scrollView {
  if (self.watchForLoadMore && !self.loadMoreViewIsErrorView) {
    CGFloat scrollPosition = scrollView.contentSize.height - scrollView.frame.size.height
      - scrollView.contentOffset.y;
    if (scrollPosition < self.loadMoreTriggerThreshold) {
      [self triggerLoadMore];
    }
  }
}

- (void)setHasFinishedLoadingMore:(BOOL)canLoadMore withError:(NSError *)errorOrNil
                    showErrorView:(BOOL)showErrorView {
  if (self.state != SKStatefulTableViewControllerStateLoadingMore)
    return;

  self.canLoadMore = canLoadMore;
  self.loadMoreViewIsErrorView = errorOrNil && showErrorView;
  self.lastLoadMoreError = errorOrNil;

  [self setState:SKStatefulTableViewControllerStateIdle];
  [self setWatchForLoadMoreIfApplicable:canLoadMore];
}

- (void)updateLoadMoreView {
  if (self.watchForLoadMore) {
    UIView *loadMoreView = [self viewForLoadingMoreWithError:self.loadMoreViewIsErrorView ? self.lastLoadMoreError : nil];
    loadMoreView.backgroundColor = self.lastLoadMoreError ? [UIColor.redColor colorWithAlphaComponent:0.5f] : UIColor.greenColor;
    self.tableView.tableFooterView = loadMoreView;
  } else {
    self.tableView.tableFooterView = nil;
  }
}

- (UIView *)viewForLoadingMoreWithError:(NSError *)error {
  if ([self.delegate respondsToSelector:@selector(statefulTableView:viewForLoadMoreWithError:)]) {
    return [self.delegate statefulTableView:self viewForLoadMoreWithError:error];
  } else {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f,
      self.tableView.bounds.size.width, 44.f)];
    if (error) {
      UILabel *label = [[UILabel alloc] init];
      label.text = error.localizedDescription;
      label.font = [label.font fontWithSize:12.f];
      label.frame = ({
        CGRect f = label.frame;
        f.size.height = container.bounds.size.height;
        f.origin.x = 10.f;
        f.size.width = container.bounds.size.width - 140.f;
        f;
      });
      [container addSubview:label];

      UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
      [button setTitle:@"Try Again" forState:UIControlStateNormal];
      [button addTarget:self action:@selector(triggerLoadMore) forControlEvents:UIControlEventTouchUpInside];
      button.frame = ({
        CGRect f = CGRectMake(0.f, 0.f, 130.f, container.bounds.size.height);
        f.origin.x = container.bounds.size.width - f.size.width - 5.f;
        f.origin.y = 0.f;
        f;
      });
      [container addSubview:button];
    } else {
      UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
      activityIndicatorView.frame = ({
        CGRect f = activityIndicatorView.frame;
        f.origin.x = container.frame.size.width * 0.5f - f.size.width * 0.5f;
        f.origin.y = container.frame.size.height * 0.5f - f.size.height * 0.5f;
        f;
      });
      [activityIndicatorView startAnimating];
      [container addSubview:activityIndicatorView];
    }
    return container;
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Utils

- (void)setViewMode:(SKStatefulTableViewControllerViewMode)mode {
  self.staticContainerView.hidden = mode == SKStatefulTableViewControllerViewModeTable;
  if (!self.staticContainerView.hidden) {
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  }
}

- (void)resetStaticContentViewWithChildView:(UIView *)childView {
  [self.staticContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
  [self.staticContainerView addSubview:childView];
}

- (BOOL)stateIsLoading {
  return self.state == SKStatefulTableViewControllerStateInitialLoading
    | self.state == SKStatefulTableViewControllerStateLoadingFromPullToRefresh
    | self.state == SKStatefulTableViewControllerStateLoadingMore;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  return nil;
}

@end
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

@property (nonatomic) BOOL loadMoreEnabled;

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

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Initial Load

- (void)setHasFinishedInitialLoad:(BOOL)tableIsEmpty withError:(NSError *)errorOrNil {
  if (self.state != SKStatefulTableViewControllerStateInitialLoading)
    return;

  if (errorOrNil || tableIsEmpty) {
    UIView *view = [self viewForEmptyInitialLoadWithError:errorOrNil];
    [self resetStaticContentViewWithChildView:view];
    [self setState:SKStatefulTableViewControllerStateEmptyOrInitialLoadError];
    [self setLoadMoreEnabled:NO];
  } else {
    [self setState:SKStatefulTableViewControllerStateIdle];
    [self setViewMode:SKStatefulTableViewControllerViewModeTable];
    [self setLoadMoreEnabled:YES];
  }
}

- (void)triggerInitialLoad {
  if ([self stateIsLoading])
    return;

  [self setState:SKStatefulTableViewControllerStateInitialLoading];

  __weak typeof(self) wSelf = self;
  if ([self.delegate respondsToSelector:@selector(statefulTableViewWillBeginInitialLoad:completion:)]) {
    [self.delegate statefulTableViewWillBeginInitialLoad:self completion:^(BOOL tableIsEmpty, NSError *errorOrNil) {
      [wSelf setHasFinishedInitialLoad:tableIsEmpty withError:errorOrNil];
    }];
  }

  UIView *initialLoadView = [self viewForInitialLoad];
  [self resetStaticContentViewWithChildView:initialLoadView];

  [self setViewMode:SKStatefulTableViewControllerViewModeStatic];
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
  [self triggerPullToRefresh];
}

- (void)triggerPullToRefresh {
  if ([self stateIsLoading])
    return;

  [self setState:SKStatefulTableViewControllerStateLoadingFromPullToRefresh];

  __weak typeof(self) wSelf = self;
  if ([self.delegate respondsToSelector:@selector(statefulTableViewWillBeginLoadingFromPullToRefresh:completion:)]) {
    [self.delegate statefulTableViewWillBeginLoadingFromPullToRefresh:self
                                                           completion:^(BOOL tableIsEmpty, NSError *errorOrNil) {
      [wSelf setHasFinishedLoadingFromPullToRefresh:tableIsEmpty withError:errorOrNil];
    }];
  }

  [self.refreshControl beginRefreshing];
}

- (void)setHasFinishedLoadingFromPullToRefresh:(BOOL)tableIsEmpty withError:(NSError *)errorOrNil {
  if (self.state != SKStatefulTableViewControllerStateLoadingFromPullToRefresh)
    return;

  [self.refreshControl endRefreshing];

  if (errorOrNil || tableIsEmpty) {
    UIView *view = [self viewForEmptyInitialLoadWithError:errorOrNil];
    [self resetStaticContentViewWithChildView:view];
    [self setState:SKStatefulTableViewControllerStateEmptyOrInitialLoadError];
    [self setViewMode:SKStatefulTableViewControllerViewModeStatic];
    [self setLoadMoreEnabled:NO];
  } else {
    [self setState:SKStatefulTableViewControllerStateIdle];
    [self setViewMode:SKStatefulTableViewControllerViewModeTable];
    [self setLoadMoreEnabled:YES];
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Load More

- (void)triggerLoadMore {
  if ([self stateIsLoading])
    return;

  [self setState:SKStatefulTableViewControllerStateLoadingMore];

  __weak typeof(self) wSelf = self;
  if ([self.delegate respondsToSelector:@selector(statefulTableViewWillBeginLoadingMore:completion:)]) {
    [self.delegate statefulTableViewWillBeginLoadingMore:self completion:^(BOOL canLoadMore, NSError *errorOrNil) {
      [wSelf setHasFinishedLoadingMore:canLoadMore withError:errorOrNil];
    }];
  }
}

- (void)setLoadMoreEnabled:(BOOL)enabled {
  _loadMoreEnabled = enabled;

  if (enabled) {
    if (!self.tableView.tableFooterView) {
      UIView *loadMoreView = [self viewForLoadingMoreWithError:nil];
      loadMoreView.backgroundColor = UIColor.greenColor;
      self.tableView.tableFooterView = loadMoreView;
    }
    [self triggerLoadMoreIfApplicable:self.tableView];
  } else {
    self.tableView.tableFooterView = nil;
  }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  [self triggerLoadMoreIfApplicable:scrollView];
}

- (void)triggerLoadMoreIfApplicable:(UIScrollView *)scrollView {
  if (self.loadMoreEnabled) {
    CGFloat scrollPosition = scrollView.contentSize.height - scrollView.frame.size.height - scrollView.contentOffset.y;
    if (scrollPosition < self.loadMoreTriggerThreshold) {
      [self triggerLoadMore];
    }
  }
}

- (void)setHasFinishedLoadingMore:(BOOL)canLoadMore withError:(NSError *)errorOrNil {
  if (self.state != SKStatefulTableViewControllerStateLoadingMore)
    return;

  // TODO separate view for load-more with error
  [self setState:SKStatefulTableViewControllerStateIdle];
  [self setViewMode:SKStatefulTableViewControllerViewModeTable];
  [self setLoadMoreEnabled:canLoadMore];
}

- (UIView *)viewForLoadingMoreWithError:(NSError *)error {
  if ([self.delegate respondsToSelector:@selector(statefulTableView:viewForLoadMoreWithError:)]) {
    return [self.delegate statefulTableView:self viewForLoadMoreWithError:error];
  } else {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f,
      self.tableView.bounds.size.width, 44.f)];
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

@end
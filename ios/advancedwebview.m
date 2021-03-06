/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "Advancedwebview.h"

#import <UIKit/UIKit.h>

#import <React/RCTAutoInsetsProtocol.h>
#import <React/RCTConvert.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/RCTView.h>
#import <React/UIView+React.h>
#import <AFNetworking/AFURLSessionManager.h>
#import "CBStoreHouseRefreshControl.h"

//NSString *const RCTJSNavigationScheme2 = @"react-js-navigation";

static NSString *const kPostMessageHost = @"postMessage";

@interface Advancedwebview () <UIWebViewDelegate,UIScrollViewDelegate, RCTAutoInsetsProtocol>

@property (nonatomic, copy) RCTDirectEventBlock onLoadingStart;
@property (nonatomic, copy) RCTDirectEventBlock onLoadingFinish;
@property (nonatomic, copy) RCTDirectEventBlock onLoadingError;
@property (nonatomic, copy) RCTDirectEventBlock onShouldStartLoadWithRequest;
@property (nonatomic, copy) RCTDirectEventBlock onMessage;
//custom properties
@property (nonatomic, copy) RCTDirectEventBlock onImageDownloadComplete;
@property (nonatomic, copy) RCTDirectEventBlock onImageDownload;
@property (nonatomic) NSString *fileuri;
//custom properties - end

@end

@implementation Advancedwebview
{
  UIWebView *_webView;
  NSString *_injectedJavaScript;
  CBStoreHouseRefreshControl *_refreshControl;
}

- (void)dealloc
{
  _webView.delegate = nil;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    super.backgroundColor = [UIColor clearColor];
    _automaticallyAdjustContentInsets = YES;
    _contentInset = UIEdgeInsetsZero;
    _webView = [[UIWebView alloc] initWithFrame:self.bounds];
    _webView.delegate = self;
    _webView.scrollView.delegate = self;
    [self addSubview:_webView];
  }
  return self;
}

RCT_NOT_IMPLEMENTED(- (instancetype)initWithCoder:(NSCoder *)aDecoder)

- (void)goForward
{
  [_webView goForward];
}

- (void)goBack
{
  [_webView goBack];
}

- (void)reload
{
  NSURLRequest *request = [RCTConvert NSURLRequest:self.source];
  if (request.URL && !_webView.request.URL.absoluteString.length) {
    [_webView loadRequest:request];
  }
  else {
    [_webView reload];
  }
}

- (void)stopLoading
{
  [_webView stopLoading];
}

- (void)postMessage:(NSString *)message
{
  NSDictionary *eventInitDict = @{
                                  @"data": message,
                                  };
  NSString *source = [NSString
                      stringWithFormat:@"document.dispatchEvent(new MessageEvent('message', %@));",
                      RCTJSONStringify(eventInitDict, NULL)
                      ];
  [_webView stringByEvaluatingJavaScriptFromString:source];
}

- (void)injectJavaScript:(NSString *)script
{
  [_webView stringByEvaluatingJavaScriptFromString:script];
}

- (void)setSource:(NSDictionary *)source
{
  if (![_source isEqualToDictionary:source]) {
    _source = [source copy];
    
    // Check for a static html source first
    NSString *html = [RCTConvert NSString:source[@"html"]];
    if (html) {
      NSURL *baseURL = [RCTConvert NSURL:source[@"baseUrl"]];
      if (!baseURL) {
        baseURL = [NSURL URLWithString:@"about:blank"];
      }
      [_webView loadHTMLString:html baseURL:baseURL];
      return;
    }
    
    NSURLRequest *request = [RCTConvert NSURLRequest:source];
    // Because of the way React works, as pages redirect, we actually end up
    // passing the redirect urls back here, so we ignore them if trying to load
    // the same url. We'll expose a call to 'reload' to allow a user to load
    // the existing page.
    if ([request.URL isEqual:_webView.request.URL]) {
      return;
    }
    if (!request.URL) {
      // Clear the webview
      [_webView loadHTMLString:@"" baseURL:nil];
      return;
    }
    [_webView loadRequest:request];
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _webView.frame = self.bounds;
}

- (void)setContentInset:(UIEdgeInsets)contentInset
{
  _contentInset = contentInset;
  [RCTView autoAdjustInsetsForView:self
                    withScrollView:_webView.scrollView
                      updateOffset:NO];
}

- (void)setScalesPageToFit:(BOOL)scalesPageToFit
{
  if (_webView.scalesPageToFit != scalesPageToFit) {
    _webView.scalesPageToFit = scalesPageToFit;
    [_webView reload];
  }
}

- (BOOL)scalesPageToFit
{
  return _webView.scalesPageToFit;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
  CGFloat alpha = CGColorGetAlpha(backgroundColor.CGColor);
  self.opaque = _webView.opaque = (alpha == 1.0);
  _webView.backgroundColor = backgroundColor;
}

- (UIColor *)backgroundColor
{
  return _webView.backgroundColor;
}

- (NSMutableDictionary<NSString *, id> *)baseEvent
{
  NSMutableDictionary<NSString *, id> *event = [[NSMutableDictionary alloc] initWithDictionary:@{
                                                                                                 @"url": _webView.request.URL.absoluteString ?: @"",
                                                                                                 @"loading" : @(_webView.loading),
                                                                                                 @"title": [_webView stringByEvaluatingJavaScriptFromString:@"document.title"],
                                                                                                 @"canGoBack": @(_webView.canGoBack),
                                                                                                 @"canGoForward" : @(_webView.canGoForward),
                                                                                                 }];
  
  return event;
}

- (void)refreshContentInset
{
  [RCTView autoAdjustInsetsForView:self
                    withScrollView:_webView.scrollView
                      updateOffset:YES];
}

#pragma mark - UIWebViewDelegate methods

- (BOOL)webView:(__unused UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType
{
  BOOL isJSNavigation = [request.URL.scheme isEqualToString:RCTJSNavigationScheme];
  
  static NSDictionary<NSNumber *, NSString *> *navigationTypes;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    navigationTypes = @{
                        @(UIWebViewNavigationTypeLinkClicked): @"click",
                        @(UIWebViewNavigationTypeFormSubmitted): @"formsubmit",
                        @(UIWebViewNavigationTypeBackForward): @"backforward",
                        @(UIWebViewNavigationTypeReload): @"reload",
                        @(UIWebViewNavigationTypeFormResubmitted): @"formresubmit",
                        @(UIWebViewNavigationTypeOther): @"other",
                        };
  });
  
  // skip this for the JS Navigation handler
  if (!isJSNavigation && _onShouldStartLoadWithRequest) {
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary: @{
                                       @"url": (request.URL).absoluteString,
                                       @"navigationType": navigationTypes[@(navigationType)]
                                       }];
    if (![self.delegate webView:self
      shouldStartLoadForRequest:event
                   withCallback:_onShouldStartLoadWithRequest]) {
      return NO;
    }
  }
  
  if (_onLoadingStart) {
    // We have this check to filter out iframe requests and whatnot
    BOOL isTopFrame = [request.URL isEqual:request.mainDocumentURL];
    if (isTopFrame) {
      NSMutableDictionary<NSString *, id> *event = [self baseEvent];
      [event addEntriesFromDictionary: @{
                                         @"url": (request.URL).absoluteString,
                                         @"navigationType": navigationTypes[@(navigationType)]
                                         }];
      _onLoadingStart(event);
    }
  }
  
  if (isJSNavigation && [request.URL.host isEqualToString:kPostMessageHost]) {
    NSString *data = request.URL.query;
    data = [data stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    data = [data stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary: @{
                                       @"data": data,
                                       }];
    
    NSString *source = @"document.dispatchEvent(new MessageEvent('message:received'));";
    
    [_webView stringByEvaluatingJavaScriptFromString:source];
    
    _onMessage(event);
  }
  //custom code - image download
  if(navigationType == UIWebViewNavigationTypeLinkClicked) {
    
    if (_onImageDownload) {
      // We have this check to filter out iframe requests and whatnot
      
      NSMutableDictionary<NSString *, id> *event = [[NSMutableDictionary alloc] initWithDictionary:@{
                                                                                                     @"error": @false
                                                                                                     }];
      _onImageDownload(event);
    }
    
    
    NSURL *requestedURL = [request URL];
    //Download image
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    
    NSURL *URL = requestedURL;//[NSURL URLWithString:@"http://example.com/download.zip"];
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    
    NSURLSessionDownloadTask *downloadTask = [manager downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
      NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
      return [documentsDirectoryURL URLByAppendingPathComponent:[response suggestedFilename]];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
      _fileuri = filePath;
      UIImage *image = [UIImage imageWithContentsOfFile:[filePath path]];
      
      UIImageWriteToSavedPhotosAlbum(image,
                                     self, // send the message to 'self' when calling the callback
                                     @selector(thisImage:hasBeenSavedInPhotoAlbum:usingContextInfo:), // the selector to tell the method to call on completion
                                     nil);
      
    }];
    [downloadTask resume];
    
    return false;
  }
  //custom code - end
  
  // JS Navigation handler
  return !isJSNavigation;
}

- (void)webView:(__unused UIWebView *)webView didFailLoadWithError:(NSError *)error
{
  if (_onLoadingError) {
    
    if(_pullToRefresh && _refreshControl){
      [_refreshControl finishingLoading];
    }
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
      // NSURLErrorCancelled is reported when a page has a redirect OR if you load
      // a new URL in the WebView before the previous one came back. We can just
      // ignore these since they aren't real errors.
      // http://stackoverflow.com/questions/1024748/how-do-i-fix-nsurlerrordomain-error-999-in-iphone-3-0-os
      return;
    }
    
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) {
      // Error code 102 "Frame load interrupted" is raised by the UIWebView if
      // its delegate returns FALSE from webView:shouldStartLoadWithRequest:navigationType
      // when the URL is from an http redirect. This is a common pattern when
      // implementing OAuth with a WebView.
      return;
    }
    
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    [event addEntriesFromDictionary:@{
                                      @"domain": error.domain,
                                      @"code": @(error.code),
                                      @"description": error.localizedDescription,
                                      }];
    _onLoadingError(event);
  }
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
  if (_messagingEnabled) {
#if RCT_DEV
    // See isNative in lodash
    NSString *testPostMessageNative = @"String(window.postMessage) === String(Object.hasOwnProperty).replace('hasOwnProperty', 'postMessage')";
    BOOL postMessageIsNative = [
                                [webView stringByEvaluatingJavaScriptFromString:testPostMessageNative]
                                isEqualToString:@"true"
                                ];
    if (!postMessageIsNative) {
      RCTLogError(@"Setting onMessage on a WebView overrides existing values of window.postMessage, but a previous value was defined");
    }
#endif
    NSString *source = [NSString stringWithFormat:
                        @"(function() {"
                        "window.originalPostMessage = window.postMessage;"
                        
                        "var messageQueue = [];"
                        "var messagePending = false;"
                        
                        "function processQueue() {"
                        "if (!messageQueue.length || messagePending) return;"
                        "messagePending = true;"
                        "window.location = '%@://%@?' + encodeURIComponent(messageQueue.shift());"
                        "}"
                        
                        "window.postMessage = function(data) {"
                        "messageQueue.push(String(data));"
                        "processQueue();"
                        "};"
                        
                        "document.addEventListener('message:received', function(e) {"
                        "messagePending = false;"
                        "processQueue();"
                        "});"
                        "})();", RCTJSNavigationScheme, kPostMessageHost
                        ];
    [webView stringByEvaluatingJavaScriptFromString:source];
  }
  if (_injectedJavaScript != nil) {
    NSString *jsEvaluationValue = [webView stringByEvaluatingJavaScriptFromString:_injectedJavaScript];
    
    NSMutableDictionary<NSString *, id> *event = [self baseEvent];
    event[@"jsEvaluationValue"] = jsEvaluationValue;
    
    _onLoadingFinish(event);
  }
  // we only need the final 'finishLoad' call so only fire the event when we're actually done loading.
  else if (_onLoadingFinish && !webView.loading && ![webView.request.URL.absoluteString isEqualToString:@"about:blank"]) {
    _onLoadingFinish([self baseEvent]);
    
   /* UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    [_webView.scrollView addSubview:refreshControl];*/
    if(_pullToRefresh){
      if(!_refreshControl){
      _refreshControl = [CBStoreHouseRefreshControl attachToScrollView:_webView.scrollView target:self refreshAction:@selector(handleRefresh:) plist:@"refresh" color:[UIColor blackColor] lineWidth:1.5 dropHeight:120 scale:1 horizontalRandomness:150 reverseLoadingAnimation:NO internalAnimationFactor:0.7];
      [_webView.scrollView addSubview:_refreshControl];
      }else{
        [_refreshControl finishingLoading];
      }
    }
  }
}

//Custom code - helper method for image download
- (void)thisImage:(UIImage *)image hasBeenSavedInPhotoAlbum:(NSError *)error usingContextInfo:(void*)ctxInfo {
  if(_fileuri != nil){
    [[NSFileManager defaultManager] removeItemAtPath:_fileuri error:&error];
    _fileuri = nil;
  }
  if (error) {
    if (_onImageDownloadComplete) {
      // We have this check to filter out iframe requests and whatnot
      
      NSMutableDictionary<NSString *, id> *event = [[NSMutableDictionary alloc] initWithDictionary:@{
                                                                                                     @"error": @true,
                                                                                                     @"path" : @""
                                                                                                     }];
      _onImageDownloadComplete(event);
    }
  } else {
    if (_onImageDownloadComplete) {
      // We have this check to filter out iframe requests and whatnot
      
      NSMutableDictionary<NSString *, id> *event = [[NSMutableDictionary alloc] initWithDictionary:@{
                                                                                                     @"error": @false,
                                                                                                     @"path" : @""
                                                                                                     }];
      _onImageDownloadComplete(event);
    }
  }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
  if(_refreshControl && _refreshControl.state != 1){
    [_refreshControl scrollViewDidScroll];
  }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
  if(_refreshControl && _refreshControl.state != 1){
    [_refreshControl scrollViewDidEndDragging];
  }
}
//Custom code - end

//Handle pull to refresh
-(void)handleRefresh:(CBStoreHouseRefreshControl *)refresh {
    [_webView reload];
  
}

@end


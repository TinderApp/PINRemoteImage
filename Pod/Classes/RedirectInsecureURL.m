//
//  Created by Hemanth Prasad on 4/16/18.
//  Copyright © 2018 ___ORGANIZATIONNAME___. All rights reserved.
//

#import "RedirectInsecureURL.h"

@interface RedirectInsecureURL()

@property (class, nonatomic, readonly) NSString *httpPrefix;
@property (class, nonatomic, readonly) NSString *httpsPrefix;
@property (class, nonatomic, readonly) NSURLSession *urlSession;
@property (nonatomic) NSURLSessionDataTask *dataTask;

@end

@implementation RedirectInsecureURL

+ (NSString *)httpPrefix {
    return @"http://images.gotinder.com/";
}

+ (NSString *)httpsPrefix
{
    return @"https://images-ssl.gotinder.com/";
}

static NSURLSession *_urlSession;

+ (NSURLSession *)urlSession
{
    if (!_urlSession) {
        _urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    }
    return _urlSession;
}

+ (NSString *)didDetectHTTPImageURLNotification {
    return @"didDetectHTTPImageURLNotification";
}

+ (void)didDetectHTTPImageURL
{
    [[NSNotificationCenter defaultCenter] postNotificationName:[self didDetectHTTPImageURLNotification] object:nil];
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    if ([[request.URL absoluteString] hasPrefix:self.httpPrefix]) {
        [self didDetectHTTPImageURL];
        return YES;
    }
    
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (NSURLRequest *)modifiedRequest
{
    NSString *url = [self.request.URL absoluteString];
    NSMutableURLRequest *modifiedRequest = [self.request mutableCopy];
    modifiedRequest.URL = [NSURL URLWithString:[url stringByReplacingOccurrencesOfString:RedirectInsecureURL.httpPrefix withString:RedirectInsecureURL.httpsPrefix]];
    return modifiedRequest;
}

- (void)startLoading
{
    __weak __typeof__(self) weakSelf = self;
    self.dataTask = [RedirectInsecureURL.urlSession dataTaskWithRequest:[self modifiedRequest]
                                                       completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                                           [weakSelf notifyWithData:data response:response error:error];
                                                       }];
    [self.dataTask resume];
}

- (void)stopLoading
{
    [self.dataTask cancel];
    self.dataTask = nil;
}

- (void)notifyWithData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error
{
    if (self.client == nil) {
        return;
    }
    
    if (data != nil) {
        [self.client URLProtocol:self didLoadData:data];
    }
    
    if (response != nil) {
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    }
    
    if (error != nil) {
        [self.client URLProtocol:self didFailWithError:error];
    }
    
    [self.client URLProtocolDidFinishLoading:self];
}

@end

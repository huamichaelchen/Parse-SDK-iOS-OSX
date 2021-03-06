/**
 * Copyright (c) 2015-present, Parse, LLC.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <OCMock/OCMock.h>

#import <Bolts/BFCancellationTokenSource.h>
#import <Bolts/BFTask.h>

#import "PFCommandResult.h"
#import "PFMacros.h"
#import "PFRESTCommand.h"
#import "PFTestCase.h"
#import "PFURLSession.h"
#import "PFURLSession_Private.h"

// NOTE: NSURLSessionTasks do some *weird* runtime hackery which causes the taskIdentifier property to not
// *actually* exist. This means OCMock cannot stub it. Let's make our own subclass that forces this to work. Note that
// We do not inherit from NSURLSessionTask, as we want this to be as close to a 'strict' mock as possible.
@interface MockedSessionTask : NSObject

@property (atomic, assign) NSUInteger taskIdentifier;

@property (nonatomic, strong) void (^resumeBlock)();
@property (nonatomic, strong) void (^cancelBlock)();

@end

@implementation MockedSessionTask

@synthesize taskIdentifier;

- (void)resume {
    if (self.resumeBlock) {
        self.resumeBlock();
    } else {
        [NSException raise:NSInternalInconsistencyException format:@"Resume block not set!"];
    }
}

- (void)cancel {
    if (self.cancelBlock) {
        self.cancelBlock();
    } else {
        [NSException raise:NSInternalInconsistencyException format:@"Cancel block not set!"];
    }
}

@end

@interface URLSessionTests : PFTestCase

@end

@implementation URLSessionTests

- (void)testConstructors {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *URLSession = [NSURLSession sharedSession];

    PFURLSession *session = [[PFURLSession alloc] initWithConfiguration:configuration];
    XCTAssertNotNil(session);
    [session invalidateAndCancel];

    session = [PFURLSession sessionWithConfiguration:configuration];
    XCTAssertNotNil(session);
    [session invalidateAndCancel];

    session = [[PFURLSession alloc] initWithURLSession:URLSession];
    XCTAssertNotNil(URLSession);

    session = [PFURLSession sessionWithURLSession:URLSession];
    XCTAssertNotNil(session);

    PFAssertThrowsInconsistencyException([PFURLSession new]);
}

- (void)testPerformDataRequestSuccess {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    MockedSessionTask *mockedDataTask = [[MockedSessionTask alloc] init];

    __block id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate> sessionDelegate = nil;

    OCMExpect([mockedURLSession dataTaskWithRequest:mockedURLRequest]).andReturn(mockedDataTask);

    mockedDataTask.taskIdentifier = 1337;

    @weakify(mockedDataTask);
    mockedDataTask.resumeBlock = ^{
        @strongify(mockedDataTask);

        NSData *dataRecieved = [@"{ \"foo\": \"bar\" }" dataUsingEncoding:NSUTF8StringEncoding];
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://foo.bar"]
                                                            MIMEType:@"application/json"
                                               expectedContentLength:dataRecieved.length
                                                    textEncodingName:@"UTF-8"];

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedDataTask
                 didReceiveResponse:response
                  completionHandler:^(NSURLSessionResponseDisposition disposition) {
                      XCTAssertEqual(disposition, NSURLSessionResponseAllow);
                  }];
        [sessionDelegate URLSession:mockedURLSession dataTask:(id)mockedDataTask didReceiveData:dataRecieved];

        [sessionDelegate URLSession:mockedURLSession task:(id)mockedDataTask didCompleteWithError:nil];
    };

    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];
    sessionDelegate = (id)session;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [[session performDataURLRequestAsync:mockedURLRequest forCommand:mockedCommand cancellationToken:nil] continueWithBlock:^id(BFTask *task) {
        PFCommandResult *actualResult = task.result;
        XCTAssertEqualObjects(actualResult.result, (@{ @"foo" : @"bar" }));
        [expectation fulfill];
        return nil;
    }];
    [self waitForTestExpectations];

    OCMVerifyAll((id)mockedURLSession);
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}

- (void)testPerformDataRequesPreCancel {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    BFCancellationTokenSource *cancellationTokenSource = [BFCancellationTokenSource cancellationTokenSource];
    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];

    [cancellationTokenSource cancel];
    [[session performDataURLRequestAsync:mockedURLRequest
                              forCommand:mockedCommand
                       cancellationToken:cancellationTokenSource.token] continueWithBlock:^id(BFTask *task) {
        XCTAssertTrue(task.cancelled);
        [expectation fulfill];
        return nil;
    }];
    [self waitForTestExpectations];
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}


- (void)testPerformDataRequestCancellation {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    MockedSessionTask *mockedDataTask = [[MockedSessionTask alloc] init];

    BFCancellationTokenSource *cancellationTokenSource = [BFCancellationTokenSource cancellationTokenSource];
    __block id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate> sessionDelegate = nil;

    OCMExpect([mockedURLSession dataTaskWithRequest:mockedURLRequest]).andReturn(mockedDataTask);

    mockedDataTask.taskIdentifier = 1337;

    @weakify(mockedDataTask);
    mockedDataTask.resumeBlock = ^{
        @strongify(mockedDataTask);

        NSData *dataRecieved = [@"{ \"foo\": \"bar\" }" dataUsingEncoding:NSUTF8StringEncoding];
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://foo.bar"]
                                                            MIMEType:@"application/json"
                                               expectedContentLength:dataRecieved.length
                                                    textEncodingName:@"UTF-8"];

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedDataTask
                 didReceiveResponse:response
                  completionHandler:^(NSURLSessionResponseDisposition disposition) {
                      XCTAssertEqual(disposition, NSURLSessionResponseAllow);
                  }];
        [sessionDelegate URLSession:mockedURLSession dataTask:(id)mockedDataTask didReceiveData:dataRecieved];
        [cancellationTokenSource cancel];

        [sessionDelegate URLSession:mockedURLSession
                               task:(id)mockedDataTask
               didCompleteWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
    };

    XCTestExpectation *cancelExpectation = [self expectationWithDescription:@"cancel"];
    mockedDataTask.cancelBlock = ^{
        [cancelExpectation fulfill];
    };

    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];
    sessionDelegate = (id)session;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [[session performDataURLRequestAsync:mockedURLRequest
                              forCommand:mockedCommand
                       cancellationToken:cancellationTokenSource.token] continueWithBlock:^id(BFTask *task) {
        XCTAssertTrue(task.cancelled);
        [expectation fulfill];
        return nil;
    }];
    [self waitForTestExpectations];

    OCMVerifyAll((id)mockedURLSession);
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}

- (void)testPerformDataRequestError {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    MockedSessionTask *mockedDataTask = [[MockedSessionTask alloc] init];

    NSError *expectedError = [NSError errorWithDomain:PFParseErrorDomain code:1337 userInfo:nil];
    __block id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate> sessionDelegate = nil;

    OCMExpect([mockedURLSession dataTaskWithRequest:mockedURLRequest]).andReturn(mockedDataTask);

    mockedDataTask.taskIdentifier = 1337;

    @weakify(mockedDataTask);
    mockedDataTask.resumeBlock = ^{
        @strongify(mockedDataTask);
        [sessionDelegate URLSession:mockedURLSession task:(id)mockedDataTask didCompleteWithError:expectedError];
    };

    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];
    sessionDelegate = (id)session;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [[session performDataURLRequestAsync:mockedURLRequest forCommand:mockedCommand cancellationToken:nil]
     continueWithBlock:^id(BFTask *task) {
         XCTAssertEqualObjects(expectedError, task.error.userInfo[@"originalError"]);
         [expectation fulfill];
         return nil;
     }];
    [self waitForTestExpectations];

    OCMVerifyAll((id)mockedURLSession);
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}

- (void)testFileUploadRequestPreCancel {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    BFCancellationTokenSource *cancellationTokenSource = [BFCancellationTokenSource cancellationTokenSource];
    NSString *exampleFile = @"file.txt";

    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [cancellationTokenSource cancel];
    [[session performFileUploadURLRequestAsync:mockedURLRequest
                                    forCommand:mockedCommand
                     withContentSourceFilePath:exampleFile
                             cancellationToken:cancellationTokenSource.token
                                 progressBlock:^(int percentDone) {
                                     XCTFail();
                                 }]
     continueWithBlock:^id(BFTask *task) {
         XCTAssertTrue(task.cancelled);
         [expectation fulfill];
         return nil;
     }];
    [self waitForTestExpectations];
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}

- (void)testFileUploadSuccess {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    MockedSessionTask *mockedUploadTask = [[MockedSessionTask alloc] init];

    NSString *exampleFile = @"file.txt";
    __block id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate> sessionDelegate = nil;

    OCMExpect([mockedURLSession uploadTaskWithRequest:mockedURLRequest fromFile:[NSURL fileURLWithPath:exampleFile]]).andReturn(mockedUploadTask);

    mockedUploadTask.taskIdentifier = 1337;

    @weakify(mockedUploadTask);
    mockedUploadTask.resumeBlock = ^{
        @strongify(mockedUploadTask);
        NSData *dataToSend = [@"{ \"foo\": \"bar\" }" dataUsingEncoding:NSUTF8StringEncoding];
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://foo.bar"]
                                                            MIMEType:@"application/json"
                                               expectedContentLength:dataToSend.length
                                                    textEncodingName:@"UTF-8"];

        for (NSUInteger progress = 0; progress < dataToSend.length; progress++) {
            [sessionDelegate URLSession:mockedURLSession
                                   task:(id)mockedUploadTask
                        didSendBodyData:1
                         totalBytesSent:progress
               totalBytesExpectedToSend:dataToSend.length];
        }

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedUploadTask
                 didReceiveResponse:response
                  completionHandler:^(NSURLSessionResponseDisposition disposition) {
                      XCTAssertEqual(disposition, NSURLSessionResponseAllow);
                  }];

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedUploadTask
                     didReceiveData:dataToSend];

        [sessionDelegate URLSession:mockedURLSession
                               task:(id)mockedUploadTask
               didCompleteWithError:nil];
    };

    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];
    sessionDelegate = (id)session;

    __block int lastProgress = 0;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [[session performFileUploadURLRequestAsync:mockedURLRequest
                                    forCommand:mockedCommand
                     withContentSourceFilePath:exampleFile
                             cancellationToken:nil
                                 progressBlock:^(int percentDone) {
                                     XCTAssertGreaterThanOrEqual(percentDone, lastProgress);
                                     lastProgress = percentDone;
                                 }]
     continueWithBlock:^id(BFTask *task) {
         PFCommandResult *actualResult = task.result;
         XCTAssertEqualObjects(actualResult.result, (@{ @"foo" : @"bar" }));
         [expectation fulfill];
         return nil;
     }];
    [self waitForTestExpectations];

    OCMVerifyAll((id)mockedURLSession);
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}


- (void)testFileUploadRequestCancellation {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    MockedSessionTask *mockedUploadTask = [[MockedSessionTask alloc] init];

    BFCancellationTokenSource *cancellationTokenSource = [BFCancellationTokenSource cancellationTokenSource];
    NSString *exampleFile = @"file.txt";
    __block id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate> sessionDelegate = nil;

    OCMExpect([mockedURLSession uploadTaskWithRequest:mockedURLRequest fromFile:[NSURL fileURLWithPath:exampleFile]]).andReturn(mockedUploadTask);

    mockedUploadTask.taskIdentifier = 1337;

    @weakify(mockedUploadTask);
    mockedUploadTask.resumeBlock = ^{
        @strongify(mockedUploadTask);

        NSData *dataToSend = [@"{ \"foo\": \"bar\" }" dataUsingEncoding:NSUTF8StringEncoding];
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://foo.bar"]
                                                            MIMEType:@"application/json"
                                               expectedContentLength:dataToSend.length
                                                    textEncodingName:@"UTF-8"];

        for (NSUInteger progress = 0; progress < dataToSend.length; progress++) {
            [sessionDelegate URLSession:mockedURLSession
                                   task:(id)mockedUploadTask
                        didSendBodyData:1
                         totalBytesSent:progress
               totalBytesExpectedToSend:dataToSend.length];
        }

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedUploadTask
                 didReceiveResponse:response
                  completionHandler:^(NSURLSessionResponseDisposition disposition) {
                      XCTAssertEqual(disposition, NSURLSessionResponseAllow);
                  }];

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedUploadTask
                     didReceiveData:dataToSend];

        [cancellationTokenSource cancel];

        [sessionDelegate URLSession:mockedURLSession
                               task:(id)mockedUploadTask
               didCompleteWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
    };

    XCTestExpectation *cancelExpectation = [self expectationWithDescription:@"cancel"];
    mockedUploadTask.cancelBlock = ^{
        [cancelExpectation fulfill];
    };

    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];
    sessionDelegate = (id)session;

    __block int lastProgress = 0;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [[session performFileUploadURLRequestAsync:mockedURLRequest
                                    forCommand:mockedCommand
                     withContentSourceFilePath:exampleFile
                             cancellationToken:cancellationTokenSource.token
                                 progressBlock:^(int percentDone) {
                                     XCTAssertGreaterThanOrEqual(percentDone, lastProgress);
                                     lastProgress = percentDone;
                                 }]
     continueWithBlock:^id(BFTask *task) {
         XCTAssertTrue(task.cancelled);
         [expectation fulfill];
         return nil;
     }];
    [self waitForTestExpectations];

    OCMVerifyAll((id)mockedURLSession);
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}

- (void)testCaching {
    NSURLSession *mockedURLSession = PFStrictClassMock([NSURLSession class]);
    NSURLRequest *mockedURLRequest = PFStrictClassMock([NSURLRequest class]);
    PFRESTCommand *mockedCommand = PFStrictClassMock([PFRESTCommand class]);
    NSArray *mocks = @[ mockedURLSession, mockedURLRequest, mockedCommand ];

    MockedSessionTask *mockedDataTask = [[MockedSessionTask alloc] init];

    __block id<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate> sessionDelegate = nil;

    OCMStub([mockedURLSession dataTaskWithRequest:mockedURLRequest]).andReturn(mockedDataTask);

    mockedDataTask.taskIdentifier = 1337;
    @weakify(mockedDataTask);
    mockedDataTask.resumeBlock = ^{
        @strongify(mockedDataTask);
        NSData *dataRecieved = [@"{ \"foo\": \"bar\" }" dataUsingEncoding:NSUTF8StringEncoding];
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://foo.bar"]
                                                            MIMEType:@"application/json"
                                               expectedContentLength:dataRecieved.length
                                                    textEncodingName:@"UTF-8"];

        NSCachedURLResponse *cachedResponse =
        [[NSCachedURLResponse alloc] initWithResponse:response data:dataRecieved];

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedDataTask
                 didReceiveResponse:response
                  completionHandler:^(NSURLSessionResponseDisposition disposition) {
                      XCTAssertEqual(disposition, NSURLSessionResponseAllow);
                  }];
        [sessionDelegate URLSession:mockedURLSession dataTask:(id)mockedDataTask didReceiveData:dataRecieved];
        [sessionDelegate URLSession:mockedURLSession task:(id)mockedDataTask didCompleteWithError:nil];

        [sessionDelegate URLSession:mockedURLSession
                           dataTask:(id)mockedDataTask
                  willCacheResponse:cachedResponse
                  completionHandler:^(NSCachedURLResponse *cached) { XCTAssertNil(cached); }];
    };

    PFURLSession *session = [PFURLSession sessionWithURLSession:mockedURLSession];
    sessionDelegate = (id)session;

    XCTestExpectation *expectation = [self currentSelectorTestExpectation];
    [[session performDataURLRequestAsync:mockedURLRequest forCommand:mockedCommand cancellationToken:nil]
     continueWithBlock:^id(BFTask *task) {
         XCTAssertFalse(task.faulted);
         [expectation fulfill];
         return nil;
     }];
    [self waitForTestExpectations];

    OCMVerifyAll((id)mockedURLSession);
    [mocks makeObjectsPerformSelector:@selector(stopMocking)];
}

- (void)testInvalidate {
    PFURLSession *session = [PFURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    XCTAssertNoThrow([session invalidateAndCancel]); // lol?
}

@end

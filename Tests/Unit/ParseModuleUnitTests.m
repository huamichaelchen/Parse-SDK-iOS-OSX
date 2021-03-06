/**
 * Copyright (c) 2015-present, Parse, LLC.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "PFTestCase.h"
#import "ParseInternal.h"

@interface ParseTestModule : NSObject <ParseModule>

@property (nonatomic, assign) BOOL didInitializeCalled;

@end

@implementation ParseTestModule

- (void)parseDidInitializeWithApplicationId:(NSString *)applicationId clientKey:(NSString *)clientKey {
    self.didInitializeCalled = YES;
}

@end

@interface ParseModuleUnitTests : PFTestCase

@end

@implementation ParseModuleUnitTests

- (void)testModuleSelectors {
    ParseModuleCollection *collection = [[ParseModuleCollection alloc] init];

    ParseTestModule *module = [[ParseTestModule alloc] init];
    [collection addParseModule:module];

    [collection parseDidInitializeWithApplicationId:nil clientKey:nil];

    // Spin the run loop, as the delegate messages are being called on the main thread
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];

    XCTAssertTrue(module.didInitializeCalled, @"Did initialize method should be called on a module.");
}

- (void)testWeakModuleReference {
    ParseModuleCollection *collection = [[ParseModuleCollection alloc] init];

    @autoreleasepool {
        ParseTestModule *module = [[ParseTestModule alloc] init];
        [collection addParseModule:module];
    }

    [collection parseDidInitializeWithApplicationId:nil clientKey:nil];
    XCTAssertEqual([collection modulesCount], 0, @"Module should be removed from the collection.");
}

- (void)testModuleRemove {
    ParseModuleCollection *collection = [[ParseModuleCollection alloc] init];

    ParseTestModule *moduleA = [[ParseTestModule alloc] init];
    ParseTestModule *moduleB = [[ParseTestModule alloc] init];

    [collection addParseModule:moduleA];
    [collection addParseModule:moduleB];

    [collection removeParseModule:moduleA];

    XCTAssertTrue([collection containsModule:moduleB]);
    XCTAssertFalse([collection containsModule:moduleA]);
    XCTAssertEqual([collection modulesCount], 1, @"Module should be removed from the collection");
}

- (void)testNilModule {
    ParseModuleCollection *collection = [[ParseModuleCollection alloc] init];

    XCTAssertNoThrow([collection addParseModule:nil]);
    XCTAssertEqual([collection modulesCount], 0);
    XCTAssertNoThrow([collection removeParseModule:nil]);
    XCTAssertEqual([collection modulesCount], 0);
}

@end

#import <XCTest/XCTest.h>

@interface UITests : XCTestCase
@property XCUIApplication *app;
@end

@implementation UITests
- (void)setUp {
    self.continueAfterFailure = NO;
    self.app = [XCUIApplication new];
    self.app.launchArguments = @[@"-Skip Startup Message", @"1"];
    [self.app launch];
    XCTAssertTrue([self.app.webViews.staticTexts.firstMatch waitForExistenceWithTimeout:30]);
    // Dismiss iOS's first-use Slide to Type tutorial if it covers the keyboard.
    XCUIElement *continueButton = self.app.buttons[@"Continue"];
    if (continueButton.exists) [continueButton tap];
}
- (void)waitForOutput:(NSString *)output timeout:(NSTimeInterval)timeout {
    XCUIElement *line = [self.app.webViews.staticTexts matchingPredicate:
        [NSPredicate predicateWithFormat:@"label CONTAINS %@", output]].firstMatch;
    XCTAssertTrue([line waitForExistenceWithTimeout:timeout], @"Missing Linux command output: %@", output);
}
- (void)testLinuxShellAndPersistentFilesystem {
    [self.app typeText:@"printf 'JIZA_%s\\n' LINUX_LOCAL; uname -s; mkdir -p /root/jiza; printf 'JIZA_%s\\n' PERSISTED > /root/jiza/proof.txt; cat /root/jiza/proof.txt\n"];
    [self waitForOutput:@"JIZA_LINUX_LOCAL" timeout:15];
    [self waitForOutput:@"JIZA_PERSISTED" timeout:15];
    [self.app terminate];
    [self.app launch];
    XCTAssertTrue([self.app.webViews.staticTexts.firstMatch waitForExistenceWithTimeout:30]);
    [self.app typeText:@"cat /root/jiza/proof.txt\n"];
    [self waitForOutput:@"JIZA_PERSISTED" timeout:15];
    XCTAttachment *image = [XCTAttachment attachmentWithScreenshot:self.app.screenshot];
    image.name = @"Jiza Standalone Linux Terminal"; image.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:image];
}
- (void)testPackageManagerAndPython {
    [self.app typeText:@"apk update && apk add --no-cache bash python3 git nano && python3 -c \"print('JIZA_' + 'PYTHON_OK')\"\n"];
    [self waitForOutput:@"JIZA_PYTHON_OK" timeout:300];
    [self.app typeText:@"bash -c \"printf 'JIZA_%s\\n' BASH_OK\"; git --version\n"];
    [self waitForOutput:@"JIZA_BASH_OK" timeout:20];
    [self waitForOutput:@"git version" timeout:20];
    XCTAttachment *image = [XCTAttachment attachmentWithScreenshot:self.app.screenshot];
    image.name = @"Jiza Linux Packages and Python"; image.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:image];
}
- (void)testControlKeyInterruptsALinuxProcess {
    [self.app typeText:@"sleep 60\n"];
    XCUIElement *control = self.app.buttons[@"terminalControl"];
    XCTAssertTrue([control waitForExistenceWithTimeout:5]);
    XCTAssertTrue(control.isHittable);
    [control tap];
    XCTAssertEqualObjects(control.value, @"1");
    [self.app typeText:@"c"];
    [self.app typeText:@"printf 'JIZA_%s\\n' INTERRUPT_OK\n"];
    [self waitForOutput:@"JIZA_INTERRUPT_OK" timeout:15];
}
@end

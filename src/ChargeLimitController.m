// Settings → Charge Limit. The specifiers come from ChargeLimit.plist in the bundle; the controller keeps the
// resume level below the stop level: the resume list only offers levels under the stop level, and lowering the
// stop level pulls the resume level down with it.
#import <UIKit/UIKit.h>

@interface PSSpecifier : NSObject
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

@interface PSListController : UIViewController {
    NSArray *_specifiers;
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (PSSpecifier *)specifierForID:(NSString *)identifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)reloadSpecifier:(PSSpecifier *)specifier;
@end

@interface ChargeLimitController : PSListController
@end

@implementation ChargeLimitController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"ChargeLimit" target:self];
        [self keepResumeBelowStop];
    }
    return _specifiers;
}

- (void)keepResumeBelowStop {
    PSSpecifier *resume = [self specifierForID:@"resume"];
    int stop = [self stopLevel];
    if ([[self readPreferenceValue:resume] intValue] >= stop) {
        [super setPreferenceValue:@(stop - 10) specifier:resume];
    }
    [self updateResumeChoices];
}

- (int)stopLevel {
    return [[self readPreferenceValue:[self specifierForID:@"stop"]] intValue];
}

// Resume levels from 10% up to 10% below the stop level.
- (void)updateResumeChoices {
    NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array];
    for (int level = 10; level < [self stopLevel]; level += 10) {
        [values addObject:@(level)];
        [titles addObject:[NSString stringWithFormat:@"%d%%", level]];
    }
    [[self specifierForID:@"resume"] setValues:values titles:titles];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if (specifier != [self specifierForID:@"stop"]) {
        return;
    }
    [self keepResumeBelowStop];
    [self reloadSpecifier:[self specifierForID:@"resume"]];
}

@end

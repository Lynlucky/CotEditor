/*
 
 CENavigationBarController.m
 
 CotEditor
 http://coteditor.com
 
 Created by nakamuxu on 2005-08-22.
 
 ------------------------------------------------------------------------------
 
 © 2004-2007 nakamuxu
 © 2014-2016 1024jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 */

#import "CENavigationBarController.h"
#import "CESyntaxOutlineParser.h"
#import "Constants.h"


static const CGFloat kDefaultHeight = 16.0;
static const NSTimeInterval kDuration = 0.12;


@interface CENavigationBarController ()

@property (nonatomic, nullable, strong) IBOutlet NSTextView *textView;  // NSTextView cannot be weak

@property (nonatomic, nullable, weak) IBOutlet NSPopUpButton *outlineMenu;
@property (nonatomic, nullable, weak) IBOutlet NSButton *prevButton;
@property (nonatomic, nullable, weak) IBOutlet NSButton *nextButton;
@property (nonatomic, nullable, weak) IBOutlet NSButton *openSplitButton;
@property (nonatomic, nullable, weak) IBOutlet NSButton *closeSplitButton;
@property (nonatomic, nullable, weak) IBOutlet NSLayoutConstraint *heightConstraint;

@property (nonatomic, nullable, weak) IBOutlet NSProgressIndicator *outlineIndicator;
@property (nonatomic, nullable, weak) IBOutlet NSTextField *outlineLoadingMessage;

// readonly
@property (readwrite, nonatomic, getter=isShown) BOOL shown;

@end




#pragma mark -

@implementation CENavigationBarController

#pragma mark Superclass Methods

// ------------------------------------------------------
/// clean up
- (void)dealloc
// ------------------------------------------------------
{
    _textView = nil;
}


// ------------------------------------------------------
/// nib name
- (nullable NSString *)nibName
// ------------------------------------------------------
{
    return @"NavigationBar";
}


// ------------------------------------------------------
/// view is loaded
- (void)awakeFromNib
// ------------------------------------------------------
{
    [super awakeFromNib];
    
    // hide as default (avoid flick)
    [[self prevButton] setHidden:YES];
    [[self nextButton] setHidden:YES];
    [[self outlineMenu] setHidden:YES];
    
    [[self outlineIndicator] setUsesThreadedAnimation:YES];
}



#pragma mark Public Methods

// ------------------------------------------------------
/// set to show navigation bar.
- (void)setShown:(BOOL)isShown animate:(BOOL)performAnimation
// ------------------------------------------------------
{
    [self setShown:isShown];
    
    NSLayoutConstraint *heightConstraint = [self heightConstraint];
    CGFloat height = [self isShown] ? kDefaultHeight : 0.0;
    
    if (performAnimation) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:kDuration];
            [[heightConstraint animator] setConstant:height];
        } completionHandler:nil];
        
    } else {
        [heightConstraint setConstant:height];
    }
}


// ------------------------------------------------------
/// build outline menu from given array
- (void)setOutlineItems:(nonnull NSArray<NSDictionary<NSString *, id> *> *)outlineItems
// ------------------------------------------------------
{
    // stop outline extracting indicator
    [[self outlineIndicator] stopAnimation:self];
    [[self outlineLoadingMessage] setHidden:YES];
    
    [[self outlineMenu] removeAllItems];
    
    BOOL hasOutlineItems = [outlineItems count];
    // set buttons status here to avoid flicking (2008-05-17)
    [[self outlineMenu] setHidden:!hasOutlineItems];
    [[self prevButton] setHidden:!hasOutlineItems];
    [[self nextButton] setHidden:!hasOutlineItems];
    
    if (!hasOutlineItems) { return; }
    
    NSMenu *menu = [[self outlineMenu] menu];
    
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [paragraphStyle setTabStops:@[]];
    [paragraphStyle setDefaultTabInterval:floor(2 * [[menu font] advancementForGlyph:(NSGlyph)' '].width)];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [paragraphStyle setTighteningFactorForTruncation:0];  // don't tighten
    NSDictionary<NSString *, id> *baseAttributes = @{NSFontAttributeName: [menu font],
                                                     NSParagraphStyleAttributeName: paragraphStyle};
    
    // add headding item
    [menu addItemWithTitle:NSLocalizedString(@"<Outline Menu>", nil)
                    action:@selector(setSelectedRangeWithNSValue:)
             keyEquivalent:@""];
    [[menu itemAtIndex:0] setTarget:[self textView]];
    [[menu itemAtIndex:0] setRepresentedObject:[NSValue valueWithRange:NSMakeRange(0, 0)]];
    
    // add outline items
    for (NSDictionary<NSString *, id> *outlineItem in outlineItems) {
        if ([outlineItem[CEOutlineItemTitleKey] isEqualToString:CESeparatorString]) {
            [menu addItem:[NSMenuItem separatorItem]];
            continue;
        }
        
        NSString *title = outlineItem[CEOutlineItemTitleKey];
        NSRange titleRange = NSMakeRange(0, [title length]);
        NSMutableAttributedString *attrTitle = [[NSMutableAttributedString alloc] initWithString:title
                                                                                      attributes:baseAttributes];
        
        NSFontTraitMask fontTrait;
        fontTrait = [outlineItem[CEOutlineItemStyleBoldKey] boolValue] ? NSBoldFontMask : 0;
        fontTrait |= [outlineItem[CEOutlineItemStyleItalicKey] boolValue] ? NSItalicFontMask : 0;
        [attrTitle applyFontTraits:fontTrait range:titleRange];
        
        if ([outlineItem[CEOutlineItemStyleUnderlineKey] boolValue]) {
            [attrTitle addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:titleRange];
        }
        
        NSMenuItem *menuItem = [[NSMenuItem alloc] init];
        [menuItem setAttributedTitle:attrTitle];
        [menuItem setAction:@selector(setSelectedRangeWithNSValue:)];
        [menuItem setTarget:[self textView]];
        [menuItem setRepresentedObject:outlineItem[CEOutlineItemRangeKey]];
        
        [menu addItem:menuItem];
    }
    
    [self selectOutlineMenuItemWithRange:[[self textView] selectedRange]];
}


// ------------------------------------------------------
/// set outline menu selection
- (void)selectOutlineMenuItemWithRange:(NSRange)range
// ------------------------------------------------------
{
    if (![[self outlineMenu] isEnabled]) { return; }
    
    NSMenu *menu = [[self outlineMenu] menu];
    NSInteger count = [menu numberOfItems];
    if (count < 1) { return; }
    NSInteger index;

    if (NSEqualRanges(range, NSMakeRange(0, 0))) {
        index = 1;
    } else {
        for (index = 1; index < count; index++) {
            NSMenuItem *menuItem = [menu itemAtIndex:index];
            NSRange itemRange = [[menuItem representedObject] rangeValue];
            if (itemRange.location > range.location) {
                break;
            }
        }
    }
    // ループを抜けた時点で「次のアイテムインデックス」になっているので、減ずる
    index--;
    // skip separators
    while ([[[self outlineMenu] itemAtIndex:index] isSeparatorItem]) {
        index--;
        if (index < 0) {
            break;
        }
    }
    [[self outlineMenu] selectItemAtIndex:index];
    [self updatePrevNextButtonEnabled];
}


// ------------------------------------------------------
/// update enabilities of jump buttons
- (void)updatePrevNextButtonEnabled
// ------------------------------------------------------
{
    [[self prevButton] setEnabled:[self canSelectPrevItem]];
    [[self nextButton] setEnabled:[self canSelectNextItem]];
}


// ------------------------------------------------------
/// can select prev item in outline menu?
- (BOOL)canSelectPrevItem
// ------------------------------------------------------
{
    return ([[self outlineMenu] indexOfSelectedItem] > 1);
}


// ------------------------------------------------------
/// can select next item in outline menu?
- (BOOL)canSelectNextItem
// ------------------------------------------------------
{
    for (NSInteger i = ([[self outlineMenu] indexOfSelectedItem] + 1); i < [[self outlineMenu] numberOfItems]; i++) {
        if (![[[self outlineMenu] itemAtIndex:i] isSeparatorItem]) {
            return YES;
        }
    }
    return NO;
}


// ------------------------------------------------------
/// start displaying outline indicator
- (void)showOutlineIndicator
// ------------------------------------------------------
{
    if (![[self outlineMenu] isEnabled]) {
        [[self outlineIndicator] startAnimation:self];
        [[self outlineLoadingMessage] setHidden:NO];
    }
}


// ------------------------------------------------------
/// set closeSplitButton enabled or disabled
- (void)setCloseSplitButtonEnabled:(BOOL)enabled
// ------------------------------------------------------
{
    [[self closeSplitButton] setHidden:!enabled];
}


// ------------------------------------------------------
/// set image of open split view button
- (void)setSplitOrientationVertical:(BOOL)isVertical
// ------------------------------------------------------
{
    NSString *imageName = isVertical ? @"OpenSplitVerticalTemplate" : @"OpenSplitTemplate";
    
    [[self openSplitButton] setImage:[NSImage imageNamed:imageName]];
}



#pragma mark Action Messages

// ------------------------------------------------------
/// set select prev item of outline menu.
- (IBAction)selectPrevItem:(nullable id)sender
// ------------------------------------------------------
{
    if (![self canSelectPrevItem]) { return; }
    
    NSInteger targetIndex = [[self outlineMenu] indexOfSelectedItem] - 1;
    
    while ([[[self outlineMenu] itemAtIndex:targetIndex] isSeparatorItem]) {
        targetIndex--;
        if (targetIndex < 0) {
            break;
        }
    }
    [[[self outlineMenu] menu] performActionForItemAtIndex:targetIndex];
}


// ------------------------------------------------------
/// set select next item of outline menu.
- (IBAction)selectNextItem:(nullable id)sender
// ------------------------------------------------------
{
    if (![self canSelectNextItem]) { return; }
    
    NSInteger targetIndex = [[self outlineMenu] indexOfSelectedItem] + 1;
    NSInteger maxIndex = [[self outlineMenu] numberOfItems] - 1;
    
    while ([[[self outlineMenu] itemAtIndex:targetIndex] isSeparatorItem]) {
        targetIndex++;
        if (targetIndex > maxIndex) {
            break;
        }
    }
    [[[self outlineMenu] menu] performActionForItemAtIndex:targetIndex];
}

@end

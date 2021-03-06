//
//  RMPrefsWindowController.m
//  Recent Menu
//
//  Created by Tim Schröder on 09.02.11.
//  Copyright 2011 Tim Schröder. All rights reserved.
//
//  This class is partly based on Dave Batton's DBPrefsWindowController
//  http://www.mere-mortal-software.com/blog/details.php?d=2007-03-11

#import "RMConstants.h"
#import "RMPrefsWindowController.h"
#import "RMAppDelegate+UserDefaults.h"
#import "NSDictionary+RMAdditions.h"
#import "RMAppDelegate+Menu.h"
#import "RMAppDelegate.h"
#import "RMAppDelegate+MetadataQuery.h"
#import "SRRecorderControl.h"
#import "RMFilterFormatter.h"
#import "RMLaunchAtLoginController.h"
#import "RMSecurityScopedBookmarkController.h"
#import "RMHotkeyController.h"

#define RMQUERY_DRAG_AND_DROP @"RMQueryDragAndDrop"

static RMPrefsWindowController *_sharedPrefsWindowController = nil;

#pragma mark -
#pragma mark Focus Ring Methods

// Compary Views' Layers, for the focus ring fix
int compareViews (id firstView, id secondView, void *context);
int compareViews (id firstView, id secondView, void *context)
{
	NSResponder *responder = [[firstView window] firstResponder];
	if (!responder) return NSOrderedSame;
	if (responder == firstView) return NSOrderedDescending;
	if ([responder respondsToSelector:@selector(isDescendantOf:)]) {
		NSView *testView = (NSView*)responder;
		if ([testView isDescendantOf:firstView]) return NSOrderedDescending;
	}
	if ([firstView isKindOfClass:[NSScrollView class]]) return NSOrderedDescending;
	return NSOrderedSame;
}


@implementation RMPrefsWindowController

#pragma mark -
#pragma mark Class Methods

+ (RMPrefsWindowController *)sharedPrefsWindowController
{
	if (!_sharedPrefsWindowController) {
		_sharedPrefsWindowController = [[self alloc] initWithWindowNibName:@"Preferences"];
	}
	return _sharedPrefsWindowController;
}


#pragma mark -
#pragma mark KVO Methods

// Returns keypath
-(NSString *)keyPath:(NSString*)tag
{
	NSString *key = @"values.";
	NSString *path = [key stringByAppendingString:tag];
	return path;
}


// Is called when the user changes a setting
- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context

{
	// Fokus Ring - Focus has changed
	if (([[contentSubview subviews] objectAtIndex:0] == queryPrefsView) && ([keyPath isEqualToString:FIRSTRESPONDERKEY])) {
		[queryPrefsView sortSubviewsUsingFunction:(NSComparisonResult (*)(id, id, void*))compareViews context:nil];
	}
		
	// User Defaults have changed
    if ([keyPath isEqual:[self keyPath:DEFAULTS_SEARCHINTERVAL]]) {
		// SearchInterval changed
		[[NSApp delegate] startAllQueries];
	}
		
	if ([keyPath isEqual:[self keyPath:DEFAULTS_SEARCHLOCATION]]) {
		// SearchLocation changed
		[[NSApp delegate] startAllQueries];
	}
	
	// Hauptfenster updaten, wenn Einstellungen der Query geändert wurden    
	if ([keyPath isEqual:[self keyPath:DEFAULTS_SCOPEFILTER]]) {
		[[NSApp delegate] startAllQueries];
	}
}

-(void)observeValue:(NSString*)keypath
{
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
															  forKeyPath:keypath 
																 options:NSKeyValueObservingOptionOld
																 context:nil];
}

-(void)stopObserving:(NSString*)keypath
{
	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self 
																 forKeyPath:keypath];
}


#pragma mark -
#pragma mark Setup & Teardown

- (id)initWithWindow:(NSWindow *)window
{
	self = [super initWithWindow:nil];
	if (self != nil) {
		// Set up an array and some dictionaries to keep track
		// of the views we'll be displaying.
		toolbarIdentifiers = [[NSMutableArray alloc] init];
		toolbarViews = [[NSMutableDictionary alloc] init];
		toolbarItems = [[NSMutableDictionary alloc] init];
		
		// Set up an NSViewAnimation to animate the transitions.
		viewAnimation = [[NSViewAnimation alloc] init];
		[viewAnimation setAnimationBlockingMode:NSAnimationNonblocking];
		[viewAnimation setAnimationCurve:NSAnimationEaseInOut];
		[viewAnimation setDelegate:self];
        
	}
	return self;
	(void)window;  // To prevent compiler warnings.
}

- (void)windowDidLoad
{
	// Create a new window to display the preference views.
	// If the developer attached a window to this controller
	// in Interface Builder, it gets replaced with this one.
	NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,1000)
												    styleMask:(NSTitledWindowMask |
															   NSClosableWindowMask |
															   NSMiniaturizableWindowMask)
													  backing:NSBackingStoreBuffered
													    defer:YES] autorelease];
	[window setAutorecalculatesKeyViewLoop:YES];
	[self setWindow:window];
	[window setDelegate:self];

	contentSubview = [[[NSView alloc] initWithFrame:[[[self window] contentView] frame]] autorelease];
	[contentSubview setAutoresizingMask:(NSViewMinYMargin | NSViewWidthSizable)];
	[[[self window] contentView] addSubview:contentSubview];
	[[self window] setShowsToolbarButton:NO];
    
	// Prepare drag and drop
	[queryTable registerForDraggedTypes:[NSArray arrayWithObject:RMQUERY_DRAG_AND_DROP]];
    
}

- (void)windowWillClose:(NSNotification *)notification
{
	[[self window] removeObserver:self forKeyPath:FIRSTRESPONDERKEY];
	[self stopObserving:[self keyPath:DEFAULTS_SCOPEFILTER]];
	[self stopObserving:[self keyPath:DEFAULTS_SEARCHINTERVAL]];
	[self stopObserving:[self keyPath:DEFAULTS_SEARCHLOCATION]];
	
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) dealloc {
	[toolbarIdentifiers release];
	[toolbarViews release];
	[toolbarItems release];
	[viewAnimation release];
	[super dealloc];
}


#pragma mark -
#pragma mark Configuration

- (void)setupToolbar
{
	[self addView:generalPrefsView 
			label:PREFWINDOW_GENERALPANE
			image:[NSImage imageNamed:@"General"]];
	[self addView:advancedPrefsView 
			label:PREFWINDOW_SEARCHPANE
			image:[NSImage imageNamed:@"Search"]];
	[self addView:queryPrefsView 
			label:PREFWINDOW_QUERIESPANE
			image:[NSImage imageNamed:@"Queries"]];	
}

- (void)addView:(NSView *)view label:(NSString *)label image:(NSImage *)image
{
	NSAssert (view != nil,
			  @"Attempted to add a nil view when calling -addView:label:image:.");
	
	NSString *identifier = [[label copy] autorelease];
	
	[toolbarIdentifiers addObject:identifier];
	[toolbarViews setObject:view forKey:identifier];
	
	NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
	[item setLabel:label];
	[item setImage:image];
	[item setTarget:self];
	[item setAction:@selector(toggleActivePreferenceView:)];
	
	[toolbarItems setObject:item forKey:identifier];
}


#pragma mark -
#pragma mark Action Methods

-(void)showGeneralPrefsPane
{
    [self showWindow:self];
    [self displayViewForIdentifier:[toolbarIdentifiers objectAtIndex:0] animate:NO];
    [[self window] setInitialFirstResponder:accessButton];
}

-(NSWindow*)prefsWindow
{
    return ([self window]);
}

-(void)setAccessButtonTitleToRevoke
{
    [accessButton setTitle:PREFWINDOW_REVOKEBUTTON];
    [accessButton sizeToFit];
    NSRect rect = [accessButton frame];
    rect.size.width += 20.0;
    [accessButton setFrame:rect];
}

-(void)setAccessButtonTitleToGrant
{
    [accessButton setTitle:PREFWINDOW_GRANTBUTTON];
    [accessButton sizeToFit];
    NSRect rect = [accessButton frame];
    rect.size.width += 20.0;
    [accessButton setFrame:rect];
}

-(IBAction)toggleAccess:(id)sender
{
    [popover close];
    if ([[RMSecurityScopedBookmarkController sharedController] hasBookmark]) {
        [[RMSecurityScopedBookmarkController sharedController] deleteBookmark];
        [self setAccessButtonTitleToGrant];
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_ACCESS_REMOVED object:self];
    } else {
        [[RMSecurityScopedBookmarkController sharedController] grantBookmarkAccessForWindow:[self window]];
    }

}

-(IBAction)toggleLaunchAtLogin:(id)sender
{
    if ([sender selectedSegment] == 0) { // ON
        if (![[RMLaunchAtLoginController sharedController] launchAtLogin]) [[RMLaunchAtLoginController sharedController] turnOnLaunchAtLogin];
    }
    if ([sender selectedSegment] == 1) { // OFF
        if ([[RMLaunchAtLoginController sharedController] launchAtLogin]) [[RMLaunchAtLoginController sharedController] turnOffLaunchAtLogin];
    }
}

-(void)showNeedsAccessRightsAlert
{
    [popoverMessageField setStringValue:PREFWINDOW_NEEDACCESSMESSAGE];
    [popover showRelativeToRect:[accessButton bounds] ofView:accessButton preferredEdge:NSMaxXEdge];
}

- (IBAction)showWindow:(id)sender
{
	(void)[self window];
	// Clear the last setup and get a fresh one.
	[toolbarIdentifiers removeAllObjects];
	[toolbarViews removeAllObjects];
	[toolbarItems removeAllObjects];
	[self setupToolbar];
	
	NSAssert (([toolbarIdentifiers count] > 0),
			  @"No items were added to the toolbar in -setupToolbar.");
	
	if ([[self window] toolbar] == nil) {
		NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"RMPreferencesToolbar"];
		[toolbar setAllowsUserCustomization:NO];
		[toolbar setAutosavesConfiguration:NO];
		[toolbar setSizeMode:NSToolbarSizeModeDefault];
		[toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
		[toolbar setDelegate:self];
		[[self window] setToolbar:toolbar];
		[toolbar release];
	}
	
	// Select pane to show initially, and recalculate key view loop
	[[[self window] toolbar] setSelectedItemIdentifier:[toolbarIdentifiers objectAtIndex:0]];
	[self displayViewForIdentifier:[toolbarIdentifiers objectAtIndex:0] animate:NO];
	[[self window] recalculateKeyViewLoop];
	
	// Determine window position
	[[self window] center];
	
	[self observeValue:[self keyPath:DEFAULTS_SCOPEFILTER]];
	[self observeValue:[self keyPath:DEFAULTS_SEARCHINTERVAL]];
	[self observeValue:[self keyPath:DEFAULTS_SEARCHLOCATION]];

	// KVO for focus ring
	[[self window] addObserver:self
					forKeyPath:FIRSTRESPONDERKEY
					   options:NSKeyValueObservingOptionOld
					   context:nil];

	// Set selection in query list
	[queryArrayController setSelectionIndex:0];
	
    // determine hot key info
    NSDictionary *dict = [[RMHotkeyController sharedController] loadHotkeyPreferences];
    if (dict) [recorderControl setObjectValue:dict];
    
    // determine launch at login setting
    if ([[RMLaunchAtLoginController sharedController] launchAtLogin]) [launchAtLoginButton setSelectedSegment:0];
    
    // localize has-access button
    BOOL hasAccess = [[RMSecurityScopedBookmarkController sharedController] hasBookmark];
    if (hasAccess) {
        [self setAccessButtonTitleToRevoke];
    } else {
        [self setAccessButtonTitleToGrant];
    }
    [accessLabel setStringValue:PREFWINDOW_ACCESSLABEL];
    
	// Show window
	[super showWindow:sender];
}

// Create new query
-(IBAction)addQuery:(id)sender
{
	
	// generate new unique tag
	int newTag = 0;
	int i;
	BOOL foundTag = NO;
	BOOL alreadyThere = NO;
	int count = [[queryArrayController arrangedObjects] count];
	do {
		for (i=0;i<count;i++) {
			if ((!foundTag) && (!alreadyThere)) {
				NSNumber *compareTag = [[[queryArrayController arrangedObjects] objectAtIndex:i] valueForKey:SCOPE_DICT_TAG];
				if ([compareTag intValue] == newTag) alreadyThere = YES;
			}
		}
		if (!alreadyThere) {
			foundTag = YES;
		} else {
			newTag++;
			alreadyThere = NO;
		}
	} while (foundTag == NO);
	
	// Generate new query
	NSDictionary *dict = [NSDictionary createFilter:QUERY_DEFAULTTITLE 
										   withType:QUERY_DEFAULTTYPE
										  withValue:QUERY_DEFAULTVALUE
										 isEditable:YES
										  isEnabled:NO
											withTag:[NSNumber numberWithInteger:newTag]];
	
	NSInteger index = [queryArrayController selectionIndex];
	if (index == NSNotFound) {
		index = 0;
	} else index++;
	
	[queryArrayController insertObject:dict
				 atArrangedObjectIndex:index];
	[queryArrayController setSelectionIndex:index];
	[queryTable scrollRowToVisible:index];
}

// Delete query
-(IBAction)removeQuery:(id)sender
{
	NSInteger index = [queryArrayController selectionIndex];
	if (index == NSNotFound) return;
	[queryArrayController removeObjectAtArrangedObjectIndex:index];
	int cnt;
	cnt = [[queryArrayController arrangedObjects] count];
	if (index >= cnt) index--;
	[queryArrayController setSelectionIndex:index];
}


// Reset filters
-(IBAction) resetQueries:(id)sender
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    //[defaults setObject:[RMFilterController standardFilters] forKey:DEFAULTS_SCOPEFILTER];
    [defaults synchronize]; 
    [queryArrayController setSelectionIndex:0];
}

#pragma mark -
#pragma mark TableView Delegate

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard

{
    // Copy the row numbers to the pasteboard.
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
    [pboard declareTypes:[NSArray arrayWithObject:RMQUERY_DRAG_AND_DROP] owner:self];
    [pboard setData:data forType:RMQUERY_DRAG_AND_DROP];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op

{
	int result = NSDragOperationNone;
	if ((op == NSTableViewDropAbove) && (row != 0)) {
		result = NSDragOperationMove;
	}
    return result;
}


- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info
			  row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    NSPasteboard* pboard = [info draggingPasteboard];
    NSData* rowData = [pboard dataForType:RMQUERY_DRAG_AND_DROP];
    NSIndexSet* rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
    NSInteger dragRow = [rowIndexes firstIndex];
	if (dragRow == 0) return NO;
	NSDictionary *dict = [[[queryArrayController arrangedObjects] objectAtIndex:dragRow] copy];
	[queryArrayController removeObjectAtArrangedObjectIndex:dragRow];
	int cnt;
	cnt = [[queryArrayController arrangedObjects] count];
	if (row >= cnt) row--;
	[queryArrayController insertObject:dict
				 atArrangedObjectIndex:row];
	[dict release];
	[queryArrayController setSelectionIndex:row];
	return YES;
}

#pragma mark -
#pragma mark Toolbar

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return toolbarIdentifiers;
	(void)toolbar;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar 
{
	return toolbarIdentifiers;
	(void)toolbar;
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	return toolbarIdentifiers;
	(void)toolbar;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)willBeInserted 
{
	return [toolbarItems objectForKey:identifier];
	(void)toolbar;
	(void)willBeInserted;
}


- (void)toggleActivePreferenceView:(NSToolbarItem *)toolbarItem
{
	[self displayViewForIdentifier:[toolbarItem itemIdentifier] animate:YES];
}


- (void)displayViewForIdentifier:(NSString *)identifier animate:(BOOL)animate
{	
	// Find the view we want to display.
	NSView *newView = [toolbarViews objectForKey:identifier];
	
	[[[self window] toolbar] setSelectedItemIdentifier:identifier];

	
	// See if there are any visible views.
	NSView *oldView = nil;
	if ([[contentSubview subviews] count] > 0) {
		// Get a list of all of the views in the window. Usually at this
		// point there is just one visible view. But if the last fade
		// hasn't finished, we need to get rid of it now before we move on.
		NSEnumerator *subviewsEnum = [[contentSubview subviews] reverseObjectEnumerator];
		
		// The first one (last one added) is our visible view.
		oldView = [subviewsEnum nextObject];
		
		// Remove any others.
		NSView *reallyOldView = nil;
		while ((reallyOldView = [subviewsEnum nextObject]) != nil) {
			[reallyOldView removeFromSuperviewWithoutNeedingDisplay];
		}
	}
	
	if (![newView isEqualTo:oldView]) {		
		NSRect frame = [newView bounds];
		frame.origin.y = NSHeight([contentSubview frame]) - NSHeight([newView bounds]);
		[newView setFrame:frame];
		[contentSubview addSubview:newView];
		[[self window] setInitialFirstResponder:newView];
		
		if (animate)
			[self crossFadeView:oldView withView:newView];
		else {
			[oldView removeFromSuperviewWithoutNeedingDisplay];
			[newView setHidden:NO];
			[[self window] setFrame:[self frameForView:newView] display:YES animate:animate];
		}
		NSString *titleString = [NSString stringWithFormat:PREFWINDOW_TITLE, [[toolbarItems objectForKey:identifier] label]];
		[[self window] setTitle:titleString];
	}
}


#pragma mark -
#pragma mark Cross-Fading Methods

- (void)crossFadeView:(NSView *)oldView withView:(NSView *)newView
{
	[viewAnimation stopAnimation];
	[viewAnimation setDuration:0.25];
	
	NSDictionary *fadeOutDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
									   oldView, NSViewAnimationTargetKey,
									   NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
									   nil];
	
	NSDictionary *fadeInDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
									  newView, NSViewAnimationTargetKey,
									  NSViewAnimationFadeInEffect, NSViewAnimationEffectKey,
									  nil];
	
	NSDictionary *resizeDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
									  [self window], NSViewAnimationTargetKey,
									  [NSValue valueWithRect:[[self window] frame]], NSViewAnimationStartFrameKey,
									  [NSValue valueWithRect:[self frameForView:newView]], NSViewAnimationEndFrameKey,
									  nil];
	
	NSArray *animationArray = [NSArray arrayWithObjects:
							   fadeOutDictionary,
							   fadeInDictionary,
							   resizeDictionary,
							   nil];
	
	[viewAnimation setViewAnimations:animationArray];
	[viewAnimation startAnimation];
}


- (void)animationDidEnd:(NSAnimation *)animation
{
	NSView *subview;
	
	// Get a list of all of the views in the window. Hopefully
	// at this point there are two. One is visible and one is hidden.
	NSEnumerator *subviewsEnum = [[contentSubview subviews] reverseObjectEnumerator];
	
	// This is our visible view. Just get past it.
	subview = [subviewsEnum nextObject];
	
	// Remove everything else. There should be just one, but
	// if the user does a lot of fast clicking, we might have
	// more than one to remove.
	while ((subview = [subviewsEnum nextObject]) != nil) {
		[subview removeFromSuperviewWithoutNeedingDisplay];
	}
	
	// This is a work-around that prevents the first
	// toolbar icon from becoming highlighted.
	[[self window] makeFirstResponder:nil];
	
	(void)animation;
}


- (NSRect)frameForView:(NSView *)view
// Calculate the window size for the new view.
{
	NSRect windowFrame = [[self window] frame];
	NSRect contentRect = [[self window] contentRectForFrameRect:windowFrame];
	float windowTitleAndToolbarHeight = NSHeight(windowFrame) - NSHeight(contentRect);
	
	windowFrame.size.height = NSHeight([view frame]) + windowTitleAndToolbarHeight;
	windowFrame.size.width = NSWidth([view frame]);
	windowFrame.origin.y = NSMaxY([[self window] frame]) - NSHeight(windowFrame);
	
	return windowFrame;
}

#pragma mark -
#pragma mark ShortcutRecorder Delegate

- (BOOL)shortcutRecorder:(SRRecorderControl *)aRecorder isKeyCode:(NSInteger)keyCode andFlagsTaken:(NSUInteger)flags reason:(NSString **)aReason
{
    return NO;
}


- (void)shortcutRecorder:(SRRecorderControl *)aRecorder keyComboDidChange:(KeyCombo)newKeyCombo
{
    NSInteger code = newKeyCombo.code;
    NSUInteger flags = newKeyCombo.flags;
    [[RMHotkeyController sharedController] updateHotkeyWithKeyCode:code andFlags:flags];
    [[RMHotkeyController sharedController] saveHotkeyPreferencesWithKeyCode:code andFlags:flags];
}



@end


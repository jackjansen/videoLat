//
//  SettingsView.m
//
//  Created by Jack Jansen on 26-08-10.
//  Copyright 2010 Centrum voor Wiskunde en Informatica. All rights reserved.
//

#import "SettingsView.h"
#import "iSight.h"

@implementation SettingsView

@synthesize xmit;
@synthesize datatypeQRCode;
@synthesize datatypeBlackWhite;
@synthesize mirrorView;

@synthesize recv;
@synthesize detectString;
@synthesize bwString;
@synthesize blackWhiteRect;
@synthesize foundQRcode;

@synthesize waitForDetection;
@synthesize coordHelper;
@synthesize waitDelay;

@synthesize running;
@synthesize summarize;

@synthesize manager;

- (NSString *)fileName {
    [bChooseFile setEnabled: NO];
    return [fileName retain];
}

- (void)awakeFromNib
{
	xmit = true;
    datatypeQRCode = true;
    datatypeBlackWhite = false;
    mirrorView = false;

    recv = true;

    waitForDetection = true;
	coordHelper = [NSString stringWithUTF8String: "None"];
	waitDelay = 0;

    running = false;
	summarize = true;
	
    blackWhiteRect = NSMakeRect(0, 0, -1, -1);
    detectString = [NSString stringWithUTF8String: "none"];
    bwString = [NSString stringWithUTF8String: "none"];
    fileName = [NSString stringWithUTF8String: "/tmp/measurements.csv"];
	[bCameras addItemsWithTitles: [inputHandler deviceNames]];
    [self updateButtons: self];
	[self roleChanged: self];
}

- (IBAction)cameraChanged: (id) sender
{
	NSMenuItem *item = [sender selectedItem];
	NSString *cam = [item title];
	NSLog(@"Switch to %@\n", cam);
	[inputHandler switchToDeviceWithName: cam];
}

- (IBAction)buttonChanged: (id) sender
{
    // Data type (Note: measurement-type popup change is handled by roleChange:)
    NSButtonCell *selCell = [bDataType selectedCell];
    datatypeQRCode = selCell == bDataTypeQRCode;
    datatypeBlackWhite = selCell == bDataTypeBlackWhite;
    
    // Transmission
    xmit = [bXmit state] == NSOnState;
    mirrorView = [bMirror state] == NSOnState;

    // Reception
    recv = [bRecv state] == NSOnState;


    // Coordination
    waitForDetection = [bWait state] == NSOnState;
	NSMenuItem *selHelper = [bCoordHelper selectedCell];
	coordHelper = [selHelper title];
	waitDelay = [bWaitDelay intValue];
    
    // Output
    fileName = [[bFilename stringValue] retain];
    summarize = [bSummarize state] == NSOnState;

    // Run
    running = [bRunning state] == NSOnState;
    [manager settingsChanged];
}

- (IBAction)roleChanged: (id) sender
{
    NSMenuItem *selItem = [bRole selectedItem];
    BOOL enabled = NO;
	BOOL needCam = NO;
	BOOL hasCam = [inputHandler available];
    if ([selItem tag] == roleXmitOnly) {
        [bXmit setState: NSOnState];
        [bRecv setState: NSOffState];
        [bDataType selectCell: bDataTypeQRCode];
        [bWait setState: NSOffState];
        [bCoordHelper selectItemWithTitle: @"None"];
    } else if ([selItem tag] == roleRecvOnly) {
        [bXmit setState: NSOffState];
        [bRecv setState: NSOnState];
        [bDataType selectCell: nil];
        [bWait setState: NSOffState];
        [bCoordHelper selectItemWithTitle: @"None"];
		needCam = YES;
    } else if ([selItem tag] == roleRoundTrip) {
        [bXmit setState: NSOnState];
        [bRecv setState: NSOnState];
        [bDataType selectCell: bDataTypeQRCode];
        [bWait setState: NSOnState];
        [bCoordHelper selectItemWithTitle: @"None"];
		needCam = YES;
    } else if ([selItem tag] == roleXmitSelf) {
        [bXmit setState: NSOnState];
        [bRecv setState: NSOffState];
        [bDataType selectCell: bDataTypeBlackWhite];
        [bWait setState: NSOnState];
        [bCoordHelper selectItemWithTitle: @"sw_labjack"];
    } else if ([selItem tag] == roleRecvSelf) {
        [bXmit setState: NSOffState];
        [bRecv setState: NSOnState];
        [bDataType selectCell: bDataTypeBlackWhite];
        [bWait setState: NSOnState];
        [bCoordHelper selectItemWithTitle: @"sw_labjack"];
		needCam = YES;
    } else {
        // Leave buttons as-is
        enabled = YES;
    }
	if (!hasCam) {
		[bRecv setState: NSOffState];
	}

    [bXmit setEnabled: enabled];
    [bRecv setEnabled: (enabled && hasCam)];
    [bDataType setEnabled: enabled];
    [bWait setEnabled: enabled];
    
    [self buttonChanged: self];
	if (needCam && !hasCam && sender != self) {
		NSRunAlertPanel(@"Error", @"This mode requires a camera", nil, nil, nil);
	}
}

- (void)chooseFile: (id) sender
{
    NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setExtensionHidden: NO];
	[savePanel setAllowedFileTypes:[NSArray arrayWithObject:@"csv"]];
	[ savePanel setAllowsOtherFileTypes:YES];
	[savePanel setNameFieldStringValue: @"measurements"];
    if ([savePanel runModal] == NSFileHandlingPanelOKButton) {
        NSURL *selUrl = [savePanel URL];
        assert([selUrl isFileURL]);
        fileName = [selUrl path];
        [self updateButtons: self];
    }
}

- (void)updateButtons: (id)sender
{
    // Transmission
    [bXmit setState: xmit?NSOnState:NSOffState];
	[bMirror setState: mirrorView?NSOnState:NSOffState];

    // Reception
    [bRecv setState: recv?NSOnState:NSOffState];
    [bDetected setStringValue: detectString];
    if (foundQRcode) {
        [bDetected setTextColor:[NSColor blackColor]];
    } else {
        [bDetected setTextColor:[NSColor redColor]];
    }
    if (NSIsEmptyRect(blackWhiteRect)) {
        [bLocation setStringValue: @"No QR code found yet"];
    } else {
        NSString * loc = [NSString stringWithFormat: @"pos %d,%d size %d,%d", 
            (int)blackWhiteRect.origin.x,
            (int)blackWhiteRect.origin.y,
            (int)blackWhiteRect.size.width,
            (int)blackWhiteRect.size.height];
        [bLocation setStringValue: loc];
    }
    [bBWstatus setStringValue: bwString];

    // Coordination
    [bWait setState: waitForDetection?NSOnState:NSOffState];
    [bCoordHelper selectItemWithTitle: coordHelper];
	[bWaitDelay setIntValue: waitDelay];

    // Output
    [bFilename setStringValue: fileName];
    [bSummarize setState: summarize?NSOnState:NSOffState];

    // Run
    [bRunning setState: running?NSOnState:NSOffState];
    
}

- (void)updateButtonsIfNeeded
{
    if( [[self window] isVisible])
        [self performSelectorOnMainThread:@selector(updateButtons:) withObject:self waitUntilDone:NO];
}


@end

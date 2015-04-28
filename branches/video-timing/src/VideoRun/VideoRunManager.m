//
//  VideoRunManager.m
//
//  Created by Jack Jansen on 27-08-10.
//  Copyright 2010-2014 Centrum voor Wiskunde en Informatica. Licensed under GPL3.
//

#import "VideoRunManager.h"
#import "FindQRCodes.h"
#import "GenQRCodes.h"
#import "EventLogger.h"
#import <sys/sysctl.h>


@implementation VideoRunManager
@synthesize mirrored;
@synthesize selectionView;

//
// Prerun parameters.
// We want 10 consecutive catches, and we initially start with a 1ms delay (doubled at every failure)

- (int) initialPrerunCount { return 10; }
- (int) initialPrerunDelay { return 1000; }

+ (void) initialize
{
    [BaseRunManager registerClass: [self class] forMeasurementType: @"Video Roundtrip"];
    [BaseRunManager registerNib: @"VideoRun" forMeasurementType: @"Video Roundtrip"];
#ifdef WITH_UIKIT
    [BaseRunManager registerSelectionNib: @"VideoInputSelectionView" forMeasurementType: @"Video Roundtrip"];
#endif
}

- (VideoRunManager*)init
{
    self = [super init];
	if (self) {
        prevOutputCode = nil;
		outputCodeImage = nil;

        prevInputCode = nil;
	}
    return self;
}

- (void)dealloc
{
    // Deallocate the capturer first
    self.capturer = nil;
	self.clock = nil;
}

- (void) awakeFromNib
{
    if ([super respondsToSelector:@selector(awakeFromNib)]) [super awakeFromNib];
    @synchronized(self) {
        assert(self.clock);
    }
}

- (void)stop
{
	if (self.capturer) [self.capturer stop];
	self.capturer = nil;
	self.clock = nil;
}

- (void)triggerNewOutputValue
{
	@synchronized(self) {
//xyzzy		prerunOutputStartTime = 0;
//xyzzy		outputStartTime = 0;
//xyzzy		inputStartTime = 0;
		outputCodeImage = nil;
		[self.outputView performSelectorOnMainThread:@selector(showNewData) withObject:nil waitUntilDone:NO ];
	}
}


#pragma mark MeasurementOutputManagerProtocol

- (CIImage *)newOutputStart
{
    // Called from the redraw routine, should generate a new output code only when needed.
    @synchronized(self) {
        
        // If we are not running we should display a blue-grayish square
        if (!self.running && !self.preRunning) {
            CIImage *idleImage = [CIImage imageWithColor:[CIColor colorWithRed:0.1 green:0.4 blue:0.5]];
            CGRect rect = {0, 0, 480, 480};
            idleImage = [idleImage imageByCroppingToRect: rect];
            return idleImage;
        }
        
        // If we have already generated a QR code that hasn't been detected yet we return that.
        if (outputCodeImage)
            return outputCodeImage;
        
        // Generate a new image. First obtain the timestamp.
        uint64_t tsForCode = [self.clock now];

        // Sanity check: times should be monotonically increasing
        if (tsOutLatest && tsOutLatest >= tsForCode) {
#ifdef WITH_APPKIT
            NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: output clock not monotonically increasing."
                    defaultButton:@"OK"
                    alternateButton:nil
                    otherButton:nil
                    informativeTextWithFormat:@"Previous value was %lld, current value is %lld.\nConsult Helpfile if this error persists.",
                              (long long)tsOutLatest,
                              (long long)tsForCode];
            [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
#else
			showWarningAlert(@"Output clock has gone back in time");
#endif
        }
        
        // Generate the new output code. During preRunning, our input companion can
        // supply the codes, if it wants to (the NetworkRunManager does this, so the
        // codes contain the ip/port combination of the server)
        self.outputCode = nil;
        if (self.preRunning && [self.inputCompanion respondsToSelector:@selector(genPrerunCode)]) {
            self.outputCode = [self.inputCompanion genPrerunCode];
        }
        if (self.outputCode == nil) {
            self.outputCode = [NSString stringWithFormat:@"%lld", tsForCode];
        }
        if (VL_DEBUG) NSLog(@"New output code: %@", self.outputCode);
        int bpp = 4;
        CGSize size = {480, 480};
        char *bitmapdata = (char*)malloc(size.width*size.height*bpp);
        memset(bitmapdata, 0xf0, size.width*size.height*bpp);
        assert(self.genner);
        [self.genner gen: bitmapdata width:size.width height:size.height code:[self.outputCode UTF8String]];
        NSData *data = [NSData dataWithBytesNoCopy:bitmapdata length:(size.width*size.height*bpp) freeWhenDone: YES];
		assert(data);
		outputCodeImage = [CIImage imageWithBitmapData:data bytesPerRow:bpp*size.width size:size format:kCIFormatARGB8 colorSpace:nil];
		assert(outputCodeImage);
		tsOutEarliest = [self.clock now];
		tsOutLatest = 0;
		return outputCodeImage;
    }
}

- (void) newOutputDone
{
    @synchronized(self) {
		if (tsOutEarliest == 0) {
			// We haven't generated an output code yet, so ignore this, a redraw
			// because of some other reason
			return;
		}
		if (tsOutLatest != 0) {
			// We have already received the redraw for our mosyt recent generated code.
			// Again, redraw for some other reason, ignore.
			return;
		}
        assert(tsOutEarliest);
		assert(tsOutLatest == 0);
		tsOutLatest = [self.clock now];
		uint64_t tsOutToRemember = tsOutLatest;
		if (self.running) {
			[self.collector recordTransmission: self.outputCode at: tsOutToRemember];
			VL_LOG_EVENT(@"transmission", tsOutToRemember, self.outputCode);
        }
    }
}

#pragma mark MeasurementInputManagerProtocol

- (IBAction)startPreMeasuring: (id)sender
{
	[super startPreMeasuring: sender];
	self.outputView.mirrored = self.mirrored;
}

- (void)setFinderRect: (NSorUIRect)theRect
{
#if 0
	[self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
#endif
}


- (void) newInputStart:(uint64_t)timestamp
{
    @synchronized(self) {
//    assert(inputStartTime == 0);
        if (self.collector) {
			tsFrameEarliest = tsFrameLatest;
			tsFrameLatest = timestamp;

            // Sanity check: times should be monotonically increasing
            if (tsFrameEarliest >= tsFrameLatest) {
#ifdef WITH_APPKIT
                NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: input clock not monotonically increasing."
                                                 defaultButton:@"OK"
                                               alternateButton:nil
                                                   otherButton:nil
                                     informativeTextWithFormat:@"Previous value was %lld, current value is %lld.\nConsult Helpfile if this error persists.",
                                  (long long)tsFrameEarliest,
                                  (long long)tsFrameLatest];
                [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
#else
				showWarningAlert(@"Input clock has gone back in time");
#endif
            }
        }
    }
}

- (void) newInputStart
{
	assert(0); // I think this method shouldn't be used...
    [self newInputStart: [self.clock now]];
}

- (void) _prerunRecordNoReception
{
#if 1
    if (VL_DEBUG) NSLog(@"Prerun no reception\n");
    assert(self.preRunning);
    if (tsOutLatest && [self.clock now] - tsOutLatest > maxDelay) {
        // No data found within alotted time. Double the time, reset the count, change mirroring
        if (VL_DEBUG) NSLog(@"tsOutLatest=%llu, prerunDelay=%llu, mirrored=%d\n", tsOutLatest, maxDelay, self.mirrored);
        maxDelay *= 2;
        prerunMoreNeeded = self.initialPrerunCount;
        self.mirrored = !self.mirrored;
        self.outputView.mirrored = self.mirrored;
        self.statusView.detectCount = [NSString stringWithFormat: @"%d more, mirrored=%d", prerunMoreNeeded, (int)self.mirrored];
		self.statusView.detectAverage = @"";
        [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
        [self.outputCompanion triggerNewOutputValue];
    } 
#endif
}

- (void) _prerunRecordReception: (NSString *)code
{
    if (VL_DEBUG) NSLog(@"prerun reception %@\n", code);
    assert(self.preRunning);
    if (self.preRunning) {
        prerunMoreNeeded -= 1;
        self.statusView.detectCount = [NSString stringWithFormat: @"%d more, mirrored=%d", prerunMoreNeeded, (int)self.mirrored];
		self.statusView.detectAverage = @"";
        [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
        if (VL_DEBUG) NSLog(@"preRunMoreMeeded=%d\n", prerunMoreNeeded);
        if (prerunMoreNeeded == 0) {
            NSLog(@"average detection algorithm duration=%lld µS", averageFinderDuration);
#ifdef WITH_SET_MIN_CAPTURE_DURATION
            [self.capturer setMinCaptureInterval: averageFinderDuration*2];
#endif
            self.statusView.detectCount = @"";
			self.statusView.detectAverage = @"";
            [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
            [self performSelectorOnMainThread: @selector(stopPreMeasuring:) withObject: self waitUntilDone: NO];
        }
    }
}

- (void) newInputDone: (void*)buffer width: (int)w height: (int)h format: (const char*)formatStr size: (int)size
{
    @synchronized(self) {
		if (self.outputCompanion.outputCode == nil) {
			if (VL_DEBUG) NSLog(@"newInputDone called, but no output code yet\n");
			return;
		}
        if (tsFrameLatest == 0) {
            NSLog(@"newInputDone called, but tsFrameLatest==0\n");
			assert(0);
            return;
        }
        uint64_t finderStartTime = [self.clock now];
        char *code = [self.finder find: buffer width: w height: h format: formatStr size:size];
        uint64_t finderStopTime = [self.clock now];
        uint64_t finderDuration = finderStopTime - finderStartTime;
        BOOL foundQRcode = (code != NULL);
        if (foundQRcode) {
            
			// Compare the code to what was expected.
            if (prevOutputCode && strcmp(code, [prevOutputCode UTF8String]) == 0) {
				//NSLog(@"Received old output code again: %s", code);
            } else if (prevInputCode && strcmp(code, [prevInputCode UTF8String]) == 0) {
                prevInputCodeDetectionCount++;
                if (VL_DEBUG) NSLog(@"Received same code as last reception: %s, count=%d", code, prevInputCodeDetectionCount);
                if ((prevInputCodeDetectionCount % 250) == 0) {
#ifdef WITH_APPKIT
                    NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: no new QR code generated."
                                                     defaultButton:@"OK"
                                                   alternateButton:nil
                                                       otherButton:nil
                                         informativeTextWithFormat:@"QR-code %@ detected %d times. Generating new one.",
                                      prevInputCode, prevInputCodeDetectionCount];
                    [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
#endif
                    [self.outputCompanion triggerNewOutputValue];
                }
            } else if (strcmp(code, [self.outputCompanion.outputCode UTF8String]) == 0) {
				// Correct code found.
                
                // Let's first report it.
				if (self.running) {
					assert(tsOutLatest);	// Must have been set before we can detect a qr-code
					assert(tsFrameLatest);	// Must have gotten an input frame before we get here
					uint64_t oldestTimePossible = tsOutLatest;	// Cannot detect before it has been generated
					if (tsFrameEarliest > oldestTimePossible) oldestTimePossible = tsFrameEarliest;
					uint64_t bestTimeStamp = (oldestTimePossible + tsFrameLatest) / 2;
					NSLog(@"output between %lld and %lld (delta %lld), input between %lld and %lld (delta %lld) best %lld",
						tsOutEarliest, tsOutLatest, tsOutLatest-tsOutEarliest,
						tsFrameEarliest, tsFrameLatest, tsFrameLatest-tsFrameEarliest,
						bestTimeStamp);
					BOOL ok = [self.collector recordReception: self.outputCompanion.outputCode at: bestTimeStamp];
					VL_LOG_EVENT(@"reception", bestTimeStamp, self.outputCompanion.outputCode);
                    if (!ok) {
#ifdef WITH_APPKIT
                        NSAlert *alert = [NSAlert alertWithMessageText:@"Reception before transmission."
                                                         defaultButton:@"OK"
                                                       alternateButton:nil
                                                           otherButton:nil
                                             informativeTextWithFormat:@"Code %@ was transmitted at %lld, but received at %lld.\nConsult Helpfile if this error persists.",
                                          self.outputCompanion.outputCode,
                                          (long long)tsOutLatest,
                                          (long long)bestTimeStamp];
                        [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
#else
						showWarningAlert([NSString stringWithFormat:@"Received code %llu ms before it was transmitted", bestTimeStamp-tsOutLatest]);
#endif
                    }
                } else if (self.preRunning) {
                    // Compute average duration of our code detection algorithm
                    if (averageFinderDuration == 0)
                        averageFinderDuration = finderDuration;
                    else
                        averageFinderDuration = (averageFinderDuration+finderDuration)/2;
                    // Notify the detection
                    [self _prerunRecordReception: self.outputCompanion.outputCode];
                }
                // Now do a sanity check that it is greater than the previous detected code
                if (prevInputCode && [prevInputCode length] >= [self.outputCompanion.outputCode length] && [prevInputCode compare:self.outputCompanion.outputCode] >= 0) {
#ifdef WITH_APPKIT
					NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: input QR-code not monotonically increasing."
                                                     defaultButton:@"OK"
                                                   alternateButton:nil
                                                       otherButton:nil
                                         informativeTextWithFormat:@"Previous value was %@, current value is %@.\nConsult Helpfile if this error persists.",
                                            prevInputCode, self.outputCompanion.outputCode];
                    [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
#else
					showWarningAlert(@"Warning: input QR-code not monotonically increasing.");
#endif
                }
                // Now let's remember it so we don't generate "bad code" messages
                // if we detect it a second time.
                prevInputCode = self.outputCompanion.outputCode;
                prevInputCodeDetectionCount = 0;
                if (VL_DEBUG) NSLog(@"Received: %@", self.outputCompanion.outputCode);
                // Now generate a new output code.
                [self.outputCompanion triggerNewOutputValue];
			} else {
				// We have transmitted a code, but received a different one??
                if (self.running) {
                    NSLog(@"Bad data: expected %@, got %s", self.outputCompanion.outputCode, code);
#ifdef WITH_APPKIT
                    NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: received unexpected QR-code."
                                                     defaultButton:@"OK"
                                                   alternateButton:nil
                                                       otherButton:nil
                                         informativeTextWithFormat:@"Expected value was %@, received %s.\nConsult Helpfile if this error persists.",
                                      self.outputCompanion.outputCode, code];
                    [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
#else
					showWarningAlert([NSString stringWithFormat:@"Received unexpected QR-code %s", code]);
#endif
					[self.outputCompanion triggerNewOutputValue];
                } else if (self.preRunning) {
					[self _prerunRecordNoReception];
				}
			}
        } else {
             
            if (self.preRunning) {
                [self _prerunRecordNoReception];
            }
        }
#ifndef WITH_MEDIAN_TIMESTAMP
        inputStartTime = 0;
#endif
		if (self.running) {
			self.statusView.detectCount = [NSString stringWithFormat: @"%d", self.collector.count];
			self.statusView.detectAverage = [NSString stringWithFormat: @"%.3f ms ± %.3f", self.collector.average / 1000.0, self.collector.stddev / 1000.0];
            [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
		}
    }
}
@end
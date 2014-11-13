//
//  HardwareRunManager.m
//  videoLat
//
//  Created by Jack Jansen on 22/12/13.
//  Copyright 2010-2014 Centrum voor Wiskunde en Informatica. Licensed under GPL3.
//

#import "HardwareRunManager.h"
#import "PythonLoader.h"
#import "appDelegate.h"
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/clock.h>

@implementation HardwareRunManager

- (int) initialPrerunCount { return 100; }
- (int) initialPrerunDelay { return 1000; }

+ (void) initialize
{
    [BaseRunManager registerClass: [self class] forMeasurementType: @"Hardware Calibrate"];
    [BaseRunManager registerNib: @"HardwareRunManager" forMeasurementType: @"Hardware Calibrate"];

    [BaseRunManager registerClass: [self class] forMeasurementType: @"Screen Output Calibrate"];
    [BaseRunManager registerNib: @"ScreenToHardwareRunManager" forMeasurementType: @"Screen Output Calibrate"];
    // We should also ensure that the hardware protocol is actually part of the binary
    Protocol *hlp = @protocol(HardwareLightProtocol);
    if (VL_DEBUG) NSLog(@"HardwareLightProtocol = %@", hlp);
}

- (HardwareRunManager*)init
{
    self = [super init];
	if (self) {
	}
    return self;
}

- (void)awakeFromNib
{
    if ([super respondsToSelector:@selector(awakeFromNib)]) [super awakeFromNib];
    
#if 0
    // Check that the Python script has loaded correctly
	if (self.device && ![self.device respondsToSelector: @selector(available)])
		self.device = nil;
#endif
    self.statusView = self.measurementMaster.statusView;
    self.collector = self.measurementMaster.collector;
    if (self.clock == nil) self.clock = self;
    [self restart];
}

- (IBAction) deviceChanged: (id)sender
{
    lastError = nil;
    if (self.selectionView.bDevices == nil)
        return;
    if ([self.selectionView.bDevices indexOfSelectedItem] == 0)
        return;
    NSString *selectedDevice = [self.selectionView.bDevices titleOfSelectedItem];
    NSString *oldDevice = nil;
    if (self.device)
        oldDevice = [self.device deviceName];
    if (selectedDevice && oldDevice && [selectedDevice isEqualToString: oldDevice])
        return;
    
    self.device = nil;
    self.outputView.device = nil;
    
    if (selectedDevice == nil)
        return;
    
    [self _switchToDevice: selectedDevice];
}

- (void)_switchToDevice: (NSString *)selectedDevice
{
    [self.bConnected setState: 0];
    PythonLoader *pl = [PythonLoader sharedPythonLoader];
    BOOL ok = [pl loadPackageNamed: selectedDevice];
    if (!ok) {
        NSLog(@"HardwareRunManager: Programmer error: Python module %@ cannot be imported", selectedDevice);
        return;
    }
    
    Class deviceClass = NSClassFromString(selectedDevice);
    if (deviceClass == nil) {
        NSLog(@"HardwareRunManager: Programmer error: class %@ does not exist", selectedDevice);
        return;
    }
    self.device = [[deviceClass alloc] init];
    if (self.device == nil) {
        NSLog(@"HardwareRunManager: cannot allocate %@ object", deviceClass);
    }
    
    self.outputView.device = self.device;
    BOOL available = [self.device available];
    [self.bConnected setState: (int)available];
    [self.bPreRun setEnabled: available];
    [self.bRun setEnabled: NO];
    self.preRunning = NO;
    self.running = NO;
    minInputLevel = 1.0;
    maxInputLevel = 0.0;
    // This call is in completely the wrong place....
    if (!alive) {
        alive = YES;
        [self performSelectorInBackground:@selector(_periodic:) withObject:self];
    }
}

- (IBAction)selectBase: (id) sender
{
    assert(handlesInput);
    if (self.selectionView.bBase == nil) {
        NSLog(@"HardwareRunManager: bBase == nil");
        return;
    }
    NSMenuItem *baseItem = [self.selectionView.bBase selectedItem];
    NSString *baseName = [baseItem title];
    if (baseName == nil) {
        NSLog(@"HardwareRunManager: baseName == nil");
        return;
    }
    MeasurementType *baseType = self.measurementType.requires;
    MeasurementDataStore *baseStore = [baseType measurementNamed: baseName];
    if (baseStore == nil) {
        NSLog(@"HardwareRunManager: no base measurement named %@", baseName);
        return;
    }
    NSString *deviceName = baseStore.inputDevice;
    [self _switchToDevice:deviceName];
}

- (uint64_t)now
{
    UInt64 machTimestamp = mach_absolute_time();
    Nanoseconds nanoTimestamp = AbsoluteToNanoseconds(*(AbsoluteTime*)&machTimestamp);
    uint64_t timestamp = *(UInt64 *)&nanoTimestamp;
    timestamp = timestamp / 1000;
    return timestamp;
}

- (void)_periodic: (id)sender
{
    BOOL first = YES;
    BOOL outputLevelChanged = NO;
	uint64_t lastUpdateCall = 0;
    while(alive) {
        BOOL nConnected = self.device && [self.device available];
        uint64_t loopTimestamp = [self.clock now];
        @synchronized(self) {
            if (newOutputValueWanted) {
                outputTimestamp = loopTimestamp;
                outputLevel = 1-outputLevel;
                outputLevelChanged = YES;
                newOutputValueWanted = NO;
                if (VL_DEBUG) NSLog(@"HardwareRunManager: outputLevel %f at %lld", outputLevel, outputTimestamp);
            }
        }
        double nInputLevel = [self.device light: outputLevel];
        if (nInputLevel < 0) {
            [self performSelectorOnMainThread:@selector(_update:) withObject:self waitUntilDone:NO];
            continue;
        }
        
        @synchronized(self) {
			if (inputLevel > 0 && inputLevel < minInputLevel)
				minInputLevel = inputLevel;
			if (inputLevel < 1 && inputLevel > maxInputLevel)
				maxInputLevel = inputLevel;
			// We call update for a number of cases:
			// - first time through the loop
			// - device connected or disconnected
			// - input level changed
			// - output level changed
			// - maxDelay has passed since last call
            if (first || nConnected != connected || nInputLevel != inputLevel || outputLevelChanged || loopTimestamp > lastUpdateCall + maxDelay) {
                connected = nConnected;
                inputLevel = nInputLevel;
                inputTimestamp = loopTimestamp;
                [self performSelectorOnMainThread:@selector(_update:) withObject:self waitUntilDone:NO];
				lastUpdateCall = loopTimestamp;
                first = NO;
            }
        }
        outputLevelChanged = NO;
        [NSThread sleepForTimeInterval:0.001];
    }
}

- (void)_update: (id)sender
{
    @synchronized(self) {
        BOOL inputLight =(inputLevel > (maxInputLevel + minInputLevel)/2);
		BOOL outputMixed = (outputLevel == 0.5);
        BOOL outputLight = (outputLevel > 0.5);
		// Special case for some other component handling output
		if (!handlesOutput) {
			outputLight = [self.outputCompanion.outputCode isEqualToString:@"white"];
		}

        [self.bConnected setState: (connected ? NSOnState : NSOffState)];
        [self.bInputNumericValue setDoubleValue: inputLevel];
        [self.bInputValue setState: (inputLight ? NSOnState : NSOffState)];
        [self.outputView.bOutputValue setState: (outputMixed ? NSMixedState : outputLight ? NSOnState : NSOffState)];
        NSString *oldOutputCode = self.outputCode;
        if (outputMixed) {
            self.outputCode = nil;
        } else {
            self.outputCode = outputLight ? @"white" : @"black";
        }
        if (self.running && self.outputCode && (oldOutputCode == nil || ![self.outputCode isEqualToString: oldOutputCode])) {
            // We have generated a new output code. Remember it, if we are running
            [self.collector recordTransmission: outputLight? @"white": @"black" at:outputTimestamp];
        }
        if (!handlesInput) return;
        // Check for detections
		NSString *inputCode = inputLight? @"white": @"black";
        if (VL_DEBUG) NSLog(@" inputLevel %f (%f..%f) inputLight %d outputLight %d outputMixed %d", inputLevel, minInputLevel, maxInputLevel, inputLight, outputLight, outputMixed);
        if (inputLight == outputLight) {
            if (self.running) {
                if (VL_DEBUG) NSLog(@"light %d transmitted %lld received %lld delta %lld", outputLight, outputTimestamp, inputTimestamp, inputTimestamp - outputTimestamp);
                [self.collector recordReception:inputCode at:inputTimestamp];
                self.statusView.detectCount = [NSString stringWithFormat: @"%d", self.collector.count];
                self.statusView.detectAverage = [NSString stringWithFormat: @"%.3f ms ± %.3f", self.collector.average / 1000.0, self.collector.stddev / 1000.0];
                [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
				[self.outputCompanion triggerNewOutputValue];
            } else if (self.preRunning) {
				[self _prerunRecordReception: inputCode];
            }
        } else {
            // We did not detect the light level we expected
			if (self.preRunning)
				[self _prerunRecordNoReception];
        }
        NSString *msg = self.device.lastErrorMessage;
        if (msg && ![msg isEqualToString:lastError]) {
            lastError = msg;
            NSAlert *alert = [NSAlert alertWithMessageText:@"Hardware device error" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", msg];
            [alert runModal];
        }
    }
}

- (void)_prerunRecordReception: (NSString *)code
{
	prerunMoreNeeded--;
	if (1 || VL_DEBUG) NSLog(@"prerunRecordReception %@ preRunMoreMeeded=%d\n", code, prerunMoreNeeded);
	self.statusView.detectCount = [NSString stringWithFormat: @"%d more", prerunMoreNeeded];
	self.statusView.detectAverage = [NSString stringWithFormat: @"%.2f .. %.2f", minInputLevel, maxInputLevel];
	[self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
	if (prerunMoreNeeded == 0) {
		outputLevel = 0.5;
		self.statusView.detectCount = @"";
		//self.statusView.detectAverage = @"";
		[self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
		[self performSelectorOnMainThread: @selector(stopPreMeasuring:) withObject: self waitUntilDone: NO];
		return;
	}
	[self.outputCompanion triggerNewOutputValue];
}

- (void) _prerunRecordNoReception
{
	assert(self.preRunning);
	// Check that we have waited long enough
	if ([self.clock now] < outputTimestamp + maxDelay)
		return;
	assert(maxDelay);
	maxDelay *= 2;
	prerunMoreNeeded = self.initialPrerunCount;
	if (1 || VL_DEBUG) NSLog(@"prerunRecordNoReception, maxDelay is now %lld", maxDelay);
	self.statusView.detectCount = [NSString stringWithFormat: @"%d more", prerunMoreNeeded];
	self.statusView.detectAverage = [NSString stringWithFormat: @"%.2f .. %.2f", minInputLevel, maxInputLevel];
	[self.outputCompanion triggerNewOutputValue];
}


- (void)triggerNewOutputValue
{
    if (!self.running && !self.preRunning) {
        // Idle, show intermediate value
        outputLevel = 0.5;
    } else {
        // If we are running or prerunning we only want 0 and 1.
        if (outputLevel > 0 && outputLevel < 1)
            outputLevel = 0;
    }
	newOutputValueWanted = YES;
    if (VL_DEBUG) NSLog(@"triggerNewOutputValue called");
}

#if 0
- (IBAction)startPreMeasuring: (id)sender
{
	@synchronized(self) {
        assert(handlesInput);
        // XXXX No need to check base measuremen??
        [self.bPreRun setEnabled: NO];
        [self.bRun setEnabled: NO];
        if (self.statusView) {
            [self.statusView.bStop setEnabled: NO];
        }
        // Do actual prerunning
        prerunMoreNeeded = self.initialPrerunCount;
        if (!handlesOutput) {
            BOOL ok = [self.outputCompanion companionStartPreMeasuring];
            if (!ok) return;
        }
        self.preRunning = YES;
        [self.outputCompanion triggerNewOutputValue];
    }
}
#endif

- (IBAction)stopPreMeasuring: (id)sender
{
#if 1
	[super stopPreMeasuring: sender];
	outputLevel = 0.5;
#else
	@synchronized(self) {
		self.preRunning = NO;
        if (!handlesOutput)
            [self.outputCompanion companionStopPreMeasuring];
        outputLevel = 0.5;
        newOutputValueWanted = NO;
		[self.bPreRun setEnabled: NO];
		[self.bRun setEnabled: YES];
		if (!self.statusView) {
			// XXXJACK Make sure statusview is active/visible
		}
		[self.statusView.bStop setEnabled: NO];
	}
#endif
}

#if 0
- (IBAction)startMeasuring: (id)sender
{
    @synchronized(self) {
		[self.bPreRun setEnabled: NO];
		[self.bRun setEnabled: NO];
		if (!self.statusView) {
			// XXXJACK Make sure statusview is active/visible
		}
		[self.statusView.bStop setEnabled: YES];
        self.running = YES;
        if (!handlesOutput)
            [self.outputCompanion companionStartMeasuring];
        [self.collector startCollecting: self.measurementType.name input: self.device.deviceID name: self.device.deviceName output: self.device.deviceID name: self.device.deviceName];
        [self.outputCompanion triggerNewOutputValue];
    }
}
#endif

- (void)restart
{
    @synchronized(self) {
		if (self.measurementType == nil) return;
        assert(handlesInput);
        // Pre-select the correct device. Sometimes through device popup, sometimes through base
        if (self.selectionView.bDevices) {
            [self deviceChanged: self];
        } else if (self.selectionView.bBase) {
            [self selectBase:self];
        }
        
        if (self.device == nil) {
            NSLog(@"HardwareRunManager: no hardware device available");
            [self.bPreRun setEnabled: NO];
            [self.bRun setEnabled: NO];
            if (self.statusView) {
                [self.statusView.bStop setEnabled: NO];
            }
            return;
        }
		[super restart];
		outputLevel = 0.5;
		if (!alive) {
            alive = YES;
            [self performSelectorInBackground:@selector(_periodic:) withObject:self];
        }
    }
}

- (void) companionRestart
{
	[super companionRestart];
	outputLevel = 0.5;
	if (!alive) {
		alive = YES;
		[self performSelectorInBackground:@selector(_periodic:) withObject:self];
	}
}

- (void)stop
{
	alive = NO;
}

- (CIImage *)newOutputStart
{
	[NSException raise:@"HardwareRunManager" format:@"Must override newOutputStart in subclass"];
	return nil;
}

- (void)newOutputDone
{
	[NSException raise:@"HardwareRunManager" format:@"Must override newOutputDone in subclass"];
}

- (void)setFinderRect: (NSRect)theRect
{
	[NSException raise:@"HardwareRunManager" format:@"Must override setFinderRect in subclass"];
}


- (void)newInputStart
{
	[NSException raise:@"HardwareRunManager" format:@"Must override newInputStart in subclass"];
}

- (void)newInputStart: (uint64_t)timestamp
{
	[NSException raise:@"HardwareRunManager" format:@"Must override newInputStart: in subclass"];
}


- (void)newInputDone
{
	[NSException raise:@"HardwareRunManager" format:@"Must override newInputDone in subclass"];
}


- (void) newInputDone: (void*)buffer
                width: (int)w
               height: (int)h
               format: (const char*)formatStr
                 size: (int)size
{
	[NSException raise:@"HardwareRunManager" format:@"Must override newInputDone in subclass"];
}
@end

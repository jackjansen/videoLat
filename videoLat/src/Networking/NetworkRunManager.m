//
//  NetworkRunManager.m
//  videoLat
//
//  Created by Jack Jansen on 24/11/13.
//  Copyright 2010-2014 Centrum voor Wiskunde en Informatica. Licensed under GPL3.
//

#import "NetworkRunManager.h"

///
/// How many times do we want to get a message that the prerun code has been detected?
/// This define is used on the master side, and stops the prerun sequence. It should be high enough that we
/// have a reasonable measurement of the RTT and the clock difference.
#define PRERUN_COUNT 128

///
/// How often do we send a message if we have not received a QR-code (in microseconds)?
/// This define is used on the slave side, it keeps the connection open and the RTT clock difference.
/// In addition, it will trigger the master side to emit a fresh QR code if the current QR code hasn't been
/// detected for some time.
#define HEARTBEAT_INTERVAL 1000000LL

///
/// What is the maximum time we try to detect a QR-code (in microseconds)?
/// This define is used on the master side, to trigger a new QR code if the old one was never detected, for some reason.
#define MAX_DETECTION_INTERVAL 5000000LL


///
/// Helper function: get an uint64_t from a dictionary item, if it exists
static uint64_t getTimestamp(NSDictionary *data, NSString *key)
{
    id timeObject = [data objectForKey: key];
    if (timeObject == nil) {
        NSLog(@"No key %@ in %@", key, data);
        return 0;
    }
    if ([timeObject respondsToSelector:@selector(unsignedLongLongValue)]) {
        return [timeObject unsignedLongLongValue];
    }
    uint64_t timestamp;
    if (sscanf([timeObject UTF8String], "%lld", &timestamp) == 1) {
        return timestamp;
    }
    NSLog(@"Cannot convert to uint64: %@", timeObject);
    return 0;
}

@interface SimpleRemoteClock : NSObject  <RemoteClockProtocol> {
	int64_t localTimeToRemoteTime;
    uint64_t rtt;
    bool initialized;
};
- (uint64_t)remoteNow: (uint64_t) now;
- (void)remote: (uint64_t)remote between: (uint64_t)start and: (uint64_t) finish;
- (uint64_t)rtt;
@end

@implementation SimpleRemoteClock
- (SimpleRemoteClock *) init
{
	self = [super init];
	localTimeToRemoteTime = 0;
    initialized = false;
	return self;
}

- (uint64_t)remoteNow: (uint64_t) now
{
    if (!initialized) return 0;
	return now + localTimeToRemoteTime;
}

- (void)remote: (uint64_t)remote between: (uint64_t)start and: (uint64_t) finish
{
    rtt = finish-start;
	uint64_t mid = (finish+start)/2;
	localTimeToRemoteTime = (int64_t)remote - (int64_t)mid;
    initialized = true;
}

- (uint64_t) rtt
{
    return rtt;
}

@end

@implementation NetworkRunManager

+ (void)initialize
{
    // Unsure whether we need to register our class?
#if 0
    [BaseRunManager registerClass: [self class] forMeasurementType: @"Networking"];
    // No nib is registered...
#endif
    // We also register ourselves for send-only, as a slave. At the very least we must make
    // sure the nibfile is registered...
    [BaseRunManager registerClass: [self class] forMeasurementType: @"Video Transmission (Master/Server)"];
    [BaseRunManager registerNib: @"MasterSenderRun" forMeasurementType: @"Video Transmission (Master/Server)"];
}

- (NetworkRunManager *) init
{
    self = [super init];
    if (self) {
        handlesInput = NO;
        handlesOutput = NO;
    }
    return self;
}

- (void) awakeFromNib
{
    if ([super respondsToSelector:@selector(awakeFromNib)]) [super awakeFromNib];
    self.statusView = self.measurementMaster.statusView;
    assert(self.clock);
    // If we don't handle output (i.e. output is going through video) we start the server and
    // report the port number
    if (!handlesOutput) {
        assert(self.protocol == nil);
        self.protocol = [[NetworkProtocolServer alloc] init];
        self.protocol.delegate = self;
        self.selectionView.bOurPort.intValue = self.protocol.port;
        self.collector = self.measurementMaster.collector;
    }
    // If we handle output (i.e. we get video from the camera and report QR codes to the server)
    // we only allocate a clock, the client-side of the network connection will be created once we
    // know ip/port (which will come in encoded as a QR-code)
    if (handlesOutput) {
        if (self.remoteClock == nil) {
            _keepRemoteClock = [[SimpleRemoteClock alloc] init];
            self.remoteClock = _keepRemoteClock;
        }
    }
}


#if 0

- (void)terminate
{
	BaseRunManager *ic = self.inputCompanion, *oc = self.outputCompanion;
	self.inputCompanion = nil;
	self.outputCompanion = nil;
	if (ic) [ic terminate];
	if (oc) [oc terminate];
	self.collector = nil;
	self.statusView = nil;
	self.measurementMaster = nil;
	
}

- (void) dealloc
{
}
#endif

- (void)stop
{
	//[NSException raise:@"NetworkRunManager" format:@"Must override stop in subclass"];
    NSLog(@"NetworkRunManager.stop. Unsure what to do...");
}

- (void)triggerNewOutputValue
{
	[NSException raise:@"NetworkRunManager" format:@"Must override triggerNewOutputValue in subclass"];
    assert(handlesOutput);
}

- (CIImage *)newOutputStart
{
	[NSException raise:@"NetworkRunManager" format:@"Must override newOutputStart in subclass"];
    assert(handlesOutput);
	return nil;
}

- (void)newOutputDone
{
	[NSException raise:@"NetworkRunManager" format:@"Must override newOutputDone in subclass"];
    assert(handlesOutput);
}

- (void)setFinderRect: (NSRect)theRect
{
	[NSException raise:@"NetworkRunManager" format:@"Must override setFinderRect in subclass"];
}


- (void)newInputStart
{
	[NSException raise:@"NetworkRunManager" format:@"Must override newInputStart in subclass"];
}

- (void) newInputStart:(uint64_t)timestamp
{
    @synchronized(self) {
        assert(handlesInput);
        inputStartTime = timestamp;
        
        // Sanity check: times should be monotonically increasing
        if (prevInputStartTime && prevInputStartTime >= inputStartTime) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: input clock not monotonically increasing."
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"Previous value was %lld, current value is %lld.\nConsult Helpfile if this error persists.",
                              (long long)prevInputStartTime,
                              (long long)inputStartTime];
            [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
        }
    }
}


- (void)newInputDone
{
    if (!self.running)
        return;
    
    uint64_t now = [self.clock now];
    if (now - lastDetectionReceivedTime < MAX_DETECTION_INTERVAL)
        return;
    
    // Nothing detected for a long time. Record this fact, and generate a new code.
    BOOL ok = [self.collector recordReception: @"nothing" at: now];
    assert(!ok);
    [self.outputCompanion triggerNewOutputValue];
    // This isn't true, but works well:
    lastDetectionReceivedTime = now;
}

///
/// This version of newInputDone is used when running in master mode, it signals a reception
/// by the network module
///
- (void) newInputDone: (NSString *)code count: (int)count at: (uint64_t) timestamp
{
    lastDetectionReceivedTime = timestamp;
    if (self.preRunning) {
        if (prerunCode == nil || ![prerunCode isEqualToString:code]) {
            NSLog(@"Peer sent us code %@ but we expected %@", code, prerunCode);
            return;
        }
        if (count < PRERUN_COUNT) {
            self.statusView.detectCount = [NSString stringWithFormat: @"%d", count];
        } else {
            self.statusView.detectCount = @"";
            [self stopPreMeasuring: self];
        }
        [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
    }
    if (self.running) {
        NSLog(@"Running, received code %@", code);
        if (self.outputCompanion.outputCode == nil) {
            if (VL_DEBUG) NSLog(@"newInputDone called, but no output code yet\n");
            return;
        }
    
        // Compare the code to what was expected.
        if (count > 1) {
            NSLog(@"Received old output code again: %@, %d times", code, count);
            return;
        if ((count % 128) == 0) {
                NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: no new QR code generated."
                                                 defaultButton:@"OK"
                                               alternateButton:nil
                                                   otherButton:nil
                                     informativeTextWithFormat:@"QR-code %@ detected %d times. Generating new one.",
                                  prevInputCode, prevInputCodeDetectionCount];
                [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
                [self.outputCompanion triggerNewOutputValue];
            }
        } else if ([code isEqualToString: self.outputCompanion.outputCode]) {
            // Correct code found.
            
            // Let's first report it.
            BOOL ok = [self.collector recordReception: self.outputCompanion.outputCode at: timestamp];
            if (!ok) {
                NSAlert *alert = [NSAlert alertWithMessageText:@"Reception before transmission."
                                                 defaultButton:@"OK"
                                               alternateButton:nil
                                                   otherButton:nil
                                     informativeTextWithFormat:@"Code %@ was transmitted at (unknown), but received at %lld.\nConsult Helpfile if this error persists.",
                                  self.outputCompanion.outputCode,
                                  (long long)timestamp];
                [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
            }

            // Now do a sanity check that it is greater than the previous detected code
            if (prevInputCode && [prevInputCode length] >= [self.outputCompanion.outputCode length] && [prevInputCode compare:self.outputCompanion.outputCode] >= 0) {
                NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: input QR-code not monotonically increasing."
                                                 defaultButton:@"OK"
                                               alternateButton:nil
                                                   otherButton:nil
                                     informativeTextWithFormat:@"Previous value was %@, current value is %@.\nConsult Helpfile if this error persists.",
                                  prevInputCode, self.outputCompanion.outputCode];
                [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
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
            NSLog(@"Bad data: expected %@, got %@", self.outputCompanion.outputCode, code);
            NSAlert *alert = [NSAlert alertWithMessageText:@"Warning: received unexpected QR-code."
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"Expected value was %@, received %@.\nConsult Helpfile if this error persists.",
                              self.outputCompanion.outputCode, code];
            [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
            [self.outputCompanion triggerNewOutputValue];
        }
        self.statusView.detectCount = [NSString stringWithFormat: @"%d", self.collector.count];
        self.statusView.detectAverage = [NSString stringWithFormat: @"%.3f ms ± %.3f", self.collector.average / 1000.0, self.collector.stddev / 1000.0];
        [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
    }
}

///
/// This version of newInputDone is used when running in slave mode, it signals that the camera
/// has captured an input.
///
- (void) newInputDone: (void*)buffer width: (int)w height: (int)h format: (const char*)formatStr size: (int)size
{
    @synchronized(self) {
        assert(handlesInput);
        if (inputStartTime == 0) {
            NSLog(@"newInputDone called, but inputStartTime==0\n");
            return;
        }

		assert(self.finder);
        char *ccode = [self.finder find: buffer width: w height: h format: formatStr size:size];
        BOOL foundQRcode = (ccode != NULL);
        if (foundQRcode) {
			NSString *code = [NSString stringWithUTF8String: ccode];

            if (prevInputCode && [code isEqualToString: prevInputCode]) {
                // We have seen this code before. Only increment the detection count.
                prevInputCodeDetectionCount++;
				//NSLog(@"Found %d copies since %lld (%lld) of %@", prevInputCodeDetectionCount, prevInputStartTime, prevInputStartTimeRemote, prevInputCode);
            } else {
                // We found a new QR code (at least, different from the last detection).
                // Remember when we first detected it, and then see what we should do with it.
                prevInputCode = code;
                prevInputCodeDetectionCount = 1;
                prevInputStartTime = inputStartTime;
				prevInputStartTimeRemote = [self.remoteClock remoteNow:prevInputStartTime];
                NSLog(@"Found QR-code: %@", code);
                
                // If it is a URL it is probably a prerun QR-code (which is a URL, so that if
                // the receiver isn't running videoLat but an ordinary QR-code app they will be sent
                // to the website where they can download videoLat).
                // The prerun QR-code contains contact information for the server running on the
                // master copy of videoLat.
				NSURLComponents *urlComps = [NSURLComponents componentsWithString: code];
				if (urlComps) {
					if ([urlComps.path isEqualToString: @"/landing"] && self.protocol == nil) {
						NSString *query = urlComps.query;
						NSLog(@"Server info: %@", query);
                        const char *cQuery = [query UTF8String];
                        char ipBuffer[128];
                        int port;
                        int rv = sscanf(cQuery, "ip=%126[^&]&port=%d", ipBuffer, &port);
                        if (rv != 2) {
                            self.outputView.bPeerStatus.stringValue = [NSString stringWithFormat: @"Unexcepted URL: %@", code];
                        } else {
                            NSString *ipAddress = [NSString stringWithUTF8String:ipBuffer];
                            self.outputView.bPeerIPAddress.stringValue = ipAddress;
                            self.outputView.bPeerPort.intValue = port;
                            self.outputView.bPeerStatus.stringValue = @"Connecting...";
                            
                            self.protocol = [[NetworkProtocolClient alloc] initWithPort:port host: ipAddress];
                            if (self.protocol == nil) {
                                self.outputView.bPeerStatus.stringValue = @"Failed to connect";
                            } else {
                                self.protocol.delegate = self;
                                self.outputView.bPeerStatus.stringValue = @"Connected";
                            }
                        }
					}
				}
                
            }
            // All QR codes are sent back to the master, assuming we have a connection to the master already.
            if (self.protocol) {
                uint64_t now = [self.clock now];
                uint64_t remoteNow = [self.remoteClock remoteNow: now];
                uint64_t rtt = [self.remoteClock rtt];
                NSDictionary *msg = @{
                                      @"code" : code,
                                      @"masterDetectTime": [NSString stringWithFormat:@"%lld", prevInputStartTimeRemote],
                                      @"slaveTime" : [NSString stringWithFormat:@"%lld", now],
                                      @"masterTime" : [NSString stringWithFormat:@"%lld", remoteNow],
                                      @"count" : [NSString stringWithFormat:@"%d", prevInputCodeDetectionCount],
                                      @"rtt" : [NSString stringWithFormat:@"%lld", rtt]
                                      };
                [self.protocol send: msg];
                lastMessageSentTime = now;
            }
        } else {
             // No QR-code detected. Send a heartbeat every second.
            uint64_t now = [self.clock now];
            if (self.protocol && now - lastMessageSentTime > HEARTBEAT_INTERVAL) {
                uint64_t remoteNow = [self.remoteClock remoteNow: now];
                uint64_t rtt = [self.remoteClock rtt];
                NSDictionary *msg = @{
                                      @"slaveTime" : [NSString stringWithFormat:@"%lld", now],
                                      @"masterTime" : [NSString stringWithFormat:@"%lld", remoteNow],
                                      @"rtt" : [NSString stringWithFormat:@"%lld", rtt]
                                      };
                [self.protocol send: msg];
                lastMessageSentTime = now;
            }
        }
        inputStartTime = 0;
#if 0
        if (self.running) {
            self.statusView.detectCount = [NSString stringWithFormat: @"%d", self.collector.count];
            self.statusView.detectAverage = [NSString stringWithFormat: @"%.3f ms ± %.3f", self.collector.average / 1000.0, self.collector.stddev / 1000.0];
            [self.statusView performSelectorOnMainThread:@selector(update:) withObject:self waitUntilDone:NO];
        }
#endif
    }
}

- (void)newInputDone: (void*)buffer
                size: (int)size
            channels: (int)channels
                  at: (uint64_t)timestamp
{
	[NSException raise:@"NetworkRunManager" format:@"Must override newInputDone in subclass"];
}

- (void)received:(NSDictionary *)data from: (id)connection
{
    if (handlesOutput) {
        // This code runs in the slave (video receiver, network transmitter)
        assert(self.outputView);
        //NSLog(@"received %@ from %@ (our protocol %@)", data, connection, self.protocol);
        uint64_t slaveTimestamp = getTimestamp(data, @"lastSlaveTime");
        uint64_t masterTimestamp = getTimestamp(data, @"lastMasterTime");
        if (slaveTimestamp && masterTimestamp) {
            uint64_t now = [self.clock now];
            [self.remoteClock remote:masterTimestamp between:slaveTimestamp and:now];
            self.outputView.bPeerRTT.intValue = (int)([self.remoteClock rtt]/1000);
            //NSLog(@"master %lld in %lld..%lld (delta=%lld)", masterTimestamp, slaveTimestamp, now, [self.remoteClock rtt]);
        } else {
            NSLog(@"unexpected data from master: %@", data);
        }
    } else {
        // This code runs in the master (video sender, network receiver)
        assert(self.selectionView);
        self.selectionView.bOurStatus.stringValue = @"Connected";
        //NSLog(@"received %@ from %@ (our protocol %@)", data, connection, self.protocol);
        
        uint64_t slaveTimestamp = getTimestamp(data, @"slaveTime");
        uint64_t masterTimestamp = getTimestamp(data, @"masterTime");
        uint64_t rtt = getTimestamp(data, @"rtt");
        uint64_t count = getTimestamp(data, @"count");
        NSString *code = [data objectForKey: @"code"];
        
        if (slaveTimestamp) {
            uint64_t now = [self.clock now];
            NSDictionary *msg = @{
                                  @"lastMasterTime": [NSString stringWithFormat:@"%lld", now],
                                  @"lastSlaveTime" : [NSString stringWithFormat:@"%lld", slaveTimestamp],
                                  };
            [self.protocol send: msg];
        }
        if (rtt) {
            self.selectionView.bRTT.intValue = (int)(rtt/1000);
        }
        
        if(code && masterTimestamp) {
            [self newInputDone: code count: (int)count at: masterTimestamp];
        } else {
            [self newInputDone];
        }
    }
}

- (void)disconnected:(id)connection
{
    NSLog(@"received disconnect from %@ (our protocol %@)", connection, self.protocol);
    self.protocol = nil;
    if (self.outputView) {
        self.outputView.bPeerStatus.stringValue = @"Disconnected";
    }
    if (self.selectionView) {
        self.selectionView.bOurStatus.stringValue = @"Disconnected";
    }
    if (self.preRunning)
        [self stopPreMeasuring: self];

}

- (NSString *)genPrerunCode
{
    assert (self.protocol);
    if (prerunCode == nil) {
        prerunCode = [NSString stringWithFormat:@"http://videolat.org/landing?ip=%@&port=%d", self.protocol.host, self.protocol.port];
    }
    return prerunCode;
}

- (IBAction)startPreMeasuring: (id)sender
{
    @synchronized(self) {
        assert(handlesInput);
        [self.selectionView.bPreRun setEnabled: NO];
        [self.selectionView.bRun setEnabled: NO];
        if (self.statusView) {
            [self.statusView.bStop setEnabled: NO];
        }
        // Do actual prerunning
//        prerunMoreNeeded = PRERUN_COUNT;
        if (!handlesOutput) {
            BOOL ok = [self.outputCompanion companionStartPreMeasuring];
            if (!ok) return;
        }
        self.preRunning = YES;
        [self.outputCompanion triggerNewOutputValue];
    }
}

- (IBAction)stopPreMeasuring: (id)sender
{
    @synchronized(self) {
        assert(handlesInput);
        self.preRunning = NO;
        if (!handlesOutput)
            [self.outputCompanion companionStopPreMeasuring];
//        outputLevel = 0.5;
//        newOutputValueWanted = NO;
        [self.selectionView.bPreRun setEnabled: NO];
        [self.selectionView.bRun setEnabled: YES];
        if (!self.statusView) {
            // XXXJACK Make sure statusview is active/visible
        }
        [self.statusView.bStop setEnabled: NO];
        [self.outputCompanion triggerNewOutputValue];
    }
}

- (IBAction)startMeasuring: (id)sender
{
    @synchronized(self) {
        [self.selectionView.bPreRun setEnabled: NO];
        [self.selectionView.bRun setEnabled: NO];
        if (!self.statusView) {
            // XXXJACK Make sure statusview is active/visible
        }
        [self.statusView.bStop setEnabled: YES];
        self.running = YES;
        if (!handlesOutput)
            [self.outputCompanion companionStartMeasuring];
//  XXXJACK enable?      [self.collector startCollecting: self.measurementType.name input: self.device.deviceID name: self.device.deviceName output: self.device.deviceID name: self.device.deviceName];
        [self.outputCompanion triggerNewOutputValue];
    }
}

@end
#import "VideoInput.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/clock.h>

@implementation VideoInputView
@synthesize delegate;
@synthesize visibleButton;

- (IBAction)visibleChanged: (id) sender
{
    [self setHidden: ([sender state] == NSOffState)];
}

- (void)dealloc
{
}

- (void)setHidden: (BOOL) onOff
{
    if (onOff)
        [visibleButton setState:NSOffState];
    else
        [visibleButton setState:NSOnState];
    [super setHidden: onOff];
}

- (void)mouseDown: (NSEvent *)theEvent
{
	downPoint = [theEvent locationInWindow];
	if (VL_DEBUG) NSLog(@"Mouse down (%d,%d)\n", (int)downPoint.x, (int)downPoint.y);
}

- (void)mouseUp: (NSEvent *)theEvent
{
	NSPoint upPoint = [theEvent locationInWindow];
	if (VL_DEBUG) NSLog(@"Mouse up (%d,%d)\n", (int)upPoint.x, (int)upPoint.y);
	NSRect frame = [self frame];
    float max_y = upPoint.y;
    if (downPoint.y > max_y) max_y = downPoint.y;
	float top = frame.size.height - max_y;
	float height = abs(upPoint.y - downPoint.y);
	float left = upPoint.x;
    if (downPoint.x < left) left = downPoint.x;
	float width = abs(upPoint.x - downPoint.x);
	NSRect r = {{left, top}, {width, height}};
	[[self delegate] focusRectSelected: r];
}

@end

@implementation VideoInput
@synthesize deviceID;
@synthesize deviceName;

- (VideoInput *)init
{
    self = [super init];
    if (self) {
        outputCapturer = nil;
        deviceID = nil;
        sampleBufferQueue = dispatch_queue_create("Sample Queue", DISPATCH_QUEUE_SERIAL);
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 1080
		if (CMClockGetHostTimeClock != NULL) {
			clock = CMClockGetHostTimeClock();
		}
#endif
        epoch = 0;
#ifdef WITH_STATISTICS
		firstTimeStamp = 0;
		lastTimeStamp = 0;
		nFrames = 0;
		nEarlyDrops = 0;
		nLateDrops = 0;
#endif
    }
    return self;
}

- (void)dealloc
{
	[self stop];
}

- (void) awakeFromNib
{    
    // Setup for callbacks
    [self.selfView setDelegate: self];

	if (VL_DEBUG) NSLog(@"Devices: %@\n", [self deviceNames]);
}

- (uint64_t)now
{
    UInt64 timestamp;
#if 0 && __MAC_OS_X_VERSION_MAX_ALLOWED >= 1080
    if (clock) {
        CMTime timestampCMT = CMClockGetTime(clock);
        timestampCMT = CMTimeConvertScale(timestampCMT, 1000000, kCMTimeRoundingMethod_Default);
        timestamp = timestampCMT.value;
    } else
#endif
	{
#ifdef USE_MACH_ABSOLUTE_TIME
        UInt64 machTimestamp = mach_absolute_time();
        Nanoseconds nanoTimestamp = AbsoluteToNanoseconds(*(AbsoluteTime*)&machTimestamp);
        timestamp = *(UInt64 *)&nanoTimestamp;
        timestamp = timestamp / 1000;
#else
		clock_serv_t cclock;
		mach_timespec_t mts;

		host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &cclock);
		clock_get_time(cclock, &mts);
		mach_port_deallocate(mach_task_self(), cclock);
		timestamp = ((UInt64)mts.tv_sec*1000000LL) + mts.tv_nsec/1000LL;
#endif
    }
    return timestamp - epoch;
}

- (void) stop
{
	outputCapturer = nil;
    if (selfLayer) [selfLayer removeFromSuperlayer];
	selfLayer = nil;
	if (session) {
        [session stopRunning];
    }
	session = nil;
    //dispatch_release(sampleBufferQueue);
    sampleBufferQueue = nil;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 1080
	clock = nil;
#endif
#ifdef WITH_STATISTICS
	float deltaT = (lastTimeStamp-firstTimeStamp) / 1000000.0;
	NSLog(@"Captured %.0f seconds, %d frames, %3.1f fps, %d too-early drops, %d too-late drops",
		deltaT, nFrames, nFrames/deltaT, nEarlyDrops, nLateDrops);
#endif
}

- (bool)available
{
	return session != nil && outputCapturer != nil;
}

- (NSArray*) deviceNames
{
	NSMutableArray *rv = [NSMutableArray arrayWithCapacity:128];
	/* First add the default Video input device */
	AVCaptureDevice *d = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if (d) [rv addObject: [d localizedName]]; 
	/* Next the default muxed device */
	d = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeMuxed];
	if (d) [rv addObject: [d localizedName]];
	/* Next, all video devices */
	NSArray *devs = [AVCaptureDevice devicesWithMediaType: AVMediaTypeVideo];
	for(d in devs) {
		NSString *name = [d localizedName];
		if ([rv indexOfObject: name] == NSNotFound)
			[rv addObject:name];
	}
	/* Finally, all muxed devices */
	devs = [AVCaptureDevice devicesWithMediaType: AVMediaTypeMuxed];
	for (d in devs) {
		NSString *name = [d localizedName];
		if ([rv indexOfObject: name] == NSNotFound)
			[rv addObject:name];
	}
	if ([rv count] == 0) {
		NSRunAlertPanel(
                        @"Warning",
                        @"No suitable video input device found, reception disabled.",
                        nil, nil, nil);
	}
	return rv;
}

- (BOOL)switchToDeviceWithName: (NSString *)name
{
    if (VL_DEBUG) NSLog(@"Switching to device %@\n", name);
	AVCaptureDevice* dev = [self _deviceWithName:name];
    if (dev == nil)
        return NO;
	[self _switchToDevice:dev];
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"Camera"];
    return YES;
}

- (void)_switchToDevice: (AVCaptureDevice*)dev
{
	deviceID = [dev modelID];
	deviceName = [dev localizedName];
    // Delete old session, if needed
	outputCapturer = nil;
    if (selfLayer) [selfLayer removeFromSuperlayer];
	if (session) {
        [session stopRunning];
    }
	session = nil;
    
	//Create the AV capture session
	session = [[AVCaptureSession alloc] init];
    
    // This code not enabled yet, because I don't have a camera that supports it:-)
    if ([dev lockForConfiguration: nil]) {
        // Set focus/exposure/flash, if device supports it
        if ([dev isFocusPointOfInterestSupported] && [dev isFocusModeSupported:AVCaptureFocusModeLocked] ) {
            if (VL_DEBUG) NSLog(@"Device supports focus lock\n");
        }
        if ([dev isTorchModeSupported: AVCaptureTorchModeOff]) {
            if (VL_DEBUG) NSLog(@"Device supports torch-off\n");
            dev.torchMode = AVCaptureTorchModeOff;
        }
        if ([dev isExposurePointOfInterestSupported] && [dev isExposureModeSupported:AVCaptureExposureModeLocked] ) {
            if (VL_DEBUG) NSLog(@"Device supports exposure lock\n");
        }
		// XXXJACK set max frame duration
		NSArray *supportedFrameRates = dev.activeFormat.videoSupportedFrameRateRanges;
		AVFrameRateRange *activeRange = [supportedFrameRates objectAtIndex:0];
		CMTime activeMinDuration = activeRange.minFrameDuration;
		dev.activeVideoMinFrameDuration = activeMinDuration;

		[dev unlockForConfiguration];
    }
    if (VL_DEBUG) NSLog(@"Finished looking at device capabilities\n");
	/* Create a QTKit input for the session using the iSight Device */
    NSError *error;
	AVCaptureDeviceInput *myInput = [AVCaptureDeviceInput deviceInputWithDevice:dev error:&error];
	if (error) {
        NSAlert *alert = [NSAlert alertWithError: error];
        [alert runModal];
        return;
    }
    
	/* Create a capture session for the live vidwo and add inputs get the ball rolling etc */
	[session addInput:myInput];
    if ([session canSetSessionPreset: AVCaptureSessionPreset640x480]) {
        [session setSessionPreset: AVCaptureSessionPreset640x480];
    } else {
        NSLog(@"Warning: Cannot set capture session to 640x480\n");
    }
    // XXXX On 10.9, get AVCaptureInputPort from session, get its clock, and use it

    /* Create the video capture output, and let us be its delegate */
    outputCapturer = [[AVCaptureVideoDataOutput alloc] init];
	outputCapturer.alwaysDiscardsLateVideoFrames = YES;
	[outputCapturer setSampleBufferDelegate: self queue:sampleBufferQueue];
    [session addOutput: outputCapturer];
	// XXXJACK Should catch AVCaptureSessionRuntimeErrorNotification

    if(self.selfView) {
        selfLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
        selfLayer.frame = NSRectToCGRect(self.selfView.bounds);
        [self.selfView setWantsLayer: YES];
        [self.selfView.layer addSublayer: selfLayer];
        [self.selfView setHidden: NO];
    }
    
	if (1 || VL_DEBUG) NSLog(@"Camera format: %@ %@ %@", dev.activeFormat.mediaType, dev.activeFormat.formatDescription, dev.activeFormat.videoSupportedFrameRateRanges);

	/* Let the video madness begin */
	capturing = NO;
	epoch = 0;
#ifdef WITH_STATISTICS
	firstTimeStamp = 0;
	lastTimeStamp = 0;
	nFrames = 0;
	nEarlyDrops = 0;
	nLateDrops = 0;
#endif
	[self.manager restart];
	[session startRunning];
}

- (AVCaptureDevice*)_deviceWithName: (NSString*)name
{
#if 1
	NSArray *devs = [AVCaptureDevice devicesWithMediaType: AVMediaTypeVideo];
	AVCaptureDevice *d;
	for(d in devs) {
		NSString *dn = [d localizedName];
		if ([dn compare: name] == NSOrderedSame)
			return d;
	}
	devs = [AVCaptureDevice devicesWithMediaType: AVMediaTypeMuxed];
	for (d in devs) {
		NSString *dn = [d localizedName];
		if ([dn compare: name] == NSOrderedSame)
			return d;
	}
    return nil;
#else
	return [AVCaptureDevice deviceWithUniqueID:name];
#endif
}

- (void) startCapturing: (BOOL) showPreview
{
#if 0
    // Lock focus and exposure, if supported
#endif
    // Hide preview
    if (!showPreview) [self.selfView setHidden: YES];
	capturing = YES;
}

- (void) stopCapturing
{
    [self.selfView setHidden: NO];
	capturing = NO;
}


#ifdef NOTYETFORAVFOUNDATION

- (CIImage *)view:(QTCaptureView *)view willDisplayImage:(CIImage *)image
{
	NSRect wbounds = [view previewBounds];
	CGRect ibounds = [image extent];
	xFactor = ibounds.size.width / wbounds.size.width;
	yFactor = ibounds.size.height / wbounds.size.height;

    // Noneed to process, show original image.
    return nil;
}
#endif
- (void)focusRectSelected: (NSRect)theRect
{
	theRect.origin.x *= xFactor;
	theRect.origin.y *= yFactor;
	theRect.size.width *= xFactor;
	theRect.size.height *= yFactor;
	if (VL_DEBUG) NSLog(@"FocusRectSelected %d, %d, %d, %d\n", (int)theRect.origin.x, (int)theRect.origin.y, (int)theRect.size.width, (int)theRect.size.height);
	[self.manager setFinderRect: theRect];
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
    fromConnection:(AVCaptureConnection *)connection;
{
    if( !CMSampleBufferDataIsReady(sampleBuffer) )
    {
        NSLog( @"sample buffer is not ready. Skipping sample" );
        return;
    }
    CMTime timestampCMT = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    timestampCMT = CMTimeConvertScale(timestampCMT, 1000000, kCMTimeRoundingMethod_Default);
    UInt64 timestamp = timestampCMT.value;
    UInt64 now_timestamp = [self now];
#ifdef WITH_STATISTICS
	if (firstTimeStamp == 0) firstTimeStamp = timestamp;
	lastTimeStamp = timestamp;
	nFrames++;
#endif
#if 1
	// Complain about preposterous timestamps
	if (timestamp > now_timestamp) {
#if 0
		// The timestamp of the frame is in the future. Cannot happen.
		NSAlert *alert = [NSAlert alertWithMessageText:@"Timestamp error" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Capture timestamp %lld is %lld µS in the future. This \"cannot happen\".", timestamp, timestamp - now_timestamp];
		[alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:YES];
		[session stopRunning];
		session = nil;
#else
	NSLog(@"Capture timestamp %lld is %lld µS in the future. This \"cannot happen\".", timestamp, timestamp - now_timestamp);
#ifdef WITH_STATISTICS
	nEarlyDrops++;
#endif
	return;
#endif
	}
	if (timestamp < now_timestamp - 500000) {
#if 0
		// Timestamp is more than half a second in the past
		NSAlert *alert = [NSAlert alertWithMessageText:@"Timestamp error" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Capture timestamp %lld is %lld µS in the past. This makes the current run useless. ", timestamp, now_timestamp - timestamp];
		[alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:YES];
		[session stopRunning];
		session = nil;
#else
	NSLog(@"Capture timestamp %lld is %lld µS in the past. This makes the current run useless. ", timestamp, now_timestamp - timestamp);
#ifdef WITH_STATISTICS
	nLateDrops++;
#endif
	return;
#endif
	}
#else
    if (timestamp < now_timestamp) {
        // Presentation time is in the past. Adjust our clock.
		UInt64 delta = now_timestamp - timestamp;
		if (capturing) {
			// Presentation time is in the past. Drop frame.
			NSLog(@"VideoInput: frame is %lld uS late. Drop.", delta);
			return;
		} else
		{
			//epoch += delta;
			NSLog(@"VideoInput: clock: delta %lld us, epoch set to %lld uS", delta, epoch);
		}
    }
#endif
	[self.manager newInputStart: timestamp];

    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    OSType format = CMFormatDescriptionGetMediaSubType(formatDescription);
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	const char *formatStr;
	if (format == kCVPixelFormatType_32ARGB) {
		formatStr = "RGB4";
	} else if (format == kCVPixelFormatType_8IndexedGray_WhiteIsZero) {
		formatStr = "Y800";
	} else if (format == kCVPixelFormatType_422YpCbCr8) {
		formatStr = "UYVY";
	} else if (format == 'yuvs' || format == 'yuv2') {
		// Not in the Apple header files, but generated by iSight on my MacBook??
		formatStr = "YUYV";
	} else {
		// Unknown format??
		formatStr = "unknown";
	}
	CVPixelBufferLockBaseAddress(pixelBuffer, 0);
	void *buffer = CVPixelBufferGetBaseAddress(pixelBuffer);
	size_t w = CVPixelBufferGetWidth(pixelBuffer);
	size_t h = CVPixelBufferGetHeight(pixelBuffer);
	size_t size = CVPixelBufferGetDataSize(pixelBuffer);
	assert (size>=w*h);
	[self.manager newInputDone: buffer width: (int)w height: (int)h format: formatStr size:(int)size];
	CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection;
{
    // Should adjust maximal frame rate (minFrameDuration)
    NSLog(@"camera capturer dropped frame...\n");
}
@end

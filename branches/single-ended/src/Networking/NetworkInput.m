#import "NetworkInput.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/clock.h>

@implementation NetworkInput
- (NSString *)deviceID
{
    return @"NetworkInput";
}

- (NSString *)deviceName
{
    return @"NetworkInput";
}

- (NetworkInput *)init
{
    self = [super init];
    if (self) {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 1080
//		if (CMClockGetHostTimeClock != NULL) {
//			clock = CMClockGetHostTimeClock();
//		}
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
		clock_serv_t cclock;
		mach_timespec_t mts;

		host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &cclock);
		clock_get_time(cclock, &mts);
		mach_port_deallocate(mach_task_self(), cclock);
		timestamp = ((UInt64)mts.tv_sec*1000000LL) + mts.tv_nsec/1000LL;
    }
    return timestamp;
}

- (void) stop
{

}

- (void) startCapturing: (BOOL) showPreview
{
//	capturing = YES;
}

- (void) stopCapturing
{
//	capturing = NO;
}



#if 0
// Needs to be replaced with something that is called when a
// string is received, this is then passed to a new version of newInputDone that accepts
// strings.
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
    SInt64 delta = now_timestamp - timestamp;
    if (1) {
        //
        // Suspect code ahead. On some combinations of camera and OS the video presentation
        // timestamp clock drifts. We compensate by slowly moving the epoch of our software
        // clock (which is used for output timestamping) to move towards the video input
        // timestamp clock. We do so slowly, because our dispatch_queue seems to give us
        // callbacks in some time-slotted fashion.
        epoch += (delta/10);
        NSLog(@"VideoInput: clock: delta %lld us, epoch set to %lld uS", delta, epoch);
    }
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
#endif

@end

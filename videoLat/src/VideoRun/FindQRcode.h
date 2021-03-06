///
///  @file FindQRcode.h
///  @brief Detect QR-codes in video using CoreImage.
//
//  Copyright 2010-2019 Centrum voor Wiskunde en Informatica. Licensed under GPL3.
//
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import "protocols.h"

@interface FindQRcode : NSObject <InputVideoFindProtocol> {
	CIDetector *detector;
	NSString *lastDetection;
}

@property(readonly) NSorUIRect rect;	//!< Rectangle around most recent QR code found

- (NSString *) find: (CVImageBufferRef)image;

@end

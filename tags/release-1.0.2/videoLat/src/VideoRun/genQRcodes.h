//
//  genQRcodes.h
//  macMeasurements
//
//  Created by Jack Jansen on 21-08-10.
//  Copyright 2010-2014 Centrum voor Wiskunde en Informatica. Licensed under GPL3.
//

#import <Cocoa/Cocoa.h>
#import "protocols.h"
#include "zint.h"


@interface GenQRcodes : NSObject <OutputVideoGenProtocol> {
    struct zint_symbol *symbol;
}

- (GenQRcodes*)init;
- (void) gen: (void*)buffer width: (int)width height: (int)height code: (const char *)code;

@end
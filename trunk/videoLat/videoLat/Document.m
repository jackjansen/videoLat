//
//  Document.m
//  videoLat
//
//  Created by Jack Jansen on 18/11/13.
//  Copyright (c) 2013 CWI. All rights reserved.
//

#import "Document.h"

@implementation Document
@synthesize dataStore;
@synthesize dataDistribution;

- (id)init
{
    self = [super init];
    if (self) {
		// Add your subclass-specific initialization here.
        NSLog(@"Document init\n");
    }
    return self;
}

- (id)initWithType:(NSString *)typeName error:(NSError **)outError
{
    NSLog(@"initWithType: %@\n", typeName);
    objectsForNewDocument = nil;
    NSArray *newObjects;
    BOOL ok = [[NSBundle mainBundle] loadNibNamed: @"NewMeasurement" owner: self topLevelObjects: &newObjects];
    objectsForNewDocument = newObjects;
    NSLog(@"Loaded NewMeasurement: %d, objects %@\n", (int)ok, objectsForNewDocument);
    return self;
}

- (NSString *)windowNibName
{
	// Override returning the nib file name of the document
	// If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
	return @"Document";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];
	// Add any code here that needs to be executed once the windowController has loaded the document's window.
}

- (IBAction)newDocumentComplete: (id)sender
{
    NSLog(@"New document complete\n");
    objectsForNewDocument = nil;
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	// Insert code here to write your document to data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning nil.
	// You can also choose to override -fileWrapperOfType:error:, -writeToURL:ofType:error:, or -writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.
	NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
	@throw exception;
	return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	// Insert code here to read your document from the given data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning NO.
	// You can also choose to override -readFromFileWrapper:ofType:error: or -readFromURL:ofType:error: instead.
	// If you override either of these, you should also override -isEntireFileLoaded to return NO if the contents are lazily loaded.
	NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
	@throw exception;
	return YES;
}

- (void)awakeFromNib
{
    baseName = @"videoLat";
}

- (IBAction)export: (id)sender
{
    
	NSString *csvData = [self.dataStore asCSVString];
    NSString *fileName = [NSString stringWithFormat:@"/tmp/%@-measurements.csv", baseName];
	[csvData writeToFile:fileName atomically:NO encoding:NSStringEncodingConversionAllowLossy error:nil];
#if 0
	csvData = [self.dataDistribution asCSVString];
    fileName = [NSString stringWithFormat:@"/tmp/%@-distribution.csv", baseName];
	[csvData writeToFile:fileName atomically:NO encoding:NSStringEncodingConversionAllowLossy error:nil];    
#endif
}

- (IBAction)save: (id)sender
{
    NSString *fileName = [NSString stringWithFormat:@"/tmp/%@.videoLat", baseName];
 	[NSKeyedArchiver archiveRootObject: dataStore toFile: fileName];
}

@end
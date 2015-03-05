//
//  Uploader.m
//  videoLat
//
//  Created by Jack Jansen on 05/03/15.
//  Copyright (c) 2015 CWI. All rights reserved.
//

#import "Uploader.h"
#import "MeasurementType.h"

@interface UploadHelper : NSThread  {
    NSURL *baseURL;
    NSURL *url;
    MeasurementDataStore *dataStore;
    NSString *measurementTypeID;
    NSString *machineTypeID;
    NSString *inputDeviceID;
    NSString *outputDeviceID;
    NSString *uuid;
    id<UploadQueryDelegate> delegate;
}

- (UploadHelper *)initWithURL: (NSURL *)_baseURL dataStore: (MeasurementDataStore *)_dataStore;
- (void)shouldUpload: (id<UploadQueryDelegate>)_delegate;
- (void)uploadAsynchronously;
- (void)_fillURLWithOp: (NSString *)op;
- (void)main;

@end

@implementation UploadHelper
- (UploadHelper *)initWithURL: (NSURL *)_baseURL dataStore: (MeasurementDataStore *)_dataStore
{
    self = [super init];
    if (self == nil) return nil;
    baseURL = _baseURL;
    url = nil;
    dataStore = _dataStore;
    measurementTypeID = dataStore.measurementType;
    machineTypeID = nil;
    inputDeviceID = nil;
    outputDeviceID = nil;
    uuid = nil;
    MeasurementType *myType = [MeasurementType forType: measurementTypeID];
    
    // First check: we only want to upload calibrations, and we want them to be consistent.
    
    if (!myType.isCalibration) return nil;
#if 1
    // Axctually, we only want to upload single-ended measurements
    if (!myType.outputOnlyCalibration && !myType.inputOnlyCalibration) {
        return nil;
    }
#else
    if (!myType.outputOnlyCalibration && !myType.inputOnlyCalibration) {
        if (![dataStore.input.machineTypeID isEqualToString: dataStore.output.machineTypeID]) {
            NSLog(@"sharedUploader: inconsistent machineTypeID input=%@ output=%@", dataStore.input.machineTypeID, dataStore.output.machineTypeID);
            return nil;
        }
    }
#endif
    // Get relevant parameters
    uuid = dataStore.uuid;
    
    if (!myType.outputOnlyCalibration) {
        if (dataStore.input == nil) {
            NSLog(@"sharedUploader: not output-only calibration but missing input device");
            return nil;
        }
        machineTypeID = dataStore.input.machineTypeID;
        inputDeviceID = dataStore.input.deviceID;
    }
    
    if (!myType.inputOnlyCalibration) {
        if (dataStore.input == nil) {
            NSLog(@"sharedUploader: not output-only calibration but missing input device");
            return nil;
        }
        machineTypeID = dataStore.output.machineTypeID;
        outputDeviceID = dataStore.output.deviceID;
    }
    
    return self;
}

- (void)_fillURLWithOp:(NSString *)op
{
    NSString *query = [NSString stringWithFormat:@"?op=%@", op];
    if (measurementTypeID) query = [NSString stringWithFormat: @"%@&measurementTypeID=%@", query, [measurementTypeID stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (uuid) query = [NSString stringWithFormat: @"%@&uuid=%@", query, [uuid stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (machineTypeID) query = [NSString stringWithFormat: @"%@&machineTypeID=%@", query, [machineTypeID stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (inputDeviceID) query = [NSString stringWithFormat: @"%@&inputDeviceID=%@", query, [inputDeviceID stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (outputDeviceID) query = [NSString stringWithFormat: @"%@&outputDeviceID=%@", query, [outputDeviceID stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@%@", [baseURL absoluteString], query]];
}

- (void)shouldUpload: (id<UploadQueryDelegate>)_delegate
{
    delegate = _delegate;
    [self _fillURLWithOp:@"check"];
    NSLog(@"shouldUpload: URL=%@", url);
    [delegate shouldUpload: YES];
}

- (void)uploadAsynchronously
{
    [self _fillURLWithOp:@"upload"];
    NSLog(@"uploadAsynchronously: URL=%@", url);
}

@end

@implementation Uploader


+ (Uploader *)sharedUploader
{
    static Uploader *shared = nil;
    if (shared == nil) {
        shared = [[Uploader alloc] initWithServer: [NSURL URLWithString: @"http://videolat.org/calibrationsharing"]];
    }
    return shared;
}

- initWithServer: (NSURL *)server
{
    self = [super init];
    if (self) {
        baseURL = server;
    }
    return self;
}

- (void)shouldUpload: (MeasurementDataStore *)dataStore delegate: (id<UploadQueryDelegate>) delegate
{
    UploadHelper *helper = [[UploadHelper alloc] initWithURL: baseURL dataStore: dataStore];
    if (helper) {
        [helper shouldUpload: delegate];
    }
    
}

- (void)uploadAsynchronously: (MeasurementDataStore *)dataStore
{
}

@end

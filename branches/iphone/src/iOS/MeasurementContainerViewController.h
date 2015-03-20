//
//  MeasurementContainerViewController.h
//  videoLat-iOS
//
//  Created by Jack Jansen on 16/03/15.
//  Copyright (c) 2015 CWI. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "protocols.h"
#import "MeasurementDataStore.h"

@interface MeasurementContainerViewController : UIViewController<NewMeasurementDelegate> {
	NSArray *measurementNibObjects;
	MeasurementDataStore *finishedDataStore;
}

@property(strong) NSString *measurementTypeName;
@property(strong) IBOutlet UIView *measurementView;

- (void)openUntitledDocumentWithMeasurement: (MeasurementDataStore *)dataStore;

@end

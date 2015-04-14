//
//  InputSelectionView.h
//  videoLat-iOS
//
//  Created by Jack Jansen on 25/03/15.
//  Copyright (c) 2015 CWI. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "protocols.h"

@interface InputSelectionView : UIView<SelectionView,UIPickerViewDataSource, UIPickerViewDelegate> {
    NSArray *_baseNames;
}

@property(weak) IBOutlet UIPickerView *bBase;			//!< UI element: available calibration runs
@property(weak) IBOutlet UILabel *bBaseLabel;			//!< UI element: label for the calibration picker
@property(weak) IBOutlet UILabel *bInputDeviceName;		//!< UI element: name of selected input device

@end
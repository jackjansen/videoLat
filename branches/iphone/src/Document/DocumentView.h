///
///  @file DocumentView.h
///  @brief Defines the DocumentView object.
//
//  Copyright 2010-2014 Centrum voor Wiskunde en Informatica. Licensed under GPL3.
//
//

#import "Protocols.h"
#import "DocumentDescriptionView.h"
#import "GraphView.h"
#import "Document.h"

///
/// Subclass of NSView, main view of the document. Contains the two graph views for distribution and samples
/// and the description view.
///
@interface DocumentView
#ifdef WITH_UIKIT
: UIView <UITabBarDelegate>
#else
: NSView
#endif
{
    BOOL initialValues; //!< Internal: helper variable to initialize subview values at the right time
    __weak Document *_modelObject;
};

@property(weak) IBOutlet DocumentDescriptionView *status;   //!< Set by NIB: view containing our metadata
@property(weak) IBOutlet GraphView *values;                 //!< Set by NIB: view showing the raw measurement values
@property(weak) IBOutlet GraphView *distribution;           //!< Set by NIB: view showing the measurement distribution
@property(weak) IBOutlet Document *modelObject;                //!< Set by NIB: pointer to our Document

#ifdef WITH_UIKIT
@property(weak) IBOutlet UITabBar *tabbar;
@property(weak) IBOutlet UIView *tab1;
@property(weak) IBOutlet UIView *tab2;
@property(weak) IBOutlet UIView *tab3;
@property(weak) IBOutlet UIView *tab4;
#endif

- (void)viewWillDraw;   //!< Called by window manager just before viewing, calls updateView if needed
- (void)_updateView;     //!< Updates variables in status view so they reflect the document values
- (void)controlTextDidChange:(NSNotification *)aNotification;   //!< Called when description in status view has changed, updates the document
- (IBAction)openInputCalibration:(id)sender;
- (IBAction)openOutputCalibration:(id)sender;
@end

//
//  BTRGridLayoutInfo.h
//  BTRCollectionView
//
//  Created by Jonathan Willing on 3/21/13.
//  Copyright (c) 2013 Butter. All rights reserved.
//

#import <Foundation/Foundation.h>


@class BTRGridLayoutSection;

/*
 Every PSTCollectionViewLayout has a PSTGridLayoutInfo attached.
 Is used extensively in PSTCollectionViewFlowLayout.
 */
@interface BTRGridLayoutInfo : NSObject

@property (nonatomic, strong, readonly) NSArray *sections;
@property (nonatomic, strong) NSDictionary *rowAlignmentOptions;
@property (nonatomic, assign) BOOL usesFloatingHeaderFooter;

// Vertical/horizontal dimension (depending on horizontal)
// Used to create row objects
@property (nonatomic, assign) CGFloat dimension;

@property (nonatomic, assign) BOOL horizontal;
@property (nonatomic, assign) BOOL leftToRight;
@property (nonatomic, assign) CGSize contentSize;

// Frame for specific PSTGridLayoutItem.
- (CGRect)frameForItemAtIndexPath:(NSIndexPath *)indexPath;

// Add new section. Invalidates layout.
- (BTRGridLayoutSection *)addSection;

// forces the layout to recompute on next access
// TODO; what's the parameter for?
- (void)invalidate:(BOOL)arg;

// Make a copy of the current state.
- (BTRGridLayoutInfo *)snapshot;

@end

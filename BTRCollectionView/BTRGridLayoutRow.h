//
//  BTRGridLayoutRow.h
//  BTRCollectionView
//
//  Created by Jonathan Willing on 3/21/13.
//  Copyright (c) 2013 Butter. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BTRGridLayoutSection, BTRGridLayoutItem;

@interface BTRGridLayoutRow : NSObject

@property (nonatomic, unsafe_unretained) BTRGridLayoutSection *section;
@property (nonatomic, strong, readonly) NSArray *items;
@property (nonatomic, assign) CGSize rowSize;
@property (nonatomic, assign) CGRect rowFrame;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) BOOL complete;
@property (nonatomic, assign) BOOL fixedItemSize;

// @steipete addition for row-fastPath
@property (nonatomic, assign) NSInteger itemCount;

//- (BTRGridLayoutRow *)copyFromSection:(BTRGridLayoutSection *)section; // ???

// Add new item to items array.
- (void)addItem:(BTRGridLayoutItem *)item;

// Layout current row (if invalid)
- (void)layoutRow;

// @steipete: Helper to save code in BTRCollectionViewFlowLayout.
// Returns the item rects when fixedItemSize is enabled.
- (NSArray *)itemRects;

//  Set current row frame invalid.
- (void)invalidate;

// Copy a snapshot of the current row data
- (BTRGridLayoutRow *)snapshot;

@end

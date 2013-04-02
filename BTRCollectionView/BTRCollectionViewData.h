//
//  BTRCollectionViewData.h
//  BTRCollectionView
//
//  Created by Jonathan Willing on 3/21/13.
//  Copyright (c) 2013 Butter. All rights reserved.
//

#import "BTRCollectionViewCommon.h"
#import <Foundation/Foundation.h>

@class BTRCollectionView, BTRCollectionViewLayout, BTRCollectionViewLayoutAttributes;

@interface BTRCollectionViewData : NSObject

/// Designated initializer.
- (id)initWithCollectionView:(BTRCollectionView *)collectionView layout:(BTRCollectionViewLayout *)layout;

// Ensure data is valid. may fetches items from dataSource and layout.
- (void)validateLayoutInRect:(CGRect)rect;

- (CGRect)rectForItemAtIndexPath:(NSIndexPath *)indexPath;
/*
 - (CGRect)rectForSupplementaryElementOfKind:(id)arg1 atIndexPath:(id)arg2;
 - (CGRect)rectForDecorationElementOfKind:(id)arg1 atIndexPath:(id)arg2;
 - (CGRect)rectForGlobalItemIndex:(int)arg1;
 */

- (NSInteger)globalIndexForItemAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForItemAtGlobalIndex:(NSInteger)index;

// Fetch layout attributes
- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect;
/*
 - (PSTCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath;
 - (PSTCollectionViewLayoutAttributes *)layoutAttributesForElementsInSection:(NSInteger)section;
 - (PSTCollectionViewLayoutAttributes *)layoutAttributesForGlobalItemIndex:(NSInteger)index;
 - (PSTCollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(id)arg1 atIndexPath:(NSIndexPath *)indexPath;
 - (PSTCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryElementOfKind:(id)arg1 atIndexPath:(NSIndexPath *)indexPath;
 - (id)existingSupplementaryLayoutAttributesInSection:(int)arg1;
 */

// Make data to re-evaluate dataSources.
- (void)invalidate;

// Access cached item data
- (NSInteger)numberOfItemsBeforeSection:(NSInteger)section;
- (NSInteger)numberOfItemsInSection:(NSInteger)section;
- (NSInteger)numberOfItems;
- (NSInteger)numberOfSections;

// Total size of the content.
- (CGRect)collectionViewContentRect;

@property (readonly) BOOL layoutIsPrepared;

/*
 - (void)_setLayoutAttributes:(id)arg1 atGlobalItemIndex:(int)arg2;
 - (void)_setupMutableIndexPath:(id*)arg1 forGlobalItemIndex:(int)arg2;
 - (id)_screenPageForPoint:(struct CGPoint { float x1; float x2; })arg1;
 - (void)_validateContentSize;
 - (void)_validateItemCounts;
 - (void)_updateItemCounts;
 - (void)_loadEverything;
 - (void)_prepareToLoadData;
 - (void)invalidate:(BOOL)arg1;
 */

@end
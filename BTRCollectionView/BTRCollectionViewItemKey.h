//
//  BTRCollectionViewItemKey.h
//  BTRCollectionView
//
//  Created by Jonathan Willing on 3/21/13.
//  Copyright (c) 2013 Butter. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BTRCollectionViewCommon.h"
#import "BTRCollectionViewLayout.h"

extern NSString * const BTRCollectionElementKindCell;
extern NSString * const BTRCollectionElementKindDecorationView;

@interface BTRCollectionViewItemKey : NSObject <NSCopying>

+ (id)collectionItemKeyForLayoutAttributes:(BTRCollectionViewLayoutAttributes *)layoutAttributes;
+ (id)collectionItemKeyForDecorationViewOfKind:(NSString *)elementKind andIndexPath:(NSIndexPath *)indexPath;
+ (id)collectionItemKeyForSupplementaryViewOfKind:(NSString *)elementKind andIndexPath:(NSIndexPath *)indexPath;
+ (id)collectionItemKeyForCellWithIndexPath:(NSIndexPath *)indexPath;

@property (nonatomic, assign) BTRCollectionViewItemType type;
@property (nonatomic, strong) NSIndexPath *indexPath;
@property (nonatomic, strong) NSString *identifier;
@end
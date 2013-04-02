//
//  BTRGridLayoutItem.h
//  BTRCollectionView
//
//  Created by Jonathan Willing on 3/21/13.
//  Copyright (c) 2013 Butter. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BTRGridLayoutSection, BTRGridLayoutRow;

// Represents a single grid item; only created for non-uniform-sized grids.
@interface BTRGridLayoutItem : NSObject

@property (nonatomic, unsafe_unretained) BTRGridLayoutSection *section;
@property (nonatomic, unsafe_unretained) BTRGridLayoutRow *rowObject;
@property (nonatomic, assign) CGRect itemFrame;

@end

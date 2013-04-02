//
//  BTRGridLayoutItem.m
//  BTRCollectionView
//
//  Created by Jonathan Willing on 3/21/13.
//  Copyright (c) 2013 Butter. All rights reserved.
//

#import "BTRGridLayoutItem.h"

@implementation BTRGridLayoutItem

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p itemFrame:%@>", NSStringFromClass([self class]), self, NSStringFromRect(self.itemFrame)];
}

@end

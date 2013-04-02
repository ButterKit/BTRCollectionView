//
//  BTRCollectionViewData.m
//  BTRCollectionView
//
//  Created by Jonathan Willing on 3/21/13.
//  Copyright (c) 2013 Butter. All rights reserved.
//

#import "BTRCollectionViewData.h"
#import "BTRCollectionView.h"
#import "BTRCollectionViewLayout.h"

@interface BTRCollectionViewData () {
    CGRect _validLayoutRect;
    
    NSInteger _numItems;
    NSInteger _numSections;
    NSInteger *_sectionItemCounts;
    NSArray *_globalItems;
	
    CGSize _contentSize;
    struct {
        unsigned int contentSizeIsValid:1;
        unsigned int itemCountsAreValid:1;
        unsigned int layoutIsPrepared:1;
    } _collectionViewDataFlags;
}
@property (nonatomic, unsafe_unretained) BTRCollectionView *collectionView;
@property (nonatomic, unsafe_unretained) BTRCollectionViewLayout *layout;
@property (nonatomic, strong) NSArray *cachedLayoutAttributes;

@end

@implementation BTRCollectionViewData

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithCollectionView:(BTRCollectionView *)collectionView layout:(BTRCollectionViewLayout *)layout {
    if((self = [super init])) {
        _globalItems = [NSArray new];
        _collectionView = collectionView;
        _layout = layout;
    }
    return self;
}

- (void)dealloc {
    if(_sectionItemCounts) free(_sectionItemCounts);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p numItems:%ld numSections:%ld globalItems:%@>", NSStringFromClass([self class]), self, (long)self.numberOfItems, (long)self.numberOfSections, _globalItems];
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)invalidate {
    _collectionViewDataFlags.itemCountsAreValid = NO;
    _collectionViewDataFlags.layoutIsPrepared = NO;
    _validLayoutRect = CGRectNull;  // don't set CGRectZero in case of _contentSize=CGSizeZero
}

- (CGRect)collectionViewContentRect {
    return (CGRect){.size=_contentSize};
}

- (void)validateLayoutInRect:(CGRect)rect {
    [self validateItemCounts];
    [self prepareToLoadData];
    
    // TODO: check if we need to fetch data from layout
    if (!CGRectEqualToRect(_validLayoutRect, rect)) {
        _validLayoutRect = rect;
        // we only want cell layoutAttributes & supplementaryView layoutAttributes
        self.cachedLayoutAttributes = [[self.layout layoutAttributesForElementsInRect:rect] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(BTRCollectionViewLayoutAttributes *evaluatedObject, NSDictionary *bindings) {
            return ([evaluatedObject isKindOfClass:[BTRCollectionViewLayoutAttributes class]] &&
                    ([evaluatedObject isCell]||
                     [evaluatedObject isSupplementaryView]||
                     [evaluatedObject isDecorationView]));
        }]];
    }
}

- (NSInteger)numberOfItems {
    [self validateItemCounts];
    return _numItems;
}

- (NSInteger)numberOfItemsBeforeSection:(NSInteger)section {
    return [self numberOfItemsInSection:section-1]; // ???
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section {
    [self validateItemCounts];
    if (section > _numSections || section < 0) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Section %ld out of range: 0...%ld", (long)section, (long)_numSections] userInfo:nil];
    }
    
    NSInteger numberOfItemsInSection = 0;
    if (_sectionItemCounts) {
        numberOfItemsInSection = _sectionItemCounts[section];
    }
    return numberOfItemsInSection;
}

- (NSInteger)numberOfSections {
    [self validateItemCounts];
    return _numSections;
}

- (CGRect)rectForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGRectZero;
}

- (NSIndexPath *)indexPathForItemAtGlobalIndex:(NSInteger)index {
    return _globalItems[index];
}

- (NSInteger)globalIndexForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [_globalItems indexOfObject:indexPath];
}

- (BOOL)layoutIsPrepared {
    return _collectionViewDataFlags.layoutIsPrepared;
}

- (void)setLayoutIsPrepared:(BOOL)layoutIsPrepared {
    _collectionViewDataFlags.layoutIsPrepared = layoutIsPrepared;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Fetch Layout Attributes

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect {
    [self validateLayoutInRect:rect];
    return self.cachedLayoutAttributes;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

// ensure item count is valid and loaded
- (void)validateItemCounts {
    if (!_collectionViewDataFlags.itemCountsAreValid) {
        [self updateItemCounts];
    }
}

// query dataSource for new data
- (void)updateItemCounts {
    // query how many sections there will be
    _numSections = 1;
    if ([self.collectionView.dataSource respondsToSelector:@selector(numberOfSectionsInCollectionView:)]) {
        _numSections = [self.collectionView.dataSource numberOfSectionsInCollectionView:self.collectionView];
    }
    if (_numSections <= 0) { // early bail-out
        _numItems = 0;
        free(_sectionItemCounts); _sectionItemCounts = 0;
        return;
    }
    // allocate space
    if (!_sectionItemCounts) {
        _sectionItemCounts = malloc(_numSections * sizeof(NSInteger));
    }else {
        _sectionItemCounts = realloc(_sectionItemCounts, _numSections * sizeof(NSInteger));
    }
	
    // query cells per section
    _numItems = 0;
    for (NSInteger i=0; i<_numSections; i++) {
        NSInteger cellCount = [self.collectionView.dataSource collectionView:self.collectionView numberOfItemsInSection:i];
        _sectionItemCounts[i] = cellCount;
        _numItems += cellCount;
    }
    NSMutableArray* globalIndexPaths = [[NSMutableArray alloc] initWithCapacity:_numItems];
    for(NSInteger section = 0;section<_numSections;section++)
        for(NSInteger item=0;item<_sectionItemCounts[section];item++)
            [globalIndexPaths addObject:[NSIndexPath btr_indexPathForItem:item inSection:section]];
    _globalItems = [NSArray arrayWithArray:globalIndexPaths];
    _collectionViewDataFlags.itemCountsAreValid = YES;
}

- (void)prepareToLoadData {
    if (!self.layoutIsPrepared) {
        [self.layout prepareLayout];
        _contentSize = self.layout.collectionViewContentSize;
        self.layoutIsPrepared = YES;
    }
}

@end

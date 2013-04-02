//
//  BTRCollectionView.m
//
//  Original Source: Copyright (c) 2012 Peter Steinberger. All rights reserved.
//  AppKit Port: Copyright (c) 2012 Indragie Karunaratne and Jonathan Willing. All rights reserved.
//

#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#import "BTRCollectionView.h"
#import "BTRCollectionViewCell.h"
#import "BTRCollectionViewData.h"
#import "BTRCollectionViewLayout.h"
#import "BTRCollectionViewItemKey.h"
#import "BTRCollectionViewUpdateItem.h"
#import "BTRCollectionViewFlowLayout.h"

#pragma mark Internal Constants

//static NSString* const BTRCollectionViewDeletedItemsCount = @"BTRCollectionViewDeletedItemsCount";
//static NSString* const BTRCollectionViewInsertedItemsCount = @"BTRCollectionViewInsertedItemsCount";
//static NSString* const BTRCollectionViewMovedOutCount = @"BTRCollectionViewMovedOutCount";
//static NSString* const BTRCollectionViewMovedInCount = @"BTRCollectionViewMovedInCount";
//static NSString* const BTRCollectionViewPreviousLayoutInfoKey = @"BTRCollectionViewPreviousLayoutInfoKey";
//static NSString* const BTRCollectionViewNewLayoutInfoKey = @"BTRCollectionViewNewLayoutInfoKey";
//static NSString* const BTRCollectionViewViewKey = @"BTRCollectionViewViewKey";

@interface BTRCollectionViewLayout (Internal)
@property (nonatomic, weak) BTRCollectionView *collectionView;
@end

@interface BTRCollectionViewData (Internal)
- (void)prepareToLoadData;
@end

@interface BTRCollectionViewUpdateItem()
- (NSIndexPath *)indexPath;
- (BOOL)isSectionOperation;
@end

@interface BTRCollectionView ()
// Stores all the data associated with collection view layout
@property (nonatomic, strong) BTRCollectionViewData *collectionViewData;
// Mapped to the ivar _allVisibleViewsDict (dictionary of all visible views)
@property (nonatomic, readonly) NSDictionary *visibleViewsDict;
// Stores the information associated with an update of the collection view's items
@property (nonatomic, strong) NSDictionary *currentUpdate;
@end

@interface BTRCollectionViewLayout()
@property (nonatomic,copy,readonly) NSDictionary *decorationViewClassDict;
@property (nonatomic,copy,readonly) NSDictionary *decorationViewNibDict;
@property (nonatomic,copy,readonly) NSDictionary *decorationViewExternalObjectsTables;
@end

@implementation BTRCollectionView {
	// Collection view layout
	BTRCollectionViewLayout *_layout;
	// Collection view data source
	__unsafe_unretained id<BTRCollectionViewDataSource> _dataSource;
	// Background view displayed beneath the collection view
	NSView *_backgroundView;
	// Array of index paths for the selected items
	NSMutableArray *_indexPathsForSelectedItems;
	// Set of items that are highlighted (highlighted state comes before selected)
	NSMutableArray *_indexPathsForHighlightedItems;
	// Set of items that were newly highlighted by a mouse event
	NSMutableSet *_indexPathsForNewlyHighlightedItems;
	// Set of items that were newly unhighlighted by a mouse event
	NSMutableSet *_indexPathsForNewlyUnhighlightedItems;
	
	// Reuse queues for collection view cells
	NSMutableDictionary *_cellReuseQueues;
	// Reuse queues for collection view supplementary views
	NSMutableDictionary *_supplementaryViewReuseQueues;
	// Reuse queues for collection view decoration views
	NSMutableDictionary *_decorationViewReuseQueues;
	
	// Tracks the state of reload suspension
	NSInteger _reloadingSuspendedCount;
	// Dictionary containing all views visible on screen
	NSMutableDictionary *_allVisibleViewsDict;
	// Container class that stores the layout data for the collection view
	BTRCollectionViewData *_collectionViewData;
	// Keeps track of state for item animations
	NSInteger _updateCount;
	
	id _update;
	// Temporary array of items that are inserted
	NSMutableArray *_insertItems;
	// Temporary array of items that are deleted
	NSMutableArray *_deleteItems;
	// Temporary array of items that are reloaded
	NSMutableArray *_reloadItems;
	// Temporary array of items that are moved
	NSMutableArray *_moveItems;
	// The original array of inserted items before the array is mutated
	NSArray *_originalInsertItems;
	// The original array of deleted items before the array is mutaed
	NSArray *_originalDeleteItems;
	// Block that is executed when updates to the collection view have been completed
	void (^_updateCompletionHandler)(BOOL finished);
	// Maps cell classes to reuse identifiers
	NSMutableDictionary *_cellClassDict;
	// Maps cell nibs to reuse identifiers
	NSMutableDictionary *_cellNibDict;
	// Maps supplementary view classes to reuse identifiers
	NSMutableDictionary *_supplementaryViewClassDict;
	// Maps supplementary view nibs to reuse identifiers
	NSMutableDictionary *_supplementaryViewNibDict;
		
	struct {
		// Tracks which methods the delegate and data source implement
		unsigned int delegateShouldHighlightItemAtIndexPath : 1;
		unsigned int delegateDidHighlightItemAtIndexPath : 1;
		unsigned int delegateDidUnhighlightItemAtIndexPath : 1;
		unsigned int delegateShouldSelectItemAtIndexPath : 1;
		unsigned int delegateShouldDeselectItemAtIndexPath : 1;
		unsigned int delegateDidSelectItemAtIndexPath : 1;
		unsigned int delegateDidDeselectItemAtIndexPath : 1;
		unsigned int delegateSupportsMenus : 1;
		unsigned int delegateDidEndDisplayingCell : 1;
		unsigned int delegateDidEndDisplayingSupplementaryView : 1;
		unsigned int dataSourceNumberOfSections : 1;
		unsigned int dataSourceViewForSupplementaryElement : 1;
		// Tracks collection view state
		unsigned int updating : 1;
		unsigned int updatingLayout : 1;
		unsigned int needsReload : 1;
		unsigned int reloading : 1;
		unsigned int doneFirstLayout : 1;
	} _collectionViewFlags;
}

@synthesize collectionViewLayout = _layout;
@synthesize visibleViewsDict = _allVisibleViewsDict;

#pragma mark - NSObject

- (void)BTRCollectionViewCommonSetup {
	// Allocate storage variables, configure default settings
	self.allowsSelection = YES;
	self.flipped = YES;

	_indexPathsForSelectedItems = [NSMutableArray new];
	_indexPathsForHighlightedItems = [NSMutableArray new];
	_cellReuseQueues = [NSMutableDictionary new];
	_supplementaryViewReuseQueues = [NSMutableDictionary new];
	_decorationViewReuseQueues = [NSMutableDictionary new];
	_allVisibleViewsDict = [NSMutableDictionary new];
	_cellClassDict = [NSMutableDictionary new];
	_cellNibDict = [NSMutableDictionary new];
	_supplementaryViewClassDict = [NSMutableDictionary new];
	_supplementaryViewNibDict = [NSMutableDictionary new];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
	return [self initWithFrame:frameRect collectionViewLayout:nil];
}

- (id)initWithFrame:(CGRect)frame collectionViewLayout:(BTRCollectionViewLayout *)layout {
	if ((self = [super initWithFrame:frame])) {
		[self BTRCollectionViewCommonSetup];
		self.collectionViewLayout = layout;
		_collectionViewData = [[BTRCollectionViewData alloc] initWithCollectionView:self layout:layout];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)inCoder {
	if ((self = [super initWithCoder:inCoder])) {
		[self BTRCollectionViewCommonSetup];
	}
	return self;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ collection view layout: %@",
			[super description],
			self.collectionViewLayout];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - NSView

- (void)viewWillMoveToSuperview:(NSView *)newSuperview {
	[super viewWillMoveToSuperview:newSuperview];
	// The collection view should always be placed inside a scroll view
	// Hence, its superview should be an NSClipView
	if ([newSuperview isKindOfClass:[NSClipView class]]) {
		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		if (self.superview && [self.superview isKindOfClass:[NSClipView class]]) {
			self.superview.postsBoundsChangedNotifications = NO;
			[nc removeObserver:self name:NSViewBoundsDidChangeNotification object:self.superview];
		}
		// Tell the clip view to post bounds changed notifications so that notifications are posted
		// when the view is scrolled
		NSClipView *clipView = (NSClipView *)newSuperview;
		clipView.postsBoundsChangedNotifications = YES;
		// Register for that notification and trigger layout
		[nc addObserverForName:NSViewBoundsDidChangeNotification object:clipView queue:nil usingBlock:^(NSNotification *note) {
			[self setNeedsLayout:YES];
		}];
	}
}

- (void)layout {
	[super layout];
	// Validate the layout inside the currently visible rectangle
	[_collectionViewData validateLayoutInRect:self.visibleRect];
	
	// Update the visible cells
	if (!_collectionViewFlags.updatingLayout)
		[self updateVisibleCells];
	
	// Check if the content size needs to be reset
	CGSize contentSize = [_collectionViewData collectionViewContentRect].size;
	if (!CGSizeEqualToSize(self.frame.size, contentSize)) {
		// Set the new content size and run layout again
		self.frameSize = contentSize;
		
		[_collectionViewData validateLayoutInRect:self.visibleRect];
		[self updateVisibleCells];
	}
	// Set the frame of the background view to the visible section of the view
	// This means that the background view moves as a backdrop as the view is scrolled
	if (_backgroundView) {
		_backgroundView.frame = self.visibleRect;
	}
	// We have now done a full layout pass, so update the flag
	_collectionViewFlags.doneFirstLayout = YES;
}

- (void)setFrame:(NSRect)frame {
	if (!CGRectEqualToRect(frame, self.frame)) {
		// If the frame is different, check if the layout needs to be invalidated
		if ([self.collectionViewLayout shouldInvalidateLayoutForBoundsChange:(CGRect){.size=frame.size}]) {
			[self invalidateLayout];
		}
		
		[super setFrame:frame];
	}
}

- (void)addCollectionViewSubview:(NSView *)subview {
	if ([subview isKindOfClass:[BTRCollectionViewCell class]]) {
		[self addSubview:subview positioned:NSWindowBelow relativeTo:nil];
	} else {
		[self addSubview:subview];
	}
}

#pragma mark - NSResponder

// Need to override these to receive keyboard events

- (BOOL)acceptsFirstResponder {
	return YES;
}

- (BOOL)canBecomeKeyView {
	return YES;
}

#pragma mark - Public

- (void)registerClass:(Class)cellClass forCellWithReuseIdentifier:(NSString *)identifier {
	NSParameterAssert(cellClass);
	NSParameterAssert(identifier);
	_cellClassDict[identifier] = cellClass;
}

- (void)registerClass:(Class)viewClass forSupplementaryViewOfKind:(NSString *)elementKind withReuseIdentifier:(NSString *)identifier {
	NSParameterAssert(viewClass);
	NSParameterAssert(elementKind);
	NSParameterAssert(identifier);
	NSString *kindAndIdentifier = [NSString stringWithFormat:@"%@/%@", elementKind, identifier];
	_supplementaryViewClassDict[kindAndIdentifier] = viewClass;
}

- (void)registerNib:(NSNib *)nib forCellWithReuseIdentifier:(NSString *)identifier {
	NSArray *topLevelObjects = nil;
	[nib instantiateWithOwner:nil topLevelObjects:&topLevelObjects];
	__block BOOL containsCell = NO;
	[topLevelObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([obj isKindOfClass:[BTRCollectionViewCell class]]) {
			containsCell = YES;
			*stop = YES;
		}
	}];
	NSAssert(containsCell, @"must contain a BTRCollectionViewCell object");
	
	_cellNibDict[identifier] = nib;
}

- (void)registerNib:(NSNib *)nib forSupplementaryViewOfKind:(NSString *)kind withReuseIdentifier:(NSString *)identifier {
	NSArray *topLevelObjects = nil;
	[nib instantiateWithOwner:nil topLevelObjects:&topLevelObjects];
	__block BOOL containsView = NO;
	[topLevelObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([obj isKindOfClass:[BTRCollectionReusableView class]]) {
			containsView = YES;
			*stop = YES;
		}
	}];
	NSAssert(containsView, @"must contain a BTRCollectionReusableView object");
	
	NSString *kindAndIdentifier = [NSString stringWithFormat:@"%@/%@", kind, identifier];
	_supplementaryViewNibDict[kindAndIdentifier] = nib;
}

- (id)dequeueReusableCellWithReuseIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath {
	// Check to see if there is already a reusable cell in the reuse queue
	NSMutableArray *reusableCells = _cellReuseQueues[identifier];
	__block BTRCollectionViewCell *cell = [reusableCells lastObject];
	BTRCollectionViewLayoutAttributes *attributes = [self.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath];
	
	if (cell) {
		[reusableCells removeObjectAtIndex:[reusableCells count]-1];
	} else {
		// If a NIB was registered for the cell, instantiate the NIB and retrieve the view from there
		if (_cellNibDict[identifier]) {
			// Cell was registered via registerNib:forCellWithReuseIdentifier:
			NSNib *cellNib = _cellNibDict[identifier];
			NSArray *topLevelObjects = nil;
			[cellNib instantiateWithOwner:self topLevelObjects:&topLevelObjects];
			[topLevelObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				if ([obj isKindOfClass:[BTRCollectionViewCell class]]) {
					cell = obj;
					*stop = YES;
				}
			}];
		} else {
			// Otherwise, attempt to create a new cell view from a registered class
			Class cellClass = _cellClassDict[identifier];
			if (cellClass == nil) {
				// Throw an exception if no NIB or Class was registered for the cell class
				@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Class not registered for identifier %@", identifier] userInfo:nil];
			}
			// Ask the layout to supply the attributes for the new cell
			if (attributes) {
				cell = [[cellClass alloc] initWithFrame:attributes.frame];
			} else {
				cell = [cellClass new];
			}
		}
		cell.collectionView = self;
		cell.reuseIdentifier = identifier;
	}
	
	[cell applyLayoutAttributes:attributes];
	
	return cell;
}

- (id)dequeueReusableSupplementaryViewOfKind:(NSString *)elementKind withReuseIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath {
	// Check to see if there's already a supplementary view of the desired type in the reuse queue
	NSString *kindAndIdentifier = [NSString stringWithFormat:@"%@/%@", elementKind, identifier];
	NSMutableArray *reusableViews = _supplementaryViewReuseQueues[kindAndIdentifier];
	BTRCollectionViewLayoutAttributes *attributes = [self.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:elementKind atIndexPath:indexPath];
	
	__block BTRCollectionReusableView *view = [reusableViews lastObject];
	if (view) {
		[reusableViews removeObjectAtIndex:reusableViews.count - 1];
	} else {
		// Otherwise, check to see if a NIB was registered for the view
		// and use that to create an instance of the view
		if (_supplementaryViewNibDict[kindAndIdentifier]) {
			// supplementary view was registered via registerNib:forCellWithReuseIdentifier:
			NSNib *supplementaryViewNib = _supplementaryViewNibDict[kindAndIdentifier];
			NSArray *topLevelObjects = nil;
			[supplementaryViewNib instantiateWithOwner:self topLevelObjects:&topLevelObjects];
			[topLevelObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				if ([obj isKindOfClass:[BTRCollectionReusableView class]]) {
					view = obj;
					*stop = YES;
				}
			}];
		} else {
			// Check to see if a class was registered for the view
			Class viewClass = _supplementaryViewClassDict[kindAndIdentifier];
			if (viewClass == nil) {
				// Throw an exception if neither a class nor a NIB was registered
				@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Class not registered for kind/identifier %@", kindAndIdentifier] userInfo:nil];
			}
			if (attributes) {
				// Ask the collection view for the layout attributes for the view
				BTRCollectionViewLayoutAttributes *attributes = [self.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:elementKind atIndexPath:indexPath];
				view = [[viewClass alloc] initWithFrame:attributes.frame];
			} else {
				view = [viewClass new];
			}
		}
		view.collectionView = self;
		view.reuseIdentifier = identifier;
	}
	
	[view applyLayoutAttributes:attributes];
	
	return view;
}

- (id)dequeueReusableOrCreateDecorationViewOfKind:(NSString *)elementKind forIndexPath:(NSIndexPath *)indexPath {
	// Check to see if there's already a supplementary view of the desired type in the reuse queue
	NSMutableArray *reusableViews = _decorationViewReuseQueues[elementKind];
	__block BTRCollectionReusableView *view = [reusableViews lastObject];
    BTRCollectionViewLayout *collectionViewLayout = self.collectionViewLayout;
	BTRCollectionViewLayoutAttributes *attributes = [self.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:elementKind atIndexPath:indexPath];
	
	if (view) {
		[reusableViews removeObjectAtIndex:reusableViews.count - 1];
	} else {
		NSDictionary *decorationViewNibDict = collectionViewLayout.decorationViewNibDict;
		
		if (decorationViewNibDict[elementKind]) {
			// supplementary view was registered via registerNib:forCellWithReuseIdentifier:
			NSNib *supplementaryViewNib = decorationViewNibDict[elementKind];
			NSArray *topLevelObjects = nil;
			[supplementaryViewNib instantiateWithOwner:self topLevelObjects:&topLevelObjects];
			[topLevelObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				if ([obj isKindOfClass:[BTRCollectionReusableView class]]) {
					view = obj;
					*stop = YES;
				}
			}];
		} else {
			NSDictionary *decorationViewClassDict = collectionViewLayout.decorationViewClassDict;
            Class viewClass = decorationViewClassDict[elementKind];
            Class reusableViewClass = NSClassFromString(@"UICollectionReusableView");
            if (reusableViewClass && [viewClass isEqual:reusableViewClass]) {
                viewClass = [BTRCollectionReusableView class];
            }
            if (viewClass == nil) {
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Class not registered for identifier %@", elementKind] userInfo:nil];
            }
            if (attributes) {
                view = [[viewClass alloc] initWithFrame:attributes.frame];
            } else {
                view = [viewClass new];
            }

		}
		view.collectionView = self;
		view.reuseIdentifier = elementKind;
	}
	
	[view applyLayoutAttributes:attributes];
	
	return view;
}


- (NSArray *)allCells {
	return [[_allVisibleViewsDict allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
		return [evaluatedObject isKindOfClass:[BTRCollectionViewCell class]];
	}]];
}

- (NSArray *)visibleCells {
	return [[_allVisibleViewsDict allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
		// Check if the cell is within the visible rect
		return [evaluatedObject isKindOfClass:[BTRCollectionViewCell class]] && CGRectIntersectsRect(self.visibleRect, [evaluatedObject frame]);
	}]];
}

- (void)reloadData {
	// Don't reload data if reloading has been suspended
	if (_reloadingSuspendedCount != 0) return;
	// Invalidate the layout
	[self invalidateLayout];
	// Remove every view from the collection view and empty the dictionary
	[_allVisibleViewsDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		if ([obj isKindOfClass:[NSView class]]) {
			[obj removeFromSuperview];
		}
	}];
	[_allVisibleViewsDict removeAllObjects];
	// Deselect everything
	[_indexPathsForSelectedItems enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, NSUInteger idx, BOOL *stop) {
		BTRCollectionViewCell *selectedCell = [self cellForItemAtIndexPath:indexPath];
		selectedCell.selected = NO;
		selectedCell.highlighted = NO;
	}];
	[_indexPathsForSelectedItems removeAllObjects];
	[_indexPathsForHighlightedItems removeAllObjects];
	// Layout
	[self setNeedsLayout:YES];
}


#pragma mark - Query Grid

// A bunch of methods that query the collection view's layout for information

- (NSUInteger)numberOfSections {
	return [_collectionViewData numberOfSections];
}

- (NSUInteger)numberOfItemsInSection:(NSUInteger)section {
	return [_collectionViewData numberOfItemsInSection:section];
}

- (BTRCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
	return [[self collectionViewLayout] layoutAttributesForItemAtIndexPath:indexPath];
}

- (BTRCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
	return [[self collectionViewLayout] layoutAttributesForSupplementaryViewOfKind:kind atIndexPath:indexPath];
}

- (NSIndexPath *)indexPathForItemAtPoint:(CGPoint)point {
	__block NSIndexPath *indexPath = nil;
	[_allVisibleViewsDict enumerateKeysAndObjectsWithOptions:kNilOptions usingBlock:^(id key, id obj, BOOL *stop) {
		BTRCollectionViewItemKey *itemKey = (BTRCollectionViewItemKey *)key;
		if (itemKey.type == BTRCollectionViewItemTypeCell) {
			BTRCollectionViewCell *cell = (BTRCollectionViewCell *)obj;
			if (CGRectContainsPoint(cell.frame, point)) {
				indexPath = itemKey.indexPath;
				*stop = YES;
			}
		}
	}];
	return indexPath;
}

- (NSIndexPath *)indexPathForCell:(BTRCollectionViewCell *)cell {
	__block NSIndexPath *indexPath = nil;
	[_allVisibleViewsDict enumerateKeysAndObjectsWithOptions:kNilOptions usingBlock:^(id key, id obj, BOOL *stop) {
		BTRCollectionViewItemKey *itemKey = (BTRCollectionViewItemKey *)key;
		if (itemKey.type == BTRCollectionViewItemTypeCell) {
			BTRCollectionViewCell *currentCell = (BTRCollectionViewCell *)obj;
			if (currentCell == cell) {
				indexPath = itemKey.indexPath;
				*stop = YES;
			}
		}
	}];
	return indexPath;
}

- (BTRCollectionViewCell *)cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	__block BTRCollectionViewCell *cell = nil;
	[_allVisibleViewsDict enumerateKeysAndObjectsWithOptions:0 usingBlock:^(id key, id obj, BOOL *stop) {
		BTRCollectionViewItemKey *itemKey = (BTRCollectionViewItemKey *)key;
		if (itemKey.type == BTRCollectionViewItemTypeCell) {
			if ([itemKey.indexPath isEqual:indexPath]) {
				cell = obj;
				*stop = YES;
			}
		}
	}];
	return cell;
}

- (NSArray *)indexPathsForVisibleItems {
	NSArray *visibleCells = self.visibleCells;
	NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:visibleCells.count];
    
    [visibleCells enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		BTRCollectionViewCell *cell = (BTRCollectionViewCell *)obj;
        [indexPaths addObject:cell.layoutAttributes.indexPath];
    }];
    
	return indexPaths;
}

- (NSArray *)indexPathsForSelectedItems {
	return [_indexPathsForSelectedItems copy];
}

- (void)scrollToItemAtIndexPath:(NSIndexPath *)indexPath atScrollPosition:(BTRCollectionViewScrollPosition)scrollPosition animated:(BOOL)animated {
	
	if (scrollPosition == BTRCollectionViewScrollPositionNone) return;
	// Make sure layout is valid before scrolling
	[self layout];
	
	BTRCollectionViewLayoutAttributes *layoutAttributes = [self.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath];
	
    if (layoutAttributes) {
        CGRect targetRect = [self makeRect:layoutAttributes.frame toScrollPosition:scrollPosition];
        [self btr_scrollRectToVisible:targetRect animated:animated];
    }
//	BTRCollectionViewLayoutAttributes *layoutAttributes = [self.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath];
//	if (layoutAttributes) {
//		CGRect targetRect = layoutAttributes.frame;
//		
//		// TODO: Fix this hack to apply proper margins
//		if ([self.collectionViewLayout isKindOfClass:[BTRCollectionViewFlowLayout class]]) {
//			BTRCollectionViewFlowLayout *flowLayout = (BTRCollectionViewFlowLayout *)self.collectionViewLayout;
//			targetRect.size.height += flowLayout.scrollDirection == BTRCollectionViewScrollDirectionVertical ? flowLayout.minimumLineSpacing : flowLayout.minimumInteritemSpacing;
//			targetRect.size.width += flowLayout.scrollDirection == BTRCollectionViewScrollDirectionVertical ? flowLayout.minimumInteritemSpacing : flowLayout.minimumLineSpacing;
//		}
//		targetRect = [self makeRect:targetRect toScrollPosition:scrollPosition];
//		[self btr_scrollRectToVisible:targetRect animated:animated];
//	}
}

- (CGRect)makeRect:(CGRect)targetRect toScrollPosition:(BTRCollectionViewScrollPosition)scrollPosition {
    // split parameters
    NSUInteger verticalPosition = scrollPosition & 0x07;   // 0000 0111
    NSUInteger horizontalPosition = scrollPosition & 0x38; // 0011 1000
    
    if (verticalPosition != BTRCollectionViewScrollPositionNone
        && verticalPosition != BTRCollectionViewScrollPositionTop
        && verticalPosition != BTRCollectionViewScrollPositionCenteredVertically
        && verticalPosition != BTRCollectionViewScrollPositionBottom)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"BTRCollectionViewScrollPosition: attempt to use a scroll position with multiple vertical positioning styles" userInfo:nil];
    }
    
    if(horizontalPosition != BTRCollectionViewScrollPositionNone
       && horizontalPosition != BTRCollectionViewScrollPositionLeft
       && horizontalPosition != BTRCollectionViewScrollPositionCenteredHorizontally
       && horizontalPosition != BTRCollectionViewScrollPositionRight) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"BTRCollectionViewScrollPosition: attempt to use a scroll position with multiple horizontal positioning styles" userInfo:nil];
    }
    
    CGRect frame = self.visibleRect;
    
    CGFloat calculateX;
    CGFloat calculateY;
    
    switch(verticalPosition){
        case BTRCollectionViewScrollPositionCenteredVertically:
            calculateY = targetRect.origin.y-((frame.size.height/2)-(targetRect.size.height/2));
            targetRect = CGRectMake(targetRect.origin.x, calculateY, targetRect.size.width, frame.size.height);
            break;
        case BTRCollectionViewScrollPositionTop:
            targetRect = CGRectMake(targetRect.origin.x, targetRect.origin.y, targetRect.size.width, frame.size.height);
            break;
            
        case BTRCollectionViewScrollPositionBottom:
            calculateY = targetRect.origin.y-(frame.size.height-targetRect.size.height);
            targetRect = CGRectMake(targetRect.origin.x, calculateY, targetRect.size.width, frame.size.height);
            break;
    };
    
    switch(horizontalPosition){
        case BTRCollectionViewScrollPositionCenteredHorizontally:
            calculateX = targetRect.origin.x-((frame.size.width/2)-(targetRect.size.width/2));
            targetRect = CGRectMake(calculateX, targetRect.origin.y, frame.size.width, targetRect.size.height);
            break;
            
        case BTRCollectionViewScrollPositionLeft:
            targetRect = CGRectMake(targetRect.origin.x, targetRect.origin.y, frame.size.width, targetRect.size.height);
            break;
            
        case BTRCollectionViewScrollPositionRight:
            calculateX = targetRect.origin.x-(frame.size.width-targetRect.size.width);
            targetRect = CGRectMake(calculateX, targetRect.origin.y, frame.size.width, targetRect.size.height);
            break;
    };
    
    return targetRect;
}

#pragma mark - Mouse Event Handling

- (void)mouseDown:(NSEvent *)theEvent {
	[super mouseDown:theEvent];
	if (!self.allowsSelection) return;
	//
	// A note about this whole "highlighted" state thing that seems somewhat confusing
	// The highlighted state occurs on mouseDown:. It is the intermediary step to either
	// selecting or deselecting an item. Items that are unhighlighted in this method are
	// queued to be deselected in mouseUp:, and items that are selected are queued to be
	// selected in mouseUp:
	//
	NSUInteger modifierFlags = [[NSApp currentEvent] modifierFlags];
	BOOL commandKeyDown = ((modifierFlags & NSCommandKeyMask) == NSCommandKeyMask);
	BOOL shiftKeyDown = ((modifierFlags & NSShiftKeyMask) == NSShiftKeyMask);
	
	CGPoint location = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	NSIndexPath *indexPath = [self indexPathForItemAtPoint:location];
	BOOL alreadySelected = [_indexPathsForSelectedItems containsObject:indexPath];
	
	// Unhighlights everything that's currently selected
	void (^unhighlightAllBlock)(void) = ^{
		_indexPathsForNewlyUnhighlightedItems = [NSMutableSet setWithArray:_indexPathsForSelectedItems];
		[self unhighlightAllItems];
	};
	// Convenience block for building the highlighted items array and highlighting an item
	void (^highlightBlock)(NSIndexPath *) = ^(NSIndexPath *path){
		if ([self highlightItemAtIndexPath:path
								  animated:self.animatesSelection
							scrollPosition:BTRCollectionViewScrollPositionNone
							notifyDelegate:YES]) {
			if (!_indexPathsForNewlyHighlightedItems) {
				_indexPathsForNewlyHighlightedItems = [NSMutableSet setWithObject:path];
			} else {
				[_indexPathsForNewlyHighlightedItems addObject:path];
			}
		}
	};
	// If the background was clicked, unhighlight everything
	if (!indexPath) {
		unhighlightAllBlock();
		return;
	}
	// If command is not being pressed, unhighlight everything
	// before highlighting the new item
	if (!commandKeyDown)
		unhighlightAllBlock();
	// If a modifier key is being held down and the item is already selected,
	// we want to inverse the selection and deselect it
	if (commandKeyDown && alreadySelected) {
		_indexPathsForNewlyUnhighlightedItems = [NSMutableSet setWithObject:indexPath];
		[self unhighlightItemAtIndexPath:indexPath animated:self.animatesSelection notifyDelegate:YES];
	} else {
		// If nothing has been highlighted yet and shift is not being pressed,
		// just highlight the single item
		if (!shiftKeyDown) {
			highlightBlock(indexPath);
		} else if (shiftKeyDown && [_indexPathsForSelectedItems count]) {
			// When shift is being held, we want multiple selection behaviour
			// Take two index paths, the first index path that was selected and the newly selected index path
			NSIndexPath *one = _indexPathsForSelectedItems[0];
			NSIndexPath *two = indexPath;
			NSIndexPath *startingIndexPath = nil;
			NSIndexPath *endingIndexPath = nil;
			// Compare to see which index comes first, and decide what the starting and ending index paths are
			// (the starting path should always be the lower one)
			if ([one compare:two] == NSOrderedAscending) {
				startingIndexPath = one;
				endingIndexPath = two;
			} else {
				startingIndexPath = two;
				endingIndexPath = one;
			}
			NSMutableArray *selectionRange = [NSMutableArray array];
			// Iterate through each section until reaching the section of the ending index path
			for (NSUInteger i = startingIndexPath.section; i <= endingIndexPath.section; i++) {
				NSUInteger numberOfItems = [self numberOfItemsInSection:i];
				NSUInteger currentItem = 0;
				// If we're currently iterating the last section, make sure the iteration
				// stops at the index of the ending index path
				if (i == endingIndexPath.section)
					numberOfItems = endingIndexPath.row + 1;
				// If we're iterating the first section, make sure the iteration starts
				// at the index of the starting index path
				if (i == startingIndexPath.section)
					currentItem = startingIndexPath.row;
				for (NSUInteger j = currentItem; j < numberOfItems; j++) {
					NSIndexPath *indexPath = [NSIndexPath btr_indexPathForItem:j inSection:i];
					[selectionRange addObject:indexPath];
				}
			}
			// Highlight the entire range
			[selectionRange enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, NSUInteger idx, BOOL *stop) {
				for (NSIndexPath *indexPath in selectionRange) {
					highlightBlock(indexPath);
				}
			}];
		}
	}
	
}

- (void)mouseUp:(NSEvent *)theEvent {
	[super mouseUp:theEvent];
	if (!self.allowsSelection) return;
	// "Commit" all the changes by selecting/deselecting the highlight/unhighlighted cells
	[_indexPathsForNewlyUnhighlightedItems enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, BOOL *stop) {
		[self deselectItemAtIndexPath:indexPath animated:self.animatesSelection notifyDelegate:YES];
	}];
	[_indexPathsForNewlyHighlightedItems enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, BOOL *stop) {
		[self selectItemAtIndexPath:indexPath
						   animated:self.animatesSelection
					 scrollPosition:BTRCollectionViewScrollPositionNone
					 notifyDelegate:YES];
	}];
	_indexPathsForNewlyHighlightedItems = nil;
	_indexPathsForNewlyUnhighlightedItems = nil;
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	[super mouseDragged:theEvent];
	if (!self.allowsSelection) return;
	// TODO: Implement a dragging rectangle
}

#pragma mark - Key Events

// Stubs for keyboard event implementation

- (void)keyDown:(NSEvent *)theEvent {
	[self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
}

- (void)moveUp:(id)sender {
	
}

- (void)moveDown:(id)sender {
	
}

#pragma mark - Selection and Highlighting

- (void)selectItemAtIndexPath:(NSIndexPath *)indexPath
					 animated:(BOOL)animated
			   scrollPosition:(BTRCollectionViewScrollPosition)scrollPosition
			   notifyDelegate:(BOOL)notifyDelegate {
	// Deselect everything else if only single selection is supported
	if (!self.allowsMultipleSelection) {
		[[_indexPathsForSelectedItems copy] enumerateObjectsUsingBlock:^(NSIndexPath *selectedIndexPath, NSUInteger idx, BOOL *stop) {
			if (![indexPath isEqual:selectedIndexPath]) {
				[self deselectItemAtIndexPath:selectedIndexPath animated:animated notifyDelegate:notifyDelegate];
			}
		}];
	}
	BOOL shouldSelect = YES;
	if (notifyDelegate && _collectionViewFlags.delegateShouldSelectItemAtIndexPath) {
		shouldSelect = [self.delegate collectionView:self shouldSelectItemAtIndexPath:indexPath];
	}
	if (shouldSelect) {
		BTRCollectionViewCell *selectedCell = [self cellForItemAtIndexPath:indexPath];
		if (animated) {
			[NSView btr_animate:^{
				selectedCell.selected = YES;
			}];
		} else {
			selectedCell.selected = YES;
		}
		[_indexPathsForSelectedItems addObject:indexPath];
	
		if (scrollPosition != BTRCollectionViewScrollPositionNone) {
			[self scrollToItemAtIndexPath:indexPath atScrollPosition:scrollPosition animated:animated];
		}
		
		if (notifyDelegate && _collectionViewFlags.delegateDidSelectItemAtIndexPath) {
			[self.delegate collectionView:self didSelectItemAtIndexPath:indexPath];
		}
	}
	[self unhighlightItemAtIndexPath:indexPath animated:animated notifyDelegate:YES];
}

- (void)selectItemAtIndexPath:(NSIndexPath *)indexPath
					 animated:(BOOL)animated
			   scrollPosition:(BTRCollectionViewScrollPosition)scrollPosition {
	[self selectItemAtIndexPath:indexPath animated:animated scrollPosition:scrollPosition notifyDelegate:NO];
}

- (void)deselectItemAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated {
	[self deselectItemAtIndexPath:indexPath animated:animated notifyDelegate:NO];
}

- (BOOL)deselectItemAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated notifyDelegate:(BOOL)notify {
	if ([_indexPathsForSelectedItems containsObject:indexPath]) {
		BOOL shouldDeselect = YES;
		if (notify && _collectionViewFlags.delegateShouldDeselectItemAtIndexPath) {
			shouldDeselect = [self.delegate collectionView:self shouldDeselectItemAtIndexPath:indexPath];
		}
		if (shouldDeselect) {
			BTRCollectionViewCell *selectedCell = [self cellForItemAtIndexPath:indexPath];
			if (animated) {
				[NSView btr_animate:^{
					selectedCell.selected = NO;
				}];
			} else {
				selectedCell.selected = NO;
			}
			[self unhighlightItemAtIndexPath:indexPath animated:animated notifyDelegate:notify];
		}
		[_indexPathsForSelectedItems removeObject:indexPath];
		
		if (notify && _collectionViewFlags.delegateDidDeselectItemAtIndexPath) {
			[self.delegate collectionView:self didDeselectItemAtIndexPath:indexPath];
		}
		
		return shouldDeselect;
	}
	return NO;
}

- (BOOL)highlightItemAtIndexPath:(NSIndexPath *)indexPath
						animated:(BOOL)animated
				  scrollPosition:(BTRCollectionViewScrollPosition)scrollPosition
				  notifyDelegate:(BOOL)notifyDelegate {
	BOOL shouldHighlight = YES;
	if (notifyDelegate && _collectionViewFlags.delegateShouldHighlightItemAtIndexPath) {
		shouldHighlight = [self.delegate collectionView:self shouldHighlightItemAtIndexPath:indexPath];
	}
	if (shouldHighlight) {
		BTRCollectionViewCell *highlightedCell = [self cellForItemAtIndexPath:indexPath];
		if (animated) {
			[NSView btr_animate:^{
				highlightedCell.highlighted = YES;
			}];
		} else {
			highlightedCell.highlighted = YES;
		}
		[_indexPathsForHighlightedItems addObject:indexPath];
		if (notifyDelegate && _collectionViewFlags.delegateDidHighlightItemAtIndexPath) {
			[self.delegate collectionView:self didHighlightItemAtIndexPath:indexPath];
		}
		[self scrollToItemAtIndexPath:indexPath atScrollPosition:scrollPosition animated:animated];
	}
	return shouldHighlight;
}

- (void)unhighlightItemAtIndexPath:(NSIndexPath *)indexPath
						  animated:(BOOL)animated
					notifyDelegate:(BOOL)notifyDelegate {
	if ([_indexPathsForHighlightedItems containsObject:indexPath]) {
		BTRCollectionViewCell *highlightedCell = [self cellForItemAtIndexPath:indexPath];
		if (animated) {
			[NSView btr_animate:^{
				highlightedCell.highlighted = NO;
			}];
		} else {
			highlightedCell.highlighted = NO;
		}
		[_indexPathsForHighlightedItems removeObject:indexPath];
		if (notifyDelegate && _collectionViewFlags.delegateDidUnhighlightItemAtIndexPath) {
			[self.delegate collectionView:self didUnhighlightItemAtIndexPath:indexPath];
		}
	}
}

- (void)unhighlightAllItems {
	[[_indexPathsForHighlightedItems copy] enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, NSUInteger idx, BOOL *stop) {
		[self unhighlightItemAtIndexPath:indexPath animated:NO notifyDelegate:YES];
	}];
}

- (void)deselectAllItems {
	[[_indexPathsForSelectedItems copy] enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, NSUInteger idx, BOOL *stop) {
		[self deselectItemAtIndexPath:indexPath animated:NO notifyDelegate:YES];
	}];
}

#pragma mark - Update Grid

- (void)insertSections:(NSIndexSet *)sections {
	[self updateSections:sections updateAction:BTRCollectionUpdateActionInsert];
}

- (void)deleteSections:(NSIndexSet *)sections {
	[self updateSections:sections updateAction:BTRCollectionUpdateActionDelete];
}

- (void)reloadSections:(NSIndexSet *)sections {
	[self updateSections:sections updateAction:BTRCollectionUpdateActionReload];
}

- (void)moveSection:(NSUInteger)section toSection:(NSUInteger)newSection {
	NSMutableArray *moveUpdateItems = [self arrayForUpdateAction:BTRCollectionUpdateActionMove];
	NSIndexPath *from = [NSIndexPath btr_indexPathForItem:NSNotFound inSection:section];
	NSIndexPath *to = [NSIndexPath btr_indexPathForItem:NSNotFound inSection:newSection];
	BTRCollectionViewUpdateItem *update = [[BTRCollectionViewUpdateItem alloc] initWithInitialIndexPath:from finalIndexPath:to updateAction:BTRCollectionUpdateActionMove];
	[moveUpdateItems addObject:update];
	if (!_collectionViewFlags.updating) {
		[self setupCellAnimations];
		[self endItemAnimations];
	}
}

- (void)insertItemsAtIndexPaths:(NSArray *)indexPaths {
	[self updateRowsAtIndexPaths:indexPaths updateAction:BTRCollectionUpdateActionInsert];
}

- (void)deleteItemsAtIndexPaths:(NSArray *)indexPaths {
	[self updateRowsAtIndexPaths:indexPaths updateAction:BTRCollectionUpdateActionDelete];
}

- (void)reloadItemsAtIndexPaths:(NSArray *)indexPaths {
	[self updateRowsAtIndexPaths:indexPaths updateAction:BTRCollectionUpdateActionReload];
}

- (void)moveItemAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath {
	NSMutableArray *moveUpdateItems = [self arrayForUpdateAction:BTRCollectionUpdateActionMove];
	BTRCollectionViewUpdateItem *update = [[BTRCollectionViewUpdateItem alloc] initWithInitialIndexPath:indexPath finalIndexPath:newIndexPath updateAction:BTRCollectionUpdateActionMove];
	[moveUpdateItems addObject:update];
	if (!_collectionViewFlags.updating) {
		[self setupCellAnimations];
		[self endItemAnimations];
	}
}

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(void))completion {
	[self setupCellAnimations];
	
	if (updates) updates();
	if (completion) _updateCompletionHandler = [completion copy];
	
	[self endItemAnimations];
}

#pragma mark - Properties

- (void)setBackgroundView:(NSView *)backgroundView {
	if (backgroundView != _backgroundView) {
		[_backgroundView removeFromSuperview];
		_backgroundView = backgroundView;
		backgroundView.frame = self.visibleRect;
		backgroundView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
		[self addSubview:backgroundView positioned:NSWindowBelow relativeTo:nil];
	}
}

- (void)setCollectionViewLayout:(BTRCollectionViewLayout *)layout animated:(BOOL)animated {
	if (layout == _layout) return;
	
	// Should this be in here?
	
//	if (CGRectIsEmpty(self.bounds) || !_collectionViewFlags.doneFirstLayout) {
//		_layout.collectionView = nil;
//		_collectionViewData = nil;
//		_collectionViewData = [[BTRCollectionViewData alloc] initWithCollectionView:self layout:layout];
//		_layout = layout;
//		
//		return;
//	}
	
	layout.collectionView = self;
	
	_collectionViewData = [[BTRCollectionViewData alloc] initWithCollectionView:self layout:layout];
	[_collectionViewData prepareToLoadData];
	
	NSArray *previouslySelectedIndexPaths = [self indexPathsForSelectedItems];
	NSMutableSet *selectedCellKeys = [NSMutableSet setWithCapacity:[previouslySelectedIndexPaths count]];
	
	for (NSIndexPath *indexPath in previouslySelectedIndexPaths) {
		[selectedCellKeys addObject:[BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:indexPath]];
	}
	
	NSArray *previouslyVisibleItemsKeys = [_allVisibleViewsDict allKeys];
	NSSet *previouslyVisibleItemsKeysSet = [NSSet setWithArray:previouslyVisibleItemsKeys];
	NSMutableSet *previouslyVisibleItemsKeysSetMutable = [NSMutableSet setWithArray:previouslyVisibleItemsKeys];
	
	if ([selectedCellKeys intersectsSet:selectedCellKeys]) {
		[previouslyVisibleItemsKeysSetMutable intersectSet:previouslyVisibleItemsKeysSetMutable];
	}
	
	//[self bringSubviewToFront: _allVisibleViewsDict[[previouslyVisibleItemsKeysSetMutable anyObject]]];
	
	CGPoint targetOffset = CGPointZero;
	CGPoint centerPoint = CGPointMake(self.bounds.origin.x + self.bounds.size.width / 2.0,
									  self.bounds.origin.y + self.bounds.size.height / 2.0);
	NSIndexPath *centerItemIndexPath = [self indexPathForItemAtPoint:centerPoint];
	
	if (!centerItemIndexPath) {
		NSArray *visibleItems = [self indexPathsForVisibleItems];
		if (visibleItems.count > 0) {
			centerItemIndexPath = visibleItems[visibleItems.count / 2];
		}
	}
	
	if (centerItemIndexPath) {
		BTRCollectionViewLayoutAttributes *layoutAttributes = [layout layoutAttributesForItemAtIndexPath:centerItemIndexPath];
		if (layoutAttributes) {
			BTRCollectionViewScrollPosition scrollPosition = BTRCollectionViewScrollPositionCenteredVertically | BTRCollectionViewScrollPositionCenteredHorizontally;
			CGRect targetRect = [self makeRect:layoutAttributes.frame toScrollPosition:scrollPosition];
			targetOffset = CGPointMake(fmax(0.0, targetRect.origin.x), fmax(0.0, targetRect.origin.y));
		}
	}
	
	CGRect newlyBounds = CGRectMake(targetOffset.x, targetOffset.y, self.bounds.size.width, self.bounds.size.height);
	NSArray *newlyVisibleLayoutAttrs = [_collectionViewData layoutAttributesForElementsInRect:newlyBounds];
	
	NSMutableDictionary *layoutInterchangeData = [NSMutableDictionary dictionaryWithCapacity:
												  [newlyVisibleLayoutAttrs count] + [previouslyVisibleItemsKeysSet count]];
	
	NSMutableSet *newlyVisibleItemsKeys = [NSMutableSet set];
	for (BTRCollectionViewLayoutAttributes *attr in newlyVisibleLayoutAttrs) {
		BTRCollectionViewItemKey *newKey = [BTRCollectionViewItemKey collectionItemKeyForLayoutAttributes:attr];
		[newlyVisibleItemsKeys addObject:newKey];
		
		BTRCollectionViewLayoutAttributes *prevAttr = nil;
		BTRCollectionViewLayoutAttributes *newAttr = nil;
		
		if (newKey.type == BTRCollectionViewItemTypeDecorationView) {
			prevAttr = [self.collectionViewLayout layoutAttributesForDecorationViewOfKind:attr.representedElementKind
																			  atIndexPath:newKey.indexPath];
			newAttr = [layout layoutAttributesForDecorationViewOfKind:attr.representedElementKind
														  atIndexPath:newKey.indexPath];
		}
		else if(newKey.type == BTRCollectionViewItemTypeCell) {
			prevAttr = [self.collectionViewLayout layoutAttributesForItemAtIndexPath:newKey.indexPath];
			newAttr = [layout layoutAttributesForItemAtIndexPath:newKey.indexPath];
		}
		else {
			prevAttr = [self.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:attr.representedElementKind
																				 atIndexPath:newKey.indexPath];
			newAttr = [layout layoutAttributesForSupplementaryViewOfKind:attr.representedElementKind
															 atIndexPath:newKey.indexPath];
		}
		
		if (prevAttr != nil && newAttr != nil) {
			layoutInterchangeData[newKey] = [NSDictionary dictionaryWithObjects:@[prevAttr,newAttr]
																		forKeys:@[BTRCollectionViewPreviousLayoutInfoKey, BTRCollectionViewNewLayoutInfoKey]];
		}
	}
	
	for(BTRCollectionViewItemKey *key in previouslyVisibleItemsKeysSet) {
		BTRCollectionViewLayoutAttributes *prevAttr = nil;
		BTRCollectionViewLayoutAttributes *newAttr = nil;
		
		if(key.type == BTRCollectionViewItemTypeDecorationView) {
			BTRCollectionReusableView *decorView = _allVisibleViewsDict[key];
			prevAttr = [self.collectionViewLayout layoutAttributesForDecorationViewOfKind:decorView.reuseIdentifier
																			  atIndexPath:key.indexPath];
			newAttr = [layout layoutAttributesForDecorationViewOfKind:decorView.reuseIdentifier
														  atIndexPath:key.indexPath];
		}
		else if(key.type == BTRCollectionViewItemTypeCell) {
			prevAttr = [self.collectionViewLayout layoutAttributesForItemAtIndexPath:key.indexPath];
			newAttr = [layout layoutAttributesForItemAtIndexPath:key.indexPath];
		}
		else if(key.type == BTRCollectionViewItemTypeSupplementaryView) {
			BTRCollectionReusableView* suuplView = _allVisibleViewsDict[key];
			prevAttr = [self.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:suuplView.layoutAttributes.representedElementKind
																				 atIndexPath:key.indexPath];
			newAttr = [layout layoutAttributesForSupplementaryViewOfKind:suuplView.layoutAttributes.representedElementKind
															 atIndexPath:key.indexPath];
		}
		
		layoutInterchangeData[key] = [NSDictionary dictionaryWithObjects:@[prevAttr,newAttr]
																 forKeys:@[BTRCollectionViewPreviousLayoutInfoKey, BTRCollectionViewNewLayoutInfoKey]];
	}
	
	for (BTRCollectionViewItemKey *key in [layoutInterchangeData keyEnumerator]) {
		if(key.type == BTRCollectionViewItemTypeCell) {
			BTRCollectionViewCell* cell = _allVisibleViewsDict[key];
			
			if (!cell) {
				cell = [self createPreparedCellForItemAtIndexPath:key.indexPath
											 withLayoutAttributes:layoutInterchangeData[key][BTRCollectionViewPreviousLayoutInfoKey]];
				_allVisibleViewsDict[key] = cell;
				[self addCollectionViewSubview:cell];
			}
			else [cell applyLayoutAttributes:layoutInterchangeData[key][BTRCollectionViewPreviousLayoutInfoKey]];
		}
		else if(key.type == BTRCollectionViewItemTypeSupplementaryView) {
			BTRCollectionReusableView *view = _allVisibleViewsDict[key];
			if (!view) {
				BTRCollectionViewLayoutAttributes *attrs = layoutInterchangeData[key][BTRCollectionViewPreviousLayoutInfoKey];
				view = [self createPreparedSupplementaryViewForElementOfKind:attrs.representedElementKind
																 atIndexPath:attrs.indexPath
														withLayoutAttributes:attrs];
				_allVisibleViewsDict[key] = view;
				[self addCollectionViewSubview:view];
			}
		}
		else if(key.type == BTRCollectionViewItemTypeDecorationView) {
			BTRCollectionReusableView *view = _allVisibleViewsDict[key];
			if (!view) {
				BTRCollectionViewLayoutAttributes *attrs = layoutInterchangeData[key][BTRCollectionViewPreviousLayoutInfoKey];
				view = [self dequeueReusableOrCreateDecorationViewOfKind:attrs.reuseIdentifier forIndexPath:attrs.indexPath];
				_allVisibleViewsDict[key] = view;
				[self addCollectionViewSubview:view];
			}
		}
	};
	
	CGRect contentRect = [_collectionViewData collectionViewContentRect];
	
	void (^applyNewLayoutBlock)(void) = ^{
		NSEnumerator *keys = [layoutInterchangeData keyEnumerator];
		for(BTRCollectionViewItemKey *key in keys) {
			// TODO: This is most likely not 100% the same time as in UICollectionView. Needs to be investigated.
			BTRCollectionViewCell *cell = (BTRCollectionViewCell *)_allVisibleViewsDict[key];
			[cell willTransitionFromLayout:_layout toLayout:layout];
			[cell applyLayoutAttributes:layoutInterchangeData[key][BTRCollectionViewNewLayoutInfoKey]];
			[cell didTransitionFromLayout:_layout toLayout:layout];
		}
	};
	
	void (^freeUnusedViews)(void) = ^ {
		NSMutableSet *toRemove =  [NSMutableSet set];
		for (BTRCollectionViewItemKey *key in [_allVisibleViewsDict keyEnumerator]) {
			if (![newlyVisibleItemsKeys containsObject:key]) {
				if (key.type == BTRCollectionViewItemTypeCell) {
					[self reuseCell:_allVisibleViewsDict[key]];
					[toRemove addObject:key];
				}
				else if(key.type == BTRCollectionViewItemTypeSupplementaryView) {
					[self reuseSupplementaryView:_allVisibleViewsDict[key]];
					[toRemove addObject:key];
				}
				else if(key.type == BTRCollectionViewItemTypeDecorationView) {
					[self reuseDecorationView:_allVisibleViewsDict[key]];
					[toRemove addObject:key];
				}
			}
		}
		
		for(id key in toRemove)
			[_allVisibleViewsDict removeObjectForKey:key];
	};
	
	if(animated) {
		[NSView btr_animateWithDuration:0.3f animations:^{
			_collectionViewFlags.updatingLayout = YES;
			self.frameSize = contentRect.size; // TODO?
			applyNewLayoutBlock();
		} completion:^{
			freeUnusedViews();
			_collectionViewFlags.updatingLayout = NO;
		}];
	}
	else {
		applyNewLayoutBlock();
		freeUnusedViews();
	}
	
	_layout.collectionView = nil;
	_layout = layout;
}

- (void)setCollectionViewLayout:(BTRCollectionViewLayout *)layout {
	[self setCollectionViewLayout:layout animated:NO];
}

- (void)setDelegate:(id<BTRCollectionViewDelegate>)delegate {
	if (_delegate != delegate) {
		_delegate = delegate;
		
		//	Managing the Selected Cells
		_collectionViewFlags.delegateShouldSelectItemAtIndexPath = [_delegate respondsToSelector:@selector(collectionView:shouldSelectItemAtIndexPath:)];
		_collectionViewFlags.delegateDidSelectItemAtIndexPath = [_delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)];
		_collectionViewFlags.delegateShouldDeselectItemAtIndexPath = [_delegate respondsToSelector:@selector(collectionView:shouldDeselectItemAtIndexPath:)];
		_collectionViewFlags.delegateDidDeselectItemAtIndexPath = [_delegate respondsToSelector:@selector(collectionView:didDeselectItemAtIndexPath:)];
		
		//	Managing Cell Highlighting
		_collectionViewFlags.delegateShouldHighlightItemAtIndexPath = [_delegate respondsToSelector:@selector(collectionView:shouldHighlightItemAtIndexPath:)];
		_collectionViewFlags.delegateDidHighlightItemAtIndexPath = [_delegate respondsToSelector:@selector(collectionView:didHighlightItemAtIndexPath:)];
		_collectionViewFlags.delegateDidUnhighlightItemAtIndexPath = [_delegate respondsToSelector:@selector(collectionView:didUnhighlightItemAtIndexPath:)];
		
		//	Tracking the Removal of Views
		_collectionViewFlags.delegateDidEndDisplayingCell = [_delegate respondsToSelector:@selector(collectionView:didEndDisplayingCell:forItemAtIndexPath:)];
		_collectionViewFlags.delegateDidEndDisplayingSupplementaryView = [_delegate respondsToSelector:@selector(collectionView:didEndDisplayingSupplementaryView:forElementOfKind:atIndexPath:)];
	}
}

- (void)setDataSource:(id<BTRCollectionViewDataSource>)dataSource {
	if (dataSource != _dataSource) {
		_dataSource = dataSource;
		
		//	Getting Item and Section Metrics
		_collectionViewFlags.dataSourceNumberOfSections = [_dataSource respondsToSelector:@selector(numberOfSectionsInCollectionView:)];
		
		//	Getting Views for Items
		_collectionViewFlags.dataSourceViewForSupplementaryElement = [_dataSource respondsToSelector:@selector(collectionView:viewForSupplementaryElementOfKind:atIndexPath:)];
	}
}

- (void)setAllowsMultipleSelection:(BOOL)allowsMultipleSelection {
	if (_allowsMultipleSelection != allowsMultipleSelection) {
		_allowsMultipleSelection = allowsMultipleSelection;
		[[_indexPathsForSelectedItems copy] enumerateObjectsUsingBlock:^(NSIndexPath *selectedIndexPath, NSUInteger idx, BOOL *stop) {
			if (_indexPathsForSelectedItems.count == 1) {
				*stop = YES;
			} else {
				[self deselectItemAtIndexPath:selectedIndexPath animated:YES notifyDelegate:YES];
			}
		}];
	}
}

#pragma mark - Private

- (void)invalidateLayout {
	[self.collectionViewLayout invalidateLayout];
	[self.collectionViewData invalidate];
}

- (void)updateVisibleCells {
	// Build an array of the items that need to be made visible
	NSArray *layoutAttributesArray = [_collectionViewData layoutAttributesForElementsInRect:self.visibleRect];
	
	if (layoutAttributesArray == nil || [layoutAttributesArray count] == 0) {
        // If our layout source isn't providing any layout information, we should just
        // stop, otherwise we'll blow away all the currently existing cells.
        return;
    }
	
	// create ItemKey/Attributes dictionary
	NSMutableDictionary *itemKeysToAddDict = [NSMutableDictionary dictionary];
	
	
	// Add new cells.
    for (BTRCollectionViewLayoutAttributes *layoutAttributes in layoutAttributesArray) {
        BTRCollectionViewItemKey *itemKey = [BTRCollectionViewItemKey collectionItemKeyForLayoutAttributes:layoutAttributes];
        itemKeysToAddDict[itemKey] = layoutAttributes;
		
        // check if cell is in visible dict; add it if not.
        BTRCollectionReusableView *view = _allVisibleViewsDict[itemKey];
        if (!view) {
            if (itemKey.type == BTRCollectionViewItemTypeCell) {
                view = [self createPreparedCellForItemAtIndexPath:itemKey.indexPath withLayoutAttributes:layoutAttributes];
				
            } else if (itemKey.type == BTRCollectionViewItemTypeSupplementaryView) {
                view = [self createPreparedSupplementaryViewForElementOfKind:layoutAttributes.representedElementKind
																 atIndexPath:layoutAttributes.indexPath
														withLayoutAttributes:layoutAttributes];
			} else if (itemKey.type == BTRCollectionViewItemTypeDecorationView) {
				view = [self dequeueReusableOrCreateDecorationViewOfKind:layoutAttributes.reuseIdentifier forIndexPath:layoutAttributes.indexPath];
			}
			
			// Supplementary views are optional
			if (view) {
				_allVisibleViewsDict[itemKey] = view;
				[self addCollectionViewSubview:view];
				
                // Always apply attributes.
                [view applyLayoutAttributes:layoutAttributes];
			}
        }else {
            // just update cell
            [view applyLayoutAttributes:layoutAttributes];
        }
    }
	
	// Detect what items should be removed and queued back.
    NSMutableSet *allVisibleItemKeys = [NSMutableSet setWithArray:[_allVisibleViewsDict allKeys]];
    [allVisibleItemKeys minusSet:[NSSet setWithArray:[itemKeysToAddDict allKeys]]];
	
    // Finally remove views that have not been processed and prepare them for re-use.
    for (BTRCollectionViewItemKey *itemKey in allVisibleItemKeys) {
        BTRCollectionReusableView *reusableView = _allVisibleViewsDict[itemKey];
        if (reusableView) {
            [reusableView removeFromSuperview];
            [_allVisibleViewsDict removeObjectForKey:itemKey];
            if (itemKey.type == BTRCollectionViewItemTypeCell) {
                if (_collectionViewFlags.delegateDidEndDisplayingCell) {
                    [self.delegate collectionView:self didEndDisplayingCell:(BTRCollectionViewCell *)reusableView forItemAtIndexPath:itemKey.indexPath];
                }
                [self reuseCell:(BTRCollectionViewCell *)reusableView];
            }
            else if(itemKey.type == BTRCollectionViewItemTypeSupplementaryView) {
                if (_collectionViewFlags.delegateDidEndDisplayingSupplementaryView) {
                    [self.delegate collectionView:self didEndDisplayingSupplementaryView:reusableView forElementOfKind:itemKey.identifier atIndexPath:itemKey.indexPath];
                }
                [self reuseSupplementaryView:reusableView];
            }
            else if(itemKey.type == BTRCollectionViewItemTypeDecorationView) {
                [self reuseDecorationView:reusableView];
            }
        }
    }
}

- (BTRCollectionViewCell *)createPreparedCellForItemAtIndexPath:(NSIndexPath *)indexPath withLayoutAttributes:(BTRCollectionViewLayoutAttributes *)layoutAttributes {
	BTRCollectionViewCell *cell = [self.dataSource collectionView:self cellForItemAtIndexPath:indexPath];
	
	[cell applyLayoutAttributes:layoutAttributes];
	
	[cell setHighlighted:[_indexPathsForHighlightedItems containsObject:indexPath]];
	[cell setSelected:[_indexPathsForSelectedItems containsObject:indexPath]];
	
	return cell;
}

- (BTRCollectionReusableView *)createPreparedSupplementaryViewForElementOfKind:(NSString *)kind
																   atIndexPath:(NSIndexPath *)indexPath
														  withLayoutAttributes:(BTRCollectionViewLayoutAttributes *)layoutAttributes {
	if (_collectionViewFlags.dataSourceViewForSupplementaryElement) {
		BTRCollectionReusableView *view = [self.dataSource collectionView:self
										viewForSupplementaryElementOfKind:kind
															  atIndexPath:indexPath];
		return view;
	}
	return nil;
}

- (void)queueReusableView:(BTRCollectionReusableView *)reusableView inQueue:(NSMutableDictionary *)queue {
	NSString *cellIdentifier = reusableView.reuseIdentifier;
	NSParameterAssert([cellIdentifier length]);
	
	[reusableView removeFromSuperview];
	[reusableView prepareForReuse];
	
	NSMutableArray *reuseableViews = queue[cellIdentifier];
	if (!reuseableViews) {
		reuseableViews = [NSMutableArray array];
		queue[cellIdentifier] = reuseableViews;
	}
	[reuseableViews addObject:reusableView];
}

- (void)reuseCell:(BTRCollectionViewCell *)cell {
	[self queueReusableView:cell inQueue:_cellReuseQueues];
}

- (void)reuseSupplementaryView:(BTRCollectionReusableView *)supplementaryView {
	[self queueReusableView:supplementaryView inQueue:_supplementaryViewReuseQueues];
}

- (void)reuseDecorationView:(BTRCollectionReusableView *)decorationView {
	[self queueReusableView:decorationView inQueue:_decorationViewReuseQueues];
}

#pragma mark - Updating grid internal functionality

- (void)suspendReloads {
	_reloadingSuspendedCount++;
}

- (void)resumeReloads {
	if (_reloadingSuspendedCount > 0)
		_reloadingSuspendedCount--;
}

-(NSMutableArray *)arrayForUpdateAction:(BTRCollectionUpdateAction)updateAction {
	NSMutableArray *ret = nil;
	
	switch (updateAction) {
		case BTRCollectionUpdateActionInsert:
			if (!_insertItems) _insertItems = [NSMutableArray new];
			ret = _insertItems;
			break;
		case BTRCollectionUpdateActionDelete:
			if (!_deleteItems) _deleteItems = [NSMutableArray new];
			ret = _deleteItems;
			break;
		case BTRCollectionUpdateActionMove:
			if (_moveItems) _moveItems = [NSMutableArray new];
			ret = _moveItems;
			break;
		case BTRCollectionUpdateActionReload:
			if (!_reloadItems) _reloadItems = [NSMutableArray new];
			ret = _reloadItems;
			break;
		default: break;
	}
	return ret;
}


- (void)prepareLayoutForUpdates {
	NSMutableArray *arr = [NSMutableArray new];
	[arr addObjectsFromArray: [_originalDeleteItems sortedArrayUsingSelector:@selector(inverseCompareIndexPaths:)]];
	[arr addObjectsFromArray:[_originalInsertItems sortedArrayUsingSelector:@selector(compareIndexPaths:)]];
	[arr addObjectsFromArray:[_reloadItems sortedArrayUsingSelector:@selector(compareIndexPaths:)]];
	[arr addObjectsFromArray: [_moveItems sortedArrayUsingSelector:@selector(compareIndexPaths:)]];
	[_layout prepareForCollectionViewUpdates:arr];
}

- (void)updateWithItems:(NSArray *) items {	
	[self prepareLayoutForUpdates];

	
	NSMutableArray *animations = [[NSMutableArray alloc] init];
    NSMutableDictionary *newAllVisibleView = [[NSMutableDictionary alloc] init];
	
    NSMutableDictionary *viewsToRemove = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          [NSMutableArray array], @(BTRCollectionViewItemTypeCell),
                                          [NSMutableArray array], @(BTRCollectionViewItemTypeDecorationView),
                                          [NSMutableArray array], @(BTRCollectionViewItemTypeSupplementaryView),nil];
    
    for (BTRCollectionViewUpdateItem *updateItem in items) {
        if (updateItem.isSectionOperation) continue;
		
        if (updateItem.updateAction == BTRCollectionUpdateActionDelete) {
            NSIndexPath *indexPath = updateItem.indexPathBeforeUpdate;
			
            BTRCollectionViewLayoutAttributes *finalAttrs = [_layout finalLayoutAttributesForDisappearingItemAtIndexPath:indexPath];
            BTRCollectionViewItemKey *key = [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:indexPath];
            BTRCollectionReusableView *view = _allVisibleViewsDict[key];
            if (view) {
                BTRCollectionViewLayoutAttributes *startAttrs = view.layoutAttributes;
				
                if (!finalAttrs) {
                    finalAttrs = [startAttrs copy];
                    finalAttrs.alpha = 0;
                }
                [animations addObject:@{BTRCollectionViewViewKey: view, BTRCollectionViewPreviousLayoutInfoKey: startAttrs, BTRCollectionViewNewLayoutInfoKey: finalAttrs}];
                
                [_allVisibleViewsDict removeObjectForKey:key];
                
                [viewsToRemove[@(key.type)] addObject:view];
		
            }
            
        }
        else if(updateItem.updateAction == BTRCollectionUpdateActionInsert) {
            NSIndexPath *indexPath = updateItem.indexPathAfterUpdate;
            BTRCollectionViewItemKey *key = [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:indexPath];
            BTRCollectionViewLayoutAttributes *startAttrs = [_layout initialLayoutAttributesForAppearingItemAtIndexPath:indexPath];
            BTRCollectionViewLayoutAttributes *finalAttrs = [_layout layoutAttributesForItemAtIndexPath:indexPath];
			
            CGRect startRect = startAttrs.frame;
            CGRect finalRect = finalAttrs.frame;
			
            if(CGRectIntersectsRect(self.visibleRect, startRect) || CGRectIntersectsRect(self.visibleRect, finalRect)) {
				
                if(!startAttrs){
                    startAttrs = [finalAttrs copy];
                    startAttrs.alpha = 0;
                }
				
                BTRCollectionReusableView *view = [self createPreparedCellForItemAtIndexPath:indexPath
                                                                        withLayoutAttributes:startAttrs];
                [self addCollectionViewSubview:view];
				
                newAllVisibleView[key] = view;
                [animations addObject:@{BTRCollectionViewViewKey: view, BTRCollectionViewPreviousLayoutInfoKey: startAttrs, BTRCollectionViewNewLayoutInfoKey: finalAttrs}];
            }
        }
        else if(updateItem.updateAction == BTRCollectionUpdateActionMove) {
            NSIndexPath *indexPathBefore = updateItem.indexPathBeforeUpdate;
            NSIndexPath *indexPathAfter = updateItem.indexPathAfterUpdate;
			
            BTRCollectionViewItemKey *keyBefore = [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:indexPathBefore];
            BTRCollectionViewItemKey *keyAfter = [BTRCollectionViewItemKey collectionItemKeyForCellWithIndexPath:indexPathAfter];
            BTRCollectionReusableView *view = _allVisibleViewsDict[keyBefore];
			
            BTRCollectionViewLayoutAttributes *startAttrs = nil;
            BTRCollectionViewLayoutAttributes *finalAttrs = [_layout layoutAttributesForItemAtIndexPath:indexPathAfter];
			
            if(view) {
                startAttrs = view.layoutAttributes;
                [_allVisibleViewsDict removeObjectForKey:keyBefore];
                newAllVisibleView[keyAfter] = view;
            }
            else {
                startAttrs = [finalAttrs copy];
                startAttrs.alpha = 0;
                view = [self createPreparedCellForItemAtIndexPath:indexPathAfter withLayoutAttributes:startAttrs];
                [self addCollectionViewSubview:view];
                newAllVisibleView[keyAfter] = view;
            }
			
            [animations addObject:@{BTRCollectionViewViewKey: view, BTRCollectionViewPreviousLayoutInfoKey: startAttrs, BTRCollectionViewNewLayoutInfoKey: finalAttrs}];
        }
    }
	
    for (BTRCollectionViewItemKey *key in [_allVisibleViewsDict keyEnumerator]) {
        BTRCollectionReusableView *view = _allVisibleViewsDict[key];
		
        if (key.type == BTRCollectionViewItemTypeCell) {
            NSInteger oldGlobalIndex = [_update[BTRCollectionViewOldModelKey] globalIndexForItemAtIndexPath:key.indexPath];
            NSArray *oldToNewIndexMap = _update[BTRCollectionViewOldToNewIndexMapKey];
            NSInteger newGlobalIndex = NSNotFound;
            if (oldGlobalIndex >= 0 && oldGlobalIndex < [oldToNewIndexMap count]) {
                newGlobalIndex = [oldToNewIndexMap[oldGlobalIndex] intValue];
            }
            NSIndexPath *newIndexPath = newGlobalIndex == NSNotFound ? nil : [_update[BTRCollectionViewNewModelKey] indexPathForItemAtGlobalIndex:newGlobalIndex];
            NSIndexPath *oldIndexPath = oldGlobalIndex == NSNotFound ? nil : [_update[BTRCollectionViewOldModelKey] indexPathForItemAtGlobalIndex:oldGlobalIndex];
            
            if (newIndexPath) {
				
				
                BTRCollectionViewLayoutAttributes* startAttrs = nil;
                BTRCollectionViewLayoutAttributes* finalAttrs = nil;
                
                startAttrs  = [_layout initialLayoutAttributesForAppearingItemAtIndexPath:oldIndexPath];
                finalAttrs = [_layout layoutAttributesForItemAtIndexPath:newIndexPath];
				
                NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:@{BTRCollectionViewViewKey : view}];
                if (startAttrs) dic[BTRCollectionViewPreviousLayoutInfoKey] = startAttrs;
                if (finalAttrs) dic[BTRCollectionViewNewLayoutInfoKey] = finalAttrs;
				
                [animations addObject:dic];
                BTRCollectionViewItemKey* newKey = [key copy];
                [newKey setIndexPath:newIndexPath];
                newAllVisibleView[newKey] = view;
                
            }
        } else if (key.type == BTRCollectionViewItemTypeSupplementaryView) {
            BTRCollectionViewLayoutAttributes* startAttrs = nil;
            BTRCollectionViewLayoutAttributes* finalAttrs = nil;
			
            startAttrs = view.layoutAttributes;
            finalAttrs = [_layout layoutAttributesForSupplementaryViewOfKind:view.layoutAttributes.representedElementKind atIndexPath:key.indexPath];
			
            NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:@{BTRCollectionViewViewKey:view}];
            if (startAttrs) dic[BTRCollectionViewPreviousLayoutInfoKey] = startAttrs;
            if (finalAttrs) dic[BTRCollectionViewNewLayoutInfoKey] = finalAttrs;
			
            [animations addObject:dic];
            BTRCollectionViewItemKey* newKey = [key copy];
            newAllVisibleView[newKey] = view;
			
        }
    }
    NSArray *allNewlyVisibleItems = [_layout layoutAttributesForElementsInRect:self.visibleRect];
    for (BTRCollectionViewLayoutAttributes *attrs in allNewlyVisibleItems) {
        BTRCollectionViewItemKey *key = [BTRCollectionViewItemKey collectionItemKeyForLayoutAttributes:attrs];
		
        if (key.type == BTRCollectionViewItemTypeCell && ![[newAllVisibleView allKeys] containsObject:key]) {
            BTRCollectionViewLayoutAttributes* startAttrs =
            [_layout initialLayoutAttributesForAppearingItemAtIndexPath:attrs.indexPath];
			
            BTRCollectionReusableView *view = [self createPreparedCellForItemAtIndexPath:attrs.indexPath
                                                                    withLayoutAttributes:startAttrs];
            [self addSubview:view];
            newAllVisibleView[key] = view;
			
            [animations addObject:@{BTRCollectionViewViewKey:view, BTRCollectionViewPreviousLayoutInfoKey: startAttrs?startAttrs:attrs, BTRCollectionViewNewLayoutInfoKey: attrs}];
        }
    }
	
    _allVisibleViewsDict = newAllVisibleView;
	
    for(NSDictionary *animation in animations) {
        BTRCollectionReusableView *view = animation[BTRCollectionViewViewKey];
        BTRCollectionViewLayoutAttributes *attr = animation[BTRCollectionViewPreviousLayoutInfoKey];
        [view applyLayoutAttributes:attr];
    };
    
    
    
	[NSView btr_animate:^{
		_collectionViewFlags.updatingLayout = YES;
		
        [CATransaction begin];
        [CATransaction setAnimationDuration:.3];
        
        // You might wonder why we use CATransaction to handle animation completion
        // here instead of using the completion: parameter of UIView's animateWithDuration:.
        // The problem is that animateWithDuration: calls this completion block
        // when other animations are finished. This means that the block is called
        // after the user releases his finger and the scroll view has finished scrolling.
        // This can be a large delay, which causes the layout of the cells to be greatly
        // delayed, and thus, be unrendered. I assume that was done for performance
        // purposes but it completely breaks our layout logic here.
        // To get the completion block called immediately after the animation actually
        // finishes, I switched to use CATransaction.
        // The only thing I'm not sure about - _completed_ flag. I don't know where to get it
        // in terms of CATransaction's API, so I use animateWithDuration's completion block
        // to call _updateCompletionHandler with that flag.
        // Ideally, _updateCompletionHandler should be called along with the other logic in
        // CATransaction's completionHandler but I simply don't know where to get that flag.
        [CATransaction setCompletionBlock:^{
            // Iterate through all the views that we are going to remove.
            [viewsToRemove enumerateKeysAndObjectsUsingBlock:^(NSNumber *keyObj, NSArray *views, BOOL *stop) {
                BTRCollectionViewItemType type = [keyObj unsignedIntegerValue];
                for (BTRCollectionReusableView *view in views) {
                    if(type == BTRCollectionViewItemTypeCell) {
                        [self reuseCell:(BTRCollectionViewCell *)view];
                    } else if (type == BTRCollectionViewItemTypeSupplementaryView) {
                        [self reuseSupplementaryView:view];
                    } else if (type == BTRCollectionViewItemTypeDecorationView) {
                        [self reuseDecorationView:view];
                    }
                }
            }];
            _collectionViewFlags.updatingLayout = NO;
        }];
        
        for (NSDictionary *animation in animations) {
            BTRCollectionReusableView* view = animation[BTRCollectionViewViewKey];
            BTRCollectionViewLayoutAttributes* attrs = animation[BTRCollectionViewNewLayoutInfoKey];
            [view applyLayoutAttributes:attrs];
        }
        [CATransaction commit];
	} completion:^{		
        if(_updateCompletionHandler) {
            _updateCompletionHandler(YES);
            _updateCompletionHandler = nil;
        }
	}];
}

- (void)setupCellAnimations {
	[self updateVisibleCells];
	[self suspendReloads];
	_collectionViewFlags.updating = YES;
}

- (void)endItemAnimations {
	_updateCount++;
    BTRCollectionViewData *oldCollectionViewData = _collectionViewData;
    _collectionViewData = [[BTRCollectionViewData alloc] initWithCollectionView:self layout:_layout];
	
    [_layout invalidateLayout];
    [_collectionViewData prepareToLoadData];
	
    NSMutableArray *someMutableArr1 = [[NSMutableArray alloc] init];
	
    NSArray *removeUpdateItems = [[self arrayForUpdateAction:BTRCollectionUpdateActionDelete]
                                  sortedArrayUsingSelector:@selector(inverseCompareIndexPaths:)];
	
    NSArray *insertUpdateItems = [[self arrayForUpdateAction:BTRCollectionUpdateActionInsert]
                                  sortedArrayUsingSelector:@selector(compareIndexPaths:)];
	
    NSMutableArray *sortedMutableReloadItems = [[_reloadItems sortedArrayUsingSelector:@selector(compareIndexPaths:)] mutableCopy];
    NSMutableArray *sortedMutableMoveItems = [[_moveItems sortedArrayUsingSelector:@selector(compareIndexPaths:)] mutableCopy];
	
    _originalDeleteItems = [removeUpdateItems copy];
    _originalInsertItems = [insertUpdateItems copy];
	
    NSMutableArray *someMutableArr2 = [[NSMutableArray alloc] init];
    NSMutableArray *someMutableArr3 =[[NSMutableArray alloc] init];
    NSMutableDictionary *operations = [[NSMutableDictionary alloc] init];
	
    for(BTRCollectionViewUpdateItem *updateItem in sortedMutableReloadItems) {
        NSAssert(updateItem.indexPathBeforeUpdate.section< [oldCollectionViewData numberOfSections],
                 @"attempt to reload item (%@) that doesn't exist (there are only %ld sections before update)",
                 updateItem.indexPathBeforeUpdate, (unsigned long)[oldCollectionViewData numberOfSections]);
		
        NSAssert(updateItem.indexPathBeforeUpdate.item<[oldCollectionViewData numberOfItemsInSection:updateItem.indexPathBeforeUpdate.section],
                 @"attempt to reload item (%@) that doesn't exist (there are only %ld items in section %ldd before update)",
                 updateItem.indexPathBeforeUpdate,
                 (unsigned long)[oldCollectionViewData numberOfItemsInSection:updateItem.indexPathBeforeUpdate.section],
                 updateItem.indexPathBeforeUpdate.section);
		
        [someMutableArr2 addObject:[[BTRCollectionViewUpdateItem alloc] initWithAction:BTRCollectionUpdateActionDelete
                                                                          forIndexPath:updateItem.indexPathBeforeUpdate]];
        [someMutableArr3 addObject:[[BTRCollectionViewUpdateItem alloc] initWithAction:BTRCollectionUpdateActionInsert
                                                                          forIndexPath:updateItem.indexPathAfterUpdate]];
    }
	
    NSMutableArray *sortedDeletedMutableItems = [[_deleteItems sortedArrayUsingSelector:@selector(inverseCompareIndexPaths:)] mutableCopy];
    NSMutableArray *sortedInsertMutableItems =  [[_insertItems sortedArrayUsingSelector:@selector(compareIndexPaths:)] mutableCopy];
	
    for(BTRCollectionViewUpdateItem *deleteItem in sortedDeletedMutableItems) {
        if([deleteItem isSectionOperation]) {
            NSAssert(deleteItem.indexPathBeforeUpdate.section<[oldCollectionViewData numberOfSections],
                     @"attempt to delete section (%ld) that doesn't exist (there are only %ld sections before update)",
                     (unsigned long)deleteItem.indexPathBeforeUpdate.section,
                     (unsigned long)[oldCollectionViewData numberOfSections]);
			
            for(BTRCollectionViewUpdateItem *moveItem in sortedMutableMoveItems) {
                if(moveItem.indexPathBeforeUpdate.section == deleteItem.indexPathBeforeUpdate.section) {
                    if(moveItem.isSectionOperation)
                        NSAssert(NO, @"attempt to delete and move from the same section %ld", (unsigned long)deleteItem.indexPathBeforeUpdate.section);
                    else
                        NSAssert(NO, @"attempt to delete and move from the same section (%@)", moveItem.indexPathBeforeUpdate);
                }
            }
        } else {
            NSAssert(deleteItem.indexPathBeforeUpdate.section<[oldCollectionViewData numberOfSections],
                     @"attempt to delete item (%@) that doesn't exist (there are only %ld sections before update)",
                     deleteItem.indexPathBeforeUpdate,
                     (unsigned long)[oldCollectionViewData numberOfSections]);
            NSAssert(deleteItem.indexPathBeforeUpdate.item<[oldCollectionViewData numberOfItemsInSection:deleteItem.indexPathBeforeUpdate.section],
                     @"attempt to delete item (%@) that doesn't exist (there are only %ld items in section %ld before update)",
                     deleteItem.indexPathBeforeUpdate,
                     (unsigned long)[oldCollectionViewData numberOfItemsInSection:deleteItem.indexPathBeforeUpdate.section],
                     (unsigned long)deleteItem.indexPathBeforeUpdate.section);
			
            for(BTRCollectionViewUpdateItem *moveItem in sortedMutableMoveItems) {
                NSAssert([deleteItem.indexPathBeforeUpdate isEqual:moveItem.indexPathBeforeUpdate],
                         @"attempt to delete and move the same item (%@)", deleteItem.indexPathBeforeUpdate);
            }
			
            if(!operations[@(deleteItem.indexPathBeforeUpdate.section)])
                operations[@(deleteItem.indexPathBeforeUpdate.section)] = [NSMutableDictionary dictionary];
			
            operations[@(deleteItem.indexPathBeforeUpdate.section)][BTRCollectionViewDeletedItemsCount] =
            @([operations[@(deleteItem.indexPathBeforeUpdate.section)][BTRCollectionViewDeletedItemsCount] intValue]+1);
        }
    }
	
    for(NSInteger i=0; i<[sortedInsertMutableItems count]; i++) {
        BTRCollectionViewUpdateItem *insertItem = sortedInsertMutableItems[i];
        NSIndexPath *indexPath = insertItem.indexPathAfterUpdate;
		
        BOOL sectionOperation = [insertItem isSectionOperation];
        if(sectionOperation) {
            NSAssert([indexPath section]<[_collectionViewData numberOfSections],
                     @"attempt to insert %ld but there are only %ld sections after update",
                     (unsigned long)[indexPath section], (unsigned long)[_collectionViewData numberOfSections]);
			
            for(BTRCollectionViewUpdateItem *moveItem in sortedMutableMoveItems) {
                if([moveItem.indexPathAfterUpdate isEqual:indexPath]) {
                    if(moveItem.isSectionOperation)
                        NSAssert(NO, @"attempt to perform an insert and a move to the same section (%ld)",(unsigned long)indexPath.section);
                    //                    else
                    //                        NSAssert(NO, @"attempt to perform an insert and a move to the same index path (%@)",indexPath);
                }
            }
			
            NSInteger j=i+1;
            while(j<[sortedInsertMutableItems count]) {
                BTRCollectionViewUpdateItem *nextInsertItem = sortedInsertMutableItems[j];
				
                if(nextInsertItem.indexPathAfterUpdate.section == indexPath.section) {
                    NSAssert(nextInsertItem.indexPathAfterUpdate.item<[_collectionViewData numberOfItemsInSection:indexPath.section],
                             @"attempt to insert item %ld into section %ld, but there are only %ld items in section %ld after the update",
                             (unsigned long)nextInsertItem.indexPathAfterUpdate.item,
                             (unsigned long)indexPath.section,
                             (unsigned long)[_collectionViewData numberOfItemsInSection:indexPath.section],
                             (unsigned long)indexPath.section);
                    [sortedInsertMutableItems removeObjectAtIndex:j];
                }
                else break;
            }
        } else {
            NSAssert(indexPath.item< [_collectionViewData numberOfItemsInSection:indexPath.section],
                     @"attempt to insert item to (%@) but there are only %ld items in section %ld after update",
                     indexPath,
                     (unsigned long)[_collectionViewData numberOfItemsInSection:indexPath.section],
                     (unsigned long)indexPath.section);
			
            if(!operations[@(indexPath.section)])
                operations[@(indexPath.section)] = [NSMutableDictionary dictionary];
			
            operations[@(indexPath.section)][BTRCollectionViewInsertedItemsCount] =
            @([operations[@(indexPath.section)][BTRCollectionViewInsertedItemsCount] intValue]+1);
        }
    }
	
    for(BTRCollectionViewUpdateItem * sortedItem in sortedMutableMoveItems) {
        if(sortedItem.isSectionOperation) {
            NSAssert(sortedItem.indexPathBeforeUpdate.section<[oldCollectionViewData numberOfSections],
                     @"attempt to move section (%ld) that doesn't exist (%ld sections before update)",
                     (unsigned long)sortedItem.indexPathBeforeUpdate.section,
                     (unsigned long)[oldCollectionViewData numberOfSections]);
            NSAssert(sortedItem.indexPathAfterUpdate.section<[_collectionViewData numberOfSections],
                     @"attempt to move section to %ld but there are only %ld sections after update",
                     (unsigned long)sortedItem.indexPathAfterUpdate.section,
                     (unsigned long)[_collectionViewData numberOfSections]);
        } else {
            NSAssert(sortedItem.indexPathBeforeUpdate.section<[oldCollectionViewData numberOfSections],
                     @"attempt to move item (%@) that doesn't exist (%ld sections before update)",
                     sortedItem, (unsigned long)[oldCollectionViewData numberOfSections]);
            NSAssert(sortedItem.indexPathBeforeUpdate.item<[oldCollectionViewData numberOfItemsInSection:sortedItem.indexPathBeforeUpdate.section],
                     @"attempt to move item (%@) that doesn't exist (%ld items in section %ld before update)",
                     sortedItem,
                     (unsigned long)[oldCollectionViewData numberOfItemsInSection:sortedItem.indexPathBeforeUpdate.section],
                     (unsigned long)sortedItem.indexPathBeforeUpdate.section);
			
            NSAssert(sortedItem.indexPathAfterUpdate.section<[_collectionViewData numberOfSections],
                     @"attempt to move item to (%@) but there are only %ld sections after update",
                     sortedItem.indexPathAfterUpdate,
                     (unsigned long)[_collectionViewData numberOfSections]);
            NSAssert(sortedItem.indexPathAfterUpdate.item<[_collectionViewData numberOfItemsInSection:sortedItem.indexPathAfterUpdate.section],
                     @"attempt to move item to (%@) but there are only %ld items in section %ld after update",
                     sortedItem,
                     (unsigned long)[_collectionViewData numberOfItemsInSection:sortedItem.indexPathAfterUpdate.section],
                     (unsigned long)sortedItem.indexPathAfterUpdate.section);
        }
		
        if(!operations[@(sortedItem.indexPathBeforeUpdate.section)])
            operations[@(sortedItem.indexPathBeforeUpdate.section)] = [NSMutableDictionary dictionary];
        if(!operations[@(sortedItem.indexPathAfterUpdate.section)])
            operations[@(sortedItem.indexPathAfterUpdate.section)] = [NSMutableDictionary dictionary];
		
        operations[@(sortedItem.indexPathBeforeUpdate.section)][BTRCollectionViewMovedOutCount] =
        @([operations[@(sortedItem.indexPathBeforeUpdate.section)][BTRCollectionViewMovedOutCount] intValue]+1);
		
        operations[@(sortedItem.indexPathAfterUpdate.section)][BTRCollectionViewMovedInCount] =
        @([operations[@(sortedItem.indexPathAfterUpdate.section)][BTRCollectionViewMovedInCount] intValue]+1);
    }
	
#if !defined  NS_BLOCK_ASSERTIONS
    for(NSNumber *sectionKey in [operations keyEnumerator]) {
        NSInteger section = [sectionKey intValue];
		
        NSInteger insertedCount = [operations[sectionKey][BTRCollectionViewInsertedItemsCount] intValue];
        NSInteger deletedCount = [operations[sectionKey][BTRCollectionViewDeletedItemsCount] intValue];
        NSInteger movedInCount = [operations[sectionKey][BTRCollectionViewMovedInCount] intValue];
        NSInteger movedOutCount = [operations[sectionKey][BTRCollectionViewMovedOutCount] intValue];
		
        NSAssert([oldCollectionViewData numberOfItemsInSection:section]+insertedCount-deletedCount+movedInCount-movedOutCount ==
                 [_collectionViewData numberOfItemsInSection:section],
                 @"invalide update in section %ld: number of items after update (%ld) should be equal to the number of items before update (%ld) "\
                 "plus count of inserted items (%ld), minus count of deleted items (%ld), plus count of items moved in (%ld), minus count of items moved out (%ld)",
                 (long)section,
                 (unsigned long)[_collectionViewData numberOfItemsInSection:section],
                 (unsigned long)[oldCollectionViewData numberOfItemsInSection:section],
                 (long)insertedCount,(long)deletedCount,(long)movedInCount, (long)movedOutCount);
    }
#endif
	
    [someMutableArr2 addObjectsFromArray:sortedDeletedMutableItems];
    [someMutableArr3 addObjectsFromArray:sortedInsertMutableItems];
    [someMutableArr1 addObjectsFromArray:[someMutableArr2 sortedArrayUsingSelector:@selector(inverseCompareIndexPaths:)]];
    [someMutableArr1 addObjectsFromArray:sortedMutableMoveItems];
    [someMutableArr1 addObjectsFromArray:[someMutableArr3 sortedArrayUsingSelector:@selector(compareIndexPaths:)]];
	
    NSMutableArray *layoutUpdateItems = [[NSMutableArray alloc] init];
	
    [layoutUpdateItems addObjectsFromArray:sortedDeletedMutableItems];
    [layoutUpdateItems addObjectsFromArray:sortedMutableMoveItems];
    [layoutUpdateItems addObjectsFromArray:sortedInsertMutableItems];
	
	
    NSMutableArray* newModel = [NSMutableArray array];
    for(NSInteger i=0;i<[oldCollectionViewData numberOfSections];i++) {
        NSMutableArray * sectionArr = [NSMutableArray array];
        for(NSInteger j=0;j< [oldCollectionViewData numberOfItemsInSection:i];j++)
            [sectionArr addObject: @([oldCollectionViewData globalIndexForItemAtIndexPath:[NSIndexPath btr_indexPathForItem:j inSection:i]])];
        [newModel addObject:sectionArr];
    }
	
    for(BTRCollectionViewUpdateItem *updateItem in layoutUpdateItems) {
        switch (updateItem.updateAction) {
            case BTRCollectionUpdateActionDelete: {
                if(updateItem.isSectionOperation) {
                    [newModel removeObjectAtIndex:updateItem.indexPathBeforeUpdate.section];
                } else {
                    [(NSMutableArray*)newModel[updateItem.indexPathBeforeUpdate.section]
                     removeObjectAtIndex:updateItem.indexPathBeforeUpdate.item];
                }
            }break;
            case BTRCollectionUpdateActionInsert: {
                if(updateItem.isSectionOperation) {
                    [newModel insertObject:[[NSMutableArray alloc] init]
                                   atIndex:updateItem.indexPathAfterUpdate.section];
                } else {
                    [(NSMutableArray *)newModel[updateItem.indexPathAfterUpdate.section]
                     insertObject:@(NSNotFound)
                     atIndex:updateItem.indexPathAfterUpdate.item];
                }
            }break;
				
            case BTRCollectionUpdateActionMove: {
                if(updateItem.isSectionOperation) {
                    id section = newModel[updateItem.indexPathBeforeUpdate.section];
                    [newModel insertObject:section atIndex:updateItem.indexPathAfterUpdate.section];
                }
                else {
                    id object = newModel[updateItem.indexPathBeforeUpdate.section][updateItem.indexPathBeforeUpdate.item];
                    [newModel[updateItem.indexPathBeforeUpdate.section] removeObjectAtIndex:updateItem.indexPathBeforeUpdate.item];
                    [newModel[updateItem.indexPathAfterUpdate.section] insertObject:object
                                                                            atIndex:updateItem.indexPathAfterUpdate.item];
                }
            }break;
            default: break;
        }
    }
	
    NSMutableArray *oldToNewMap = [NSMutableArray arrayWithCapacity:[oldCollectionViewData numberOfItems]];
    NSMutableArray *newToOldMap = [NSMutableArray arrayWithCapacity:[_collectionViewData numberOfItems]];
	
    for(NSInteger i=0; i < [oldCollectionViewData numberOfItems]; i++)
        [oldToNewMap addObject:@(NSNotFound)];
	
    for(NSInteger i=0; i < [_collectionViewData numberOfItems]; i++)
        [newToOldMap addObject:@(NSNotFound)];
	
    for(NSInteger i=0; i < [newModel count]; i++) {
        NSMutableArray* section = newModel[i];
        for(NSInteger j=0; j<[section count];j++) {
            NSInteger newGlobalIndex = [_collectionViewData globalIndexForItemAtIndexPath:[NSIndexPath btr_indexPathForItem:j inSection:i]];
            if([section[j] intValue] != NSNotFound)
                oldToNewMap[[section[j] intValue]] = @(newGlobalIndex);
            if(newGlobalIndex != NSNotFound)
                newToOldMap[newGlobalIndex] = section[j];
        }
    }
	
    _update = @{BTRCollectionViewOldModelKey:oldCollectionViewData, BTRCollectionViewNewModelKey:_collectionViewData, BTRCollectionViewOldToNewIndexMapKey:oldToNewMap, BTRCollectionViewNewToOldIndexMapKey:newToOldMap};
	
    [self updateWithItems:someMutableArr1];
	
    _originalInsertItems = nil;
    _originalDeleteItems = nil;
    _insertItems = nil;
    _deleteItems = nil;
    _moveItems = nil;
    _reloadItems = nil;
    _update = nil;
    _updateCount--;
    _collectionViewFlags.updating = NO;
    [self resumeReloads];
}


- (void)updateRowsAtIndexPaths:(NSArray *)indexPaths updateAction:(BTRCollectionUpdateAction)updateAction {
	BOOL updating = _collectionViewFlags.updating;
	if (!updating) [self setupCellAnimations];
	
	NSMutableArray *array = [self arrayForUpdateAction:updateAction];
	[indexPaths enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, NSUInteger idx, BOOL *stop) {
		BTRCollectionViewUpdateItem *updateItem = [[BTRCollectionViewUpdateItem alloc] initWithAction:updateAction forIndexPath:indexPath];
		[array addObject:updateItem];
	}];
	if (!updating) [self endItemAnimations];
}


- (void)updateSections:(NSIndexSet *)sections updateAction:(BTRCollectionUpdateAction)updateAction {
	BOOL updating = _collectionViewFlags.updating;
	if (!updating) {
		[self setupCellAnimations];
	}
	
	NSMutableArray *updateActions = [self arrayForUpdateAction:updateAction];
	NSUInteger section = [sections firstIndex];
	
	[sections enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		BTRCollectionViewUpdateItem *updateItem =
		[[BTRCollectionViewUpdateItem alloc] initWithAction:updateAction
											   forIndexPath:[NSIndexPath btr_indexPathForItem:NSNotFound
																					inSection:section]];
		[updateActions addObject:updateItem];
	}];
	
	if (!updating) {
		[self endItemAnimations];
	}
}
@end


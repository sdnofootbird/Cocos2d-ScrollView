//
//  FGScrollLayer.m
//  Fall G
//
//  Created by Dai Xuefeng on 23/9/12.
//  Copyright 2012 Nofootbird. 
//

#import "FGScrollLayer.h"


enum
{
	kFGScrollLayerStateIdle,
	kFGScrollLayerStateSliding,
};

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
@interface CCTouchDispatcher (targetedHandlersGetter)

- (id<NSFastEnumeration>) targetedHandlers;

@end

@implementation CCTouchDispatcher (targetedHandlersGetter)

- (id<NSFastEnumeration>) targetedHandlers
{
	return targetedHandlers;
}

@end
#endif

@implementation FGScrollLayer

@synthesize delegate = delegate_;
@synthesize minimumTouchLengthToSlide = minimumTouchLengthToSlide_;
@synthesize pagesOffset = pagesOffset_;
@synthesize pages = layers_;
@synthesize stealTouches = stealTouches_;
@synthesize pageHeight = pageHeight_;
@synthesize pageWidth = pageWidth_;

- (int) totalPagesCount
{
	return [layers_ count];
}

+(id) nodeWithLayers:(NSArray *)layers pageSize:(CGSize)pageSize pagesOffset:(int)pOffset visibleRect:(CGRect)rect{
	return [[[self alloc] initWithLayers: layers pageSize:pageSize pagesOffset:pOffset visibleRect:rect] autorelease];
}

-(id) initWithLayers:(NSArray *)layers pageSize:(CGSize)pageSize pagesOffset:(int)pOffset visibleRect:(CGRect)rect{
	if ( (self = [super init]) )
	{
		NSAssert([layers count], @"FGScrollLayer#initWithLayers:widthOffset: you must provide at least one layer!");
		
		// Enable Touches/Mouse.
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
		self.isTouchEnabled = YES;
#endif
		
		self.stealTouches = YES;
		
		// Set default minimum touch length to scroll.
		self.minimumTouchLengthToSlide = 30.0f;
		
		// Save offset.
		self.pagesOffset = pOffset;
		
		// Save array of layers.
		layers_ = [[NSMutableArray alloc] initWithArray:layers copyItems:NO];
        
        // Save pages size for later calculation
        pageHeight_ = pageSize.height;
        pageWidth_ = pageSize.width;
        maxVerticalPos_ = pageHeight_ * [layers_ count] - rect.size.height + 5;
        
        realBound = rect;
        
		[self updatePages];
		
	}
	return self;
}

- (void) dealloc
{
	self.delegate = nil;
	
	[layers_ release];
	layers_ = nil;
	
	[super dealloc];
}

- (void) updatePages
{
	// Loop through the array and add the screens if needed.
	int i = 0;
	for (CCLayer *l in layers_)
	{
		l.position = ccp(realBound.origin.x,  realBound.origin.y + (realBound.size.height - i * (pageHeight_ - self.pagesOffset)));
		if (!l.parent)
			[self addChild:l];
		i++;
	}
    [self updatePagesAvailability];
}

/**
 * According to current position, decide which pages are visible
 */
-(void)updatePagesAvailability{
    CGPoint currentPos = [self position];
    if (currentPos.y > 0) {
        int visibleBoundUp = currentPos.y / pageHeight_;
        visibleBoundUp = MIN([layers_ count], visibleBoundUp);
        for (int i = 0; i < visibleBoundUp; i++) {
            [[layers_ objectAtIndex:i] setVisible:NO];
        }
        if (visibleBoundUp < [layers_ count]) {
            int visibleBoundDown = (currentPos.y + realBound.size.height) / pageHeight_;
            visibleBoundDown = MIN([layers_ count] - 1, visibleBoundDown);
            for (int i = visibleBoundUp; i <= visibleBoundDown; i++) {
                [[layers_ objectAtIndex:i] setVisible:YES];
            }
            if (visibleBoundDown < [layers_ count] - 1) {
                for (int i = visibleBoundDown + 1; i <= [layers_ count] - 1; i++) {
                    [[layers_ objectAtIndex:i] setVisible:NO];
                }
            }
        }
    }
    else if (currentPos.y <= 0){
        CGFloat gapY = -currentPos.y;
        int visibleBound = (realBound.size.height - gapY) / pageHeight_;
        // index visibleBound itself should be invisible
        if (visibleBound < 0) {
            for (int i = 0; i < [layers_ count]; i++) {
                [[layers_ objectAtIndex:i] setVisible:NO];
            }
            return;
        }
        visibleBound = MIN([layers_ count] - 1, visibleBound);
        for (int i = 0; i <= visibleBound; i++) {
            [[layers_ objectAtIndex:i] setVisible:YES];
        }
        for (int i = visibleBound + 1; i < [layers_ count]; i++) {
            [[layers_ objectAtIndex:i] setVisible:NO];
        }
    }
}

-(void)setRealBound:(CGPoint)position size:(CGPoint)size{
    realBound = CGRectMake(position.x, position.y, size.x, size.y);
}

-(void)setPosition:(CGPoint)position{
    [super setPosition:position];
    [self updatePagesAvailability];
    CGFloat scrollBlockDesiredY = scrollBlockUpperBound - (scrollBlockUpperBound - scrollBlockLowerBound) * position.y / maxVerticalPos_;
    if (scrollBlockDesiredY > scrollBlockUpperBound) {
        scrollBlockDesiredY = scrollBlockUpperBound;
    }else if (scrollBlockDesiredY < scrollBlockLowerBound){
        scrollBlockDesiredY = scrollBlockLowerBound;
    }
    [scrollBlock setPosition:ccp([scrollBlock position].x, scrollBlockDesiredY - position.y)];
    [lowerBound setPosition:ccp([lowerBound position].x, lowerBoundPosY - position.y)];
    [upperBound setPosition:ccp([upperBound position].x, upperBoundPosY - position.y)];
    [scrollBar setPosition:ccp([scrollBar position].x, scrollBarPosY - position.y)];
}

#pragma mark Moving To / Selecting Pages

-(void) moveToPage:(int)page
{
    if (page < 0 || page >= [layers_ count]) {
        CCLOGERROR(@"FGScrollLayer#moveToPage: %d - wrong page number, out of bounds. ", page);
		return;
    }
    
    CGFloat desiredPos = page * pageHeight_;
    if (desiredPos > maxVerticalPos_) {
        desiredPos = maxVerticalPos_;
    }
    
    [self runAction:[CCMoveTo actionWithDuration:0.3 position:ccp([self position].x, desiredPos)]];
    
}

#pragma mark Touches
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED

/** Register with more priority than CCMenu's but don't swallow touches. */
-(void) registerWithTouchDispatcher
{
#if COCOS2D_VERSION >= 0x00020000
    CCTouchDispatcher *dispatcher = [[CCDirector sharedDirector] touchDispatcher];
    int priority = kCCMenuHandlerPriority - 1;
#else
    CCTouchDispatcher *dispatcher = [CCTouchDispatcher sharedDispatcher];
    int priority = kCCMenuTouchPriority - 1;
#endif
    
	[dispatcher addTargetedDelegate:self priority: priority swallowsTouches:NO];
}

/** Hackish stuff - stole touches from other CCTouchDispatcher targeted delegates.
 Used to claim touch without receiving ccTouchBegan. */
- (void) claimTouch: (UITouch *) aTouch
{
#if COCOS2D_VERSION >= 0x00020000
    CCTouchDispatcher *dispatcher = [[CCDirector sharedDirector] touchDispatcher];
#else
    CCTouchDispatcher *dispatcher = [CCTouchDispatcher sharedDispatcher];
#endif
    
	// Enumerate through all targeted handlers.
	for ( CCTargetedTouchHandler *handler in [dispatcher targetedHandlers] )
	{
		// Only our handler should claim the touch.
		if (handler.delegate == self)
		{
			if (![handler.claimedTouches containsObject: aTouch])
			{
				[handler.claimedTouches addObject: aTouch];
			}
		}
        else
        {
            // Steal touch from other targeted delegates, if they claimed it.
            if ([handler.claimedTouches containsObject: aTouch])
            {
                if ([handler.delegate respondsToSelector:@selector(ccTouchCancelled:withEvent:)])
                {
                    [handler.delegate ccTouchCancelled: aTouch withEvent: nil];
                }
                [handler.claimedTouches removeObject: aTouch];
            }
        }
	}
}

-(void)ccTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event
{
    [scrollBar setVisible:NO];
    [scrollBlock setVisible:NO];
    
    if( scrollTouch_ == touch ) {
        scrollTouch_ = nil;
    }
}

// these two variables are to make a sliding effect on scroll view
static CGFloat previousTouchPointY = -1;
static CGFloat moveSpeed = 0;
-(BOOL) ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event
{
	if( scrollTouch_ == nil ) {
		scrollTouch_ = touch;
	} else {
		return NO;
	}
	
	CGPoint touchPoint = [touch locationInView:[touch view]];
	touchPoint = [[CCDirector sharedDirector] convertToGL:touchPoint];
	
	startSwipe_ = touchPoint.y;
    startSwipeLayerPos_ = [self position].y;
	state_ = kFGScrollLayerStateIdle;
	return YES;
}

- (void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event
{
	if( scrollTouch_ != touch ) {
		return;
	}
	
	CGPoint touchPoint = [touch locationInView:[touch view]];
	touchPoint = [[CCDirector sharedDirector] convertToGL:touchPoint];
	
	
	// If finger is dragged for more distance then minimum - start sliding and cancel pressed buttons.
	// Of course only if we not already in sliding mode
	if ( (state_ != kFGScrollLayerStateSliding)
		&& (fabsf(touchPoint.y-startSwipe_) >= self.minimumTouchLengthToSlide) )
	{
		state_ = kFGScrollLayerStateSliding;
		
		// Avoid jerk after state change.
		startSwipe_ = touchPoint.y;
		startSwipeLayerPos_ = [self position].y;
        previousTouchPointY = touchPoint.y;
        
		if (self.stealTouches)
        {
			[self claimTouch: touch];
        }
		
		if ([self.delegate respondsToSelector:@selector(scrollLayerScrollingStarted:)])
		{
			[self.delegate scrollLayerScrollingStarted: self];
		}
	}
	
	if (state_ == kFGScrollLayerStateSliding)
	{
		CGFloat desiredY = startSwipeLayerPos_ + touchPoint.y - startSwipe_;
        [self setPosition:ccp(0, desiredY)];
        
        // enable scroll bar to be visible
        [scrollBar setVisible:YES];
        [scrollBlock setVisible:YES];
        
        // update scrolling effect variables
        moveSpeed = touchPoint.y - previousTouchPointY;
        previousTouchPointY = touchPoint.y;
	}
}

/**
 * After touching, generate an inertia effect.
 */
- (void)moveToDesiredPos:(CGFloat)desiredY{
    CCAction* slidingAction = nil;
    if (desiredY > maxVerticalPos_) {
        slidingAction = [CCSequence actions:[CCMoveTo actionWithDuration:0.10 position:ccp([self position].x, desiredY)], [CCMoveTo actionWithDuration:0.15 position:ccp([self position].x, maxVerticalPos_)], nil];
    }
    else if (desiredY < 0){
        slidingAction = [CCSequence actions:[CCMoveTo actionWithDuration:0.10 position:ccp([self position].x, desiredY)],[CCMoveTo actionWithDuration:0.15 position:ccp([self position].x, 0)], nil];
    }
    else{
        CGFloat interPosY = (desiredY - [self position].y) * 0.7 + [self position].y;
        slidingAction = [CCSequence actions:[CCMoveTo actionWithDuration:0.15 position:ccp([self position].x, interPosY)],[CCMoveTo actionWithDuration:0.3 position:ccp([self position].x, desiredY)], nil];
    }
    [self runAction:slidingAction];
}

- (void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event
{
    [scrollBar setVisible:NO];
    [scrollBlock setVisible:NO];
    
	if( scrollTouch_ != touch )
		return;
	scrollTouch_ = nil;

    if (ABS(moveSpeed) > 10) {
        CGFloat desiredDesY = [self position].y + moveSpeed * 5;
        [self moveToDesiredPos:desiredDesY];
    }
    else{
        if ([self position].y > maxVerticalPos_) {
            [self runAction:[CCMoveTo actionWithDuration:0.3 position:ccp([self position].x, maxVerticalPos_)]];
        }else if ([self position].y < 0){
            [self runAction:[CCMoveTo actionWithDuration:0.3 position:ccp([self position].x, 0)]];
        }
    }
    
    // restore scrolling effect variables to default value
    moveSpeed = 0;
    previousTouchPointY = -1;
}

#endif

@end

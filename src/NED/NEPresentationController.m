//
//  NEPresentationController.m
//  BARTPresentation
//
//  Created by Oliver Zscheyge on 4/6/10.
//  Copyright 2010 MPI Cognitive and Human Brain Scienes Leipzig. All rights reserved.
//


//internal presentation stuff
#import "NEPresentationController.h"
#import "NEMediaText.h"
#import "NEStimEvent.h"
#import "NEPresentationLogger.h"
#import "NELogFormatter.h"
#import "NEViewManager.h"
#import "NEPresentationExternalConditionController.h"

//Feedback stuff
#import "NEFeedbackHeli.h"
#import "NEFeedbackThermo.h"

//config 
#import "COExperimentContext.h"


/** The time interval for one update tick in milliseconds. */
#define TICK_TIME 1
/** The time interval for the update in seconds.*/
static const NSTimeInterval UPDATE_INTERVAL = TICK_TIME * 0.001;

/* notifications about the adapted design */
NSString * const BARTPresentationAddedEventsNotification = @"de.mpg.cbs.BARTPresentationAddedEventNotification";


/* Simple tuple class because Cocoa lacks one... */
@interface _NETuple : NSObject
{
    id first;
    id second;
}

@property (readonly) id first;
@property (readonly) id second;

-(id)initWithFirst:(id)fst 
         andSecond:(id)snd;

@end

@implementation _NETuple

@synthesize first;
@synthesize second;

-(id)initWithFirst:(id)fst 
         andSecond:(id)snd
{
    if ((self = [super init])) {
        first  = [fst retain];
        second = [snd retain];
    }
    
    return self;
}

-(void)dealloc
{
    [first release];
    [second release];
    [super dealloc];
}

@end
/* END Tuple class. */


@interface NEPresentationController (PrivateMethods)



/**
 * Entry point for mUpdateThread: creates an autorelease 
 * pool, continuously updates the timetable and views unti
 * the presentation is over and finally cleans the thread.
 */
-(void)runUpdateThread;

/**
 * Simulates one time tick (currently 20ms).
 */
-(void)tick;

/**
 * Integrates all events from mChangedEvents into mTimetable
 * (and removes those from mChangedEvents).
 */
-(void)updateTimetable;

/**
 * Handles events starting at mTime (submits the media object
 * to the PresentationView and adds to event to mEventsToEnd).
 */
-(void)handleStartingEvents;

/**
 * Handles events ending at mTime (removing the media object
 * from the PresentationView).
 */
-(void)handleEndingEvents;

/**
 * Resets all time and trigger measuring variables to 0.
 */
-(void)resetTimeAndTriggerCount;

/**
 * checks for the fullfillment of the external conditions
 */
-(NSDictionary*)checkForExternalConditionsForEvent:(NEStimEvent*)event;

/**
 * starts the updateThread ,i.e. the real start of the presentation
 */
-(void)startPresentation;

-(void)doActionOnTimeTable:(NSDictionary*)action 
       withResultVariables:(NSDictionary*)resVariables
                   atEvent:(NEStimEvent*)currentEvent;

@end


@implementation NEPresentationController

@synthesize mTriggerCount = _mTriggerCount;
@synthesize mLastTriggersTime = _mLastTriggersTime;
@synthesize mExternalConditionController = _mExternalConditionController;
@synthesize mTR = _mTR;
@synthesize mPresentTimeUnit = _mPresentTimeUnit;


-(id)initWithView:(NEViewManager*)view
     andTimetable:(NETimetable*)timetable
{
    if ((self = [super init])) {
        mViewManager = [view retain];
        mTimetable = [timetable retain];
        
        if ([[[[COExperimentContext getInstance] systemConfig] getProp:@"$timeUnit"] isEqualToString:@"milliseconds"]){
			_mPresentTimeUnit = PRES_TIME_MS;}
		else {
			NSLog(@"timeUnit in configuration is NOT milliseconds!");
            return nil;
        }

        
        mEventsToEnd       = [[NSMutableArray alloc] initWithCapacity:0];
        mAddedEvents       = [[NSMutableArray alloc] initWithCapacity:0];
        mLockAddedEvents   = [[NSLock alloc] init];
        mChangedEvents     = [[NSMutableArray alloc] initWithCapacity:0];
        mLockChangedEvents = [[NSLock alloc] init];
        
        mLogger = [NEPresentationLogger getInstance];
        
        mUpdateThread = [[NSThread alloc] initWithTarget:self selector:@selector(runUpdateThread) object:nil];
        _mTR           = (NSUInteger) [[[[COExperimentContext getInstance] systemConfig] getProp:@"$TR"] integerValue];
        
         [self resetTimeAndTriggerCount];
        
        [mViewManager setTimetable:mTimetable];
        [mViewManager setController:self];
        
        //register itself as an observer for the trigger messages from the sacnner
        COExperimentContext *expContext = [COExperimentContext getInstance];
        [expContext addOberserver:self forProtocol:@"BARTScannerTriggerProtocol"];
        [expContext addOberserver:self forProtocol:@"BARTButtonPressProtocol"];
        
        // TODO: hard-coded! get info from elsewhere!
//        // Helicopter feedback.
//        NSRect feedbackRect = NSMakeRect(200.0, 200.0, 400.0, 200.0);
//        NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys:@"0.0", @"minHeight",
//                                                                          @"100.0", @"maxHeight",
//                                                                          @"0.0", @"minFirerate",
//                                                                          @"3.0", @"maxFirerate", nil];
//        NEFeedbackObject* feedback = [[NEFeedbackHeli alloc] initWithFrame:feedbackRect
//                                                               andParameters:params];
//        [mViewManager setFeedback:feedback];
//        [feedback release];
        
//        // Thermometer feedback.
//        NSRect feedbackRect = NSMakeRect(350.0, 50.0, 100.0, 500.0);
//        NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys:@"0.0", @"minTemperature",
//                                                                          @"50.0", @"maxTemperature", nil];
//        NEFeedbackObject* feedback = [[NEFeedbackThermo alloc] initWithFrame:feedbackRect
//                                                               andParameters:params];
//        [mViewManager setFeedback:feedback];
//        [feedback release];
    }
    
    return self;
}

-(void)dealloc
{
    [mViewManager release];
    [mTimetable release];
    
    [mEventsToEnd release];
    [mChangedEvents release];
    [mLockChangedEvents release];
    [mAddedEvents release];
    [mLockAddedEvents release];
    
    [mUpdateThread release];
    
    [super dealloc];
}

-(void)triggerArrived:(NSNotification*)aNotification
{
    if (0 == [[aNotification object] unsignedLongValue])
    {
        [self startPresentation];
    }

    NSUInteger triggerCount = _mTriggerCount + 1;//tr
  
    [mLogger logTrigger:triggerCount withTime:mTime];
    
    [self setTriggerCount:triggerCount];
    [self setLastTriggerTime:[NSDate timeIntervalSinceReferenceDate]];
}

-(void)buttonWasPressed:(NSNotification *)aNotification
{
   // NSString *toLog = [NSString stringWithFormat:@"Button pressed: %u", [[aNotification object] unsignedCharValue]];
    [mLogger logButtonPress:[[aNotification object] unsignedIntegerValue] withTrigger:_mTriggerCount andTime:mTime];
    //[mLogger log:toLog withTime:mTime];
}

-(void)requestAdditionOfEventWithTime:(NSUInteger)t 
                             duration:(NSUInteger)dur 
                     andMediaObjectID:(NSString*)mID
{
    if (t < mTime) {
        return;
    }
    
    NEMediaObject *mediaObj = [mTimetable getMediaObjectByID:mID];
    NEStimEvent* event = [[NEStimEvent alloc] initWithTime:t 
                                                  duration:dur 
                                               mediaObject:mediaObj];
    if ([mUpdateThread isExecuting]) {
        [mLockAddedEvents lock];
        [mAddedEvents addObject:event];
        [mLockAddedEvents unlock];
        
    } else {
        [mTimetable addEvent:event];
        [mViewManager updateTimeline];
    }
    [event release];
    return;
}

-(void)enqueueEvent:(NEStimEvent*)newEvent
   asReplacementFor:(NEStimEvent*)oldEvent
{
    if ([mUpdateThread isExecuting]) {
        _NETuple* tuple = [[_NETuple alloc] initWithFirst:oldEvent andSecond:newEvent];
        [mLockChangedEvents lock];
        [mChangedEvents addObject:tuple];
        [mLockChangedEvents unlock];
        [tuple release];
    } else {
        [mTimetable replaceEvent:oldEvent 
                       withEvent:newEvent];
    }
}

-(NSUInteger)presentationDuration
{
    return [mTimetable duration];
}

-(void)startListeningForTrigger
{
    if (![mUpdateThread isExecuting] 
        && ![mUpdateThread isCancelled]) {
        
        [self resetTimeAndTriggerCount];
       
    }
}

-(void)pausePresentation
{
    if ([mUpdateThread isExecuting]) {
        [mUpdateThread cancel];
        [mViewManager pausePresentation];
    }
}

-(void)stopPresentation
{
    if ([mUpdateThread isExecuting]) {
        [mUpdateThread cancel];
        [mViewManager pausePresentation];
    }
}

-(void)startPresentation
{
    _mLastTriggersTime = [NSDate timeIntervalSinceReferenceDate];
    [mUpdateThread start];
}


-(void)continuePresentation
{
    if ([mUpdateThread isFinished]) {
        [mUpdateThread release];
        mUpdateThread = [[NSThread alloc] initWithTarget:self selector:@selector(runUpdateThread) object:nil];
        [mUpdateThread start];
        [mViewManager continuePresentation];
    }
}

-(void)resetPresentationToOriginal:(BOOL)toOriginalEvents
{
    if ([mUpdateThread isExecuting] || [mUpdateThread isFinished]) {
        [mUpdateThread cancel];
        while (![mUpdateThread isFinished]) ; // Wait until run thread is finished.
    }
    
    [mUpdateThread release];
    mUpdateThread = [[NSThread alloc] initWithTarget:self selector:@selector(runUpdateThread) object:nil];
    [self resetTimeAndTriggerCount];
    [mEventsToEnd removeAllObjects];
    
    [mViewManager resetPresentation];

    if (toOriginalEvents) {
        [mTimetable resetTimetableToOriginalEvents];
    } else {
        [mTimetable resetTimetable];
    }
    
    /** BEGIN Test log output
     *
     * TODO: place elsewere and get tolerance from config!
     */
    printf("### Log ###\n");
    
    NSString *p = [[[COExperimentContext getInstance] systemConfig] getProp:@"$logFolder"];
    
    [mLogger printToFile:@"BARTPresentationLogfile" atPath:p];
    [mLogger print];
    printf("\n");
    
//    printf("### Violations ###\n");
//    for (NSString* violationMsg in [mLogger allMessagesViolatingTolerance:7]) {
//        printf("%s\n", [violationMsg cStringUsingEncoding:NSUTF8StringEncoding]);
//    }
//    NSUInteger over100 = [[mLogger allMessagesViolatingTolerance:100] count] / 2;
//    printf(">100: %ld\n", over100);
//    NSUInteger over20  = [[mLogger allMessagesViolatingTolerance:20] count] / 2 - over100;
//    printf(">20:  %ld\n", over20);
//    NSUInteger over7   = [[mLogger allMessagesViolatingTolerance:7] count] / 2 - (over20 + over100);
//    printf(">7:   %ld\n", over7);
    [mLogger clear];
    /** END Test log output. */
}

-(void)runUpdateThread
{
    NSAutoreleasePool* autoreleasePool = [[NSAutoreleasePool alloc] init];

    [mUpdateThread setThreadPriority:1.0];
//    NSLog(@"IAMTRIGGERCOUNT: %lu", _mTriggerCount);
    while (_mTriggerCount == 0) {
        usleep(1);
        // TODO: find suitable sleep interval!
    }
    
    do {
        [self tick];
        [NSThread sleepForTimeInterval:UPDATE_INTERVAL];
    } while (![[NSThread currentThread] isCancelled]);
        
    
    NSLog(@"AP IN THREAD:%@", autoreleasePool);
    [autoreleasePool drain];
    autoreleasePool = nil;
    
    //[NSThread exit];
}

-(void)tick
{
    mCurrentTicksTime = [NSDate timeIntervalSinceReferenceDate];
    NSUInteger timeDifference = (NSUInteger) ((mCurrentTicksTime - _mLastTriggersTime) * 1000.0);
    
    if (mTime <= [mTimetable duration]) {
        if (timeDifference < _mTR - TICK_TIME) {
            mTime = (_mTriggerCount - 1) * _mTR + timeDifference;
        }
        
        //ask for conditions
        NEStimEvent *event = [mTimetable previewNextEventAtTime:mTime];
     
        //evaluate external condition
        NSDictionary* externalCondition = [[self checkForExternalConditionsForEvent:event] retain];
        
        
        if (nil != externalCondition)
        {
            BOOL isConditionFullfilled = YES;
            for (NSString *s in [externalCondition objectForKey:@"conditionsArray"])
            {
                isConditionFullfilled = isConditionFullfilled && [s boolValue];
            }
            if (YES == isConditionFullfilled)
            {
                for (NSDictionary *action in [externalCondition objectForKey:@"actionsThen"])
                {
                    [self doActionOnTimeTable:action 
                          withResultVariables:[externalCondition objectForKey:@"resultVariables"] 
                                      atEvent:event];
                }
            }
            else
            {
                for (NSDictionary *action in [externalCondition objectForKey:@"actionsElse"])
                {
                    [self doActionOnTimeTable:action 
                          withResultVariables:[externalCondition objectForKey:@"resultVariables"]
                                      atEvent:event];
                }
            }
            [externalCondition release];
        }
        
        
        
        [mViewManager setCurrentTime:mTime];
        
        [self updateTimetable];
        [self handleStartingEvents];
        [self handleEndingEvents];
        [mViewManager displayPresentationView];
        
    } else {
        [mUpdateThread cancel];
    }
}

-(NSDictionary*)checkForExternalConditionsForEvent:(NEStimEvent *)event
{
    if (NO == [[event mediaObject] isDependentFromConstraint])
    {
        return nil;
    }
    
    
    NSDictionary *dictReturn = nil;
    dictReturn = [[_mExternalConditionController checkConstraintForID:[[event mediaObject] getConstraintID]] retain];
    if (nil != dictReturn)
    {
        return [dictReturn autorelease];
    }
    return nil;
}

-(void)doActionOnTimeTable:(NSDictionary*)action withResultVariables:(NSDictionary*)resVariables atEvent:(NEStimEvent*)currentEvent
{
    
    NSString* fName = [action objectForKey:@"functionNameInternal"];
    NSArray *attArray = [action objectForKey:@"attributesArray"];
    NSString* toLog = [NSString stringWithFormat:@"%@ " , fName];
    
    if (NSOrderedSame == [fName compare:@"replaceMediaObject"])
    {
        for (NSDictionary *att in attArray){
            if ( NSOrderedSame == [[att objectForKey:@"attributeType"] compare:@"mediaObjectRef" options:NSCaseInsensitiveSearch])
            {
                NSString *oldMO = [[currentEvent mediaObject] getID];
                NEMediaObject *mediaObj = [mTimetable getMediaObjectByID:[att objectForKey:@"attributeValue"]];
                NEStimEvent *newEvent = [[NEStimEvent alloc] initWithTime:[currentEvent time] 
                                                                 duration:[currentEvent duration] 
                                                              mediaObject:mediaObj];
                [self enqueueEvent:newEvent asReplacementFor:currentEvent];
                [newEvent release];
                toLog = [toLog stringByAppendingFormat:@"%@ with %@", oldMO, [mediaObj getID] ];
                [mLogger logAction:toLog withTrigger:_mTriggerCount andTime:mTime];
                return;
            }
        }
        return;
    }
    if (NSOrderedSame == [fName compare:@"setMediaObjectParamter"])
    {
        NSString *paraName = nil;
        float paraVal = 0.0;
        
        
        for (NSDictionary *att in attArray){
            if (NSOrderedSame == [[att objectForKey:@"attributeType"] compare:@"Name" options:NSCaseInsensitiveSearch])
            {
                paraName = [att objectForKey:@"attributeValue"];
            }
            else if (NSOrderedSame == [[att objectForKey:@"attributeType"] compare:@"systemVariableRef" options:NSCaseInsensitiveSearch])
            {
                NSString *key = [att objectForKey:@"attributeValue"];
                paraVal = [[resVariables objectForKey:key] floatValue];
            }
            toLog = [toLog stringByAppendingFormat:@"%@ ",paraName];
            toLog = [toLog stringByAppendingFormat:@"with %.2f", paraVal];
        }
        [mLogger logAction:toLog withTrigger:_mTriggerCount andTime:mTime];
        
        NEMediaObject *mo = [currentEvent mediaObject];
        NSPoint p = NSMakePoint([mo position].x, [mo position].y);
        if ( (nil != paraName) && (0 < [paraName rangeOfString:@"posX"].length) )
        {
            p.x = paraVal;
        }
        if ( (nil != paraName) && (0 < [paraName rangeOfString:@"posY"].length) )
        {
            p.y = paraVal;
        }
        
        [mo setPosition:p];


        return;
    }
    
    if (NSOrderedSame == [fName compare:@"removeCurrentStimulusEvent"])
    {
        //TODO
        return;
    }
    
    if (NSOrderedSame == [fName compare:@"insertNewStimulusEvent"])
    {
     
        NSUInteger duration = 0;
        NSString *moRef = nil;
        BOOL pushAllEvents = NO;
        for (NSDictionary *att in attArray)
        {
            if (NSOrderedSame == [[att objectForKey:@"attributeType"] compare:@"mediaObjectRef" options:NSCaseInsensitiveSearch])
            {
                moRef = [att objectForKey:@"attributeValue"];
            }
            else if (NSOrderedSame == [[att objectForKey:@"attributeType"] compare:@"durationTime" options:NSCaseInsensitiveSearch])
            {
                duration = [[att objectForKey:@"attributeValue"] floatValue];
            }
            else if (NSOrderedSame == [[att objectForKey:@"attributeType"] compare:@"pushFlag" options:NSCaseInsensitiveSearch])
            {
                pushAllEvents = [[att objectForKey:@"attributeValue"] boolValue];
            }
        
        }
        
        
        
        //TODO
        //[self  requestAdditionOfEventWithTime:[currentEvent time] duration:duration andMediaObjectID:moRef]; 
        
        if (YES == pushAllEvents){
            [mTimetable shiftOnsetForAllEventsToHappen:(NSUInteger)duration];
            toLog = [toLog stringByAppendingFormat:@" %@ push %lu ms", moRef, (NSUInteger)duration];
        }
        else{
            toLog = [toLog stringByAppendingFormat:@" %@ no push", moRef];
        }
        [mLogger logAction:toLog withTrigger:_mTriggerCount andTime:mTime];
        return;
    }
    return;
    
}

-(void)updateTimetable
{
    // Add events.
    [mLockAddedEvents lock];
    for (NEStimEvent* event in mAddedEvents) {
        [mTimetable addEvent:event];
    }
    [mAddedEvents removeAllObjects];
    [mLockAddedEvents unlock];
    
    // Replace events.
    [mLockChangedEvents lock];
    for (_NETuple* eventTuple in mChangedEvents) {
        [mTimetable replaceEvent:[eventTuple first] 
                       withEvent:[eventTuple second]];
    }
    [mChangedEvents removeAllObjects];
    [mLockChangedEvents unlock];
    
    // Remove events.
    // TODO: implement removal of events.
}

-(void)handleStartingEvents
{
    NSMutableArray* arrayAllStartingEvents = [[NSMutableArray alloc] initWithCapacity:2];
    NEStimEvent* event = [mTimetable nextEventAtTime:mTime];
    while (event) {
        
        [mViewManager present:[event mediaObject]];
        [NEStimEvent endTimeSortedInsertOf:event 
                               inEventList:mEventsToEnd];
        [mLogger logStartingEvent:event withTrigger:_mTriggerCount andTime:mTime];
        
        if (nil != event)
        {
            if(YES == [[event mediaObject] isAssignedToRegressor])
            {
                [arrayAllStartingEvents addObject:event];
            }
        }
        
        event = [mTimetable nextEventAtTime:mTime];
    }
    
    if ( 0 != [arrayAllStartingEvents count])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:BARTPresentationAddedEventsNotification object:[arrayAllStartingEvents autorelease]];
    }
    else{
        [arrayAllStartingEvents release];
    }
}

-(void)handleEndingEvents
{
    BOOL done = NO;
    while ([mEventsToEnd count] > 0
           && !done) {
        NEStimEvent* event = [mEventsToEnd objectAtIndex:0];
        if (([event time] + [event duration]) <= mTime) {
            
            [mViewManager stopPresentationOf:[event mediaObject]];
            [mEventsToEnd removeObject:event];
            [mLogger logEndingEvent:event withTrigger:_mTriggerCount andTime:mTime];
            
        } else {
            done = YES;
        }
    }
}

-(void)resetTimeAndTriggerCount
{
    mTime = 0;
    [self setTriggerCount:0];
    //[mLogger printToFilePath:@"/tmp/MyLogFile.log"];
}



-(void)terminusFromScannerArrived:(NSNotification *)msg
{
    NSLog(@"%@", msg);
    //[self resetPresentationToOriginal:NO];
}

@end
